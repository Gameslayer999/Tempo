import AppKit
import CoreAudio
import Foundation

/// One app that is audibly playing right now *and* that Tempo can actually
/// pause. Both halves matter: a row for an app Tempo cannot silence would be a
/// control that does nothing (UI Principle #4), so the route is part of the
/// identity rather than something discovered at click time.
struct AudioSource: Identifiable, Equatable {
    /// How this particular app gets paused. See `AudioSourcesService` for why
    /// there are two routes and no third.
    enum PauseRoute: Equatable {
        /// The app is the current MediaRemote now-playing client, so the
        /// framework's `pause` command lands on it. This is the only route
        /// that reaches a browser tab.
        case mediaRemote
        /// The app answers an AppleScript `pause`. Works regardless of who
        /// holds now-playing, which is the whole point: the *older* player is
        /// never the now-playing client once something else starts.
        case appleScript(application: String)
    }

    let bundleID: String
    let name: String
    let route: PauseRoute
    /// Whether this is the app MediaRemote currently considers now-playing —
    /// i.e. the one the existing transport row already controls. Drives the
    /// row's ordering and its "playing here" emphasis.
    let isNowPlaying: Bool

    var id: String { bundleID }
}

/// Which apps are making sound right now, and pausing one of them by name
/// (decision 099).
///
/// **Why this service exists at all.** MediaRemote — everything
/// `MediaRemoteService` drives — models the machine as having exactly *one*
/// now-playing client. Its `pause` command carries no app target (verified in
/// the vendored adapter's `src/adapter/send.m`: `MRMediaRemoteSendCommand`
/// takes a command and a userInfo dictionary, nothing else), so it always hits
/// whichever app took over last. That is precisely the app you *don't* want to
/// pause when Spotify is still playing underneath a YouTube video.
///
/// **Detection.** The Core Audio HAL knows the real answer: every process with
/// an active output stream appears in `kAudioHardwarePropertyProcessObjectList`
/// with `kAudioProcessPropertyIsRunningOutput` set. Verified live on macOS 26.6
/// on 2026-09-16 (Agent Guideline #4) — Spotify reported `1` while playing with
/// Chrome at `0`, and each process object answers `kAudioProcessPropertyPID`
/// and `kAudioProcessPropertyBundleID`.
///
/// Browsers and Electron apps render audio in a *helper* process, which is why
/// the HAL is not the whole answer: a helper reports its own bundle id
/// (`com.google.Chrome.helper`) and its own `NSRunningApplication`, so it looks
/// like an app and is not one. A helper is therefore walked up its parent chain
/// to the first `.regular` app — measured: Chrome's helpers 5648/5649 → 1294,
/// Spotify's 22399 → 1383, Discord's 1519/1532 → 1299 — and the now-playing
/// client is taken from MediaRemote, which names it correctly to begin with.
/// See `refresh` and `owningApp`.
///
/// **Control.** Two routes, and the pair is not arbitrary: between them they
/// cover the case that prompted this. The app that started *last* is the
/// now-playing client, so MediaRemote reaches it — that is how a YouTube tab
/// gets paused. The app that was already playing is a music app, and those
/// answer AppleScript `pause` no matter who holds now-playing. An app that is
/// neither — a background browser tab that has lost now-playing — cannot be
/// reached by either route and is deliberately **not listed**.
///
/// Fails silent per Agent Guideline #3: a HAL read that errors, an app that
/// has quit, or a denied Automation prompt leaves the list short rather than
/// raising anything.
@MainActor
final class AudioSourcesService: ObservableObject {
    /// Audible, pausable apps — the now-playing client first. Empty unless
    /// the panel is open and something is actually playing.
    @Published private(set) var sources: [AudioSource] = []

    /// Apps that answer an AppleScript `pause`, keyed by bundle id. The value
    /// is the AppleScript application name, which is not derivable from the
    /// bundle id. Kept deliberately small: every entry is a promise that the
    /// row's pause button works.
    private static let appleScriptPausable: [String: String] = [
        "com.spotify.client": "Spotify",
        "com.apple.Music": "Music",
        "com.apple.TV": "TV",
        "com.apple.podcasts": "Podcasts",
        "org.videolan.vlc": "VLC",
        "com.colliderli.iina": "IINA",
        "com.apple.QuickTimePlayerX": "QuickTime Player",
    ]

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// Tempo's own pid, excluded from every scan. The global visualizer tap
    /// gives Tempo an output stream of its own, so without this Tempo would
    /// list itself as a thing that is playing (observed: `isRunningOutput = 1`
    /// for `com.gameslayer999.tempo` while only Spotify was audible).
    private static let selfPID = ProcessInfo.processInfo.processIdentifier

    /// Poll interval while the panel is open. The list is only read while the
    /// user is looking at it; a collapsed notch scans nothing.
    private static let pollInterval: TimeInterval = 1

    /// How long after a now-playing handover the outgoing app is re-checked
    /// for audio. The two events are independent — the new player claims
    /// now-playing and the old one keeps its stream open — so this is just
    /// enough settling time for a handover that arrives mid-transition,
    /// while staying well under the point where a user would have reached for
    /// the pause key themselves.
    private static let autoPauseSettle: TimeInterval = 0.4

    private let prefs: Preferences
    /// Pauses the current now-playing client. Injected by `AppDelegate` rather
    /// than reached for directly, so this service owns no adapter path and no
    /// second copy of the transport code.
    private let pauseNowPlaying: () -> Void

    private var pollTimer: Timer?
    private var nowPlayingBundleID: String?
    private var nowPlayingIsPlaying = false
    /// The last app seen actually playing — not the same as the last app seen.
    /// See `nowPlayingChanged`.
    private var lastPlayingBundleID: String?
    private var autoPauseTask: Task<Void, Never>?

    init(prefs: Preferences, pauseNowPlaying: @escaping () -> Void) {
        self.prefs = prefs
        self.pauseNowPlaying = pauseNowPlaying
    }

    // MARK: - Lifecycle

    /// Starts/stops the 1s scan. Driven by the panel's expansion.
    func setScanning(_ scanning: Bool) {
        guard scanning != (pollTimer != nil) else { return }
        if scanning {
            refresh()
            // `.common` rather than the default mode: the panel is interactive
            // while it is open (the progress bar is scrubbable, the volume
            // slider draggable), and a default-mode timer stops firing for the
            // whole of a tracking loop — which would freeze this list exactly
            // while the user is working in the panel it belongs to.
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
            if !sources.isEmpty { sources = [] }
        }
    }

    func stop() {
        setScanning(false)
        autoPauseTask?.cancel()
        autoPauseTask = nil
    }

    // MARK: - Now-playing handover

    /// Told by `MediaRemoteService` who holds now-playing, and whether they
    /// are playing. Decides which source gets the MediaRemote route, and is
    /// the trigger for the auto-pause rule.
    func nowPlayingChanged(bundleID: String?, isPlaying: Bool) {
        if isPlaying != nowPlayingIsPlaying {
            nowPlayingIsPlaying = isPlaying
            if pollTimer != nil { refresh() }
        }
        if bundleID != nowPlayingBundleID {
            nowPlayingBundleID = bundleID
            if pollTimer != nil { refresh() }
        }

        // Only a *playing* client can displace anyone, and the comparison is
        // against the last app seen playing rather than the last app seen at
        // all. Players routinely emit an empty frame between handovers, and
        // comparing against that would make the previous player nil exactly
        // when the rule needs to know who it was.
        guard isPlaying, let bundleID else { return }
        let previous = lastPlayingBundleID
        lastPlayingBundleID = bundleID

        // The rule, stated in full: when a *different* app takes over
        // now-playing and starts playing, the app that just lost it gets
        // paused — but only if it is still making sound (checked against the
        // HAL below, never assumed) and only if it can be named. A browser tab
        // that loses now-playing is unreachable by either route, so it is left
        // alone rather than pretended at.
        guard prefs.autoPausePreviousPlayer,
              let previous,
              previous != bundleID,
              let application = Self.appleScriptPausable[previous]
        else { return }

        autoPauseTask?.cancel()
        autoPauseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.autoPauseSettle * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Re-read rather than trusting the handover: if the user paused
            // Spotify themselves before starting the video, there is nothing
            // to pause and sending one would be the app acting on stale state.
            guard Self.audibleApps().contains(where: { $0.bundleID == previous }) else { return }
            // And the handover must still stand — a bounce back to `previous`
            // within the settle window would otherwise pause what is now the
            // foreground player.
            guard self.lastPlayingBundleID == bundleID else { return }
            Self.runAppleScriptPause(application: application)
        }
    }

    // MARK: - Scanning

    /// Two sources, deliberately, because neither is sufficient alone.
    ///
    /// The now-playing client comes from **MediaRemote**, not from the HAL scan:
    /// a browser renders audio in a helper process whose own bundle id is
    /// `com.google.Chrome.helper`, which matches nothing and can be paused by
    /// nothing, so a Chrome row derived from the process list would either be
    /// missing or be labelled "Google Chrome Helper". MediaRemote already names
    /// the app properly and already knows whether it is playing.
    ///
    /// Everything else comes from the **HAL**, filtered to the AppleScript set —
    /// those are exactly the apps that keep playing *underneath* a new
    /// now-playing client, which is the case this whole service exists for, and
    /// they produce audio from their own process under their own bundle id
    /// (measured: Spotify's audio object is pid 1383 `com.spotify.client`
    /// itself, Music's is pid 1306 `com.apple.Music`).
    private func refresh() {
        let nowPlaying = nowPlayingBundleID
        var next: [AudioSource] = []

        if nowPlayingIsPlaying, let nowPlaying {
            next.append(AudioSource(
                bundleID: nowPlaying,
                name: Self.appName(for: nowPlaying) ?? nowPlaying,
                // AppleScript is preferred even here: it names the app, so the
                // click stays correct if now-playing changes hands between the
                // scan and the click.
                route: Self.appleScriptPausable[nowPlaying].map { .appleScript(application: $0) }
                    ?? .mediaRemote,
                isNowPlaying: true
            ))
        }

        for app in Self.audibleApps() {
            guard let application = Self.appleScriptPausable[app.bundleID],
                  app.bundleID != nowPlaying
            else { continue }
            next.append(AudioSource(
                bundleID: app.bundleID,
                name: app.name,
                route: .appleScript(application: application),
                isNowPlaying: false
            ))
        }

        // Now-playing leads: it is what just started, and what the transport
        // row above already refers to.
        next.sort { lhs, rhs in
            lhs.isNowPlaying == rhs.isNowPlaying ? lhs.name < rhs.name : lhs.isNowPlaying
        }

        if next != sources { sources = next }
    }

    private static func appName(for bundleID: String) -> String? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.localizedName
    }

    // MARK: - Pausing

    /// Pauses one named app. The route was decided when the source was built,
    /// so this never has to guess and never pauses the wrong player.
    func pause(_ source: AudioSource) {
        switch source.route {
        case .mediaRemote:
            pauseNowPlaying()
        case .appleScript(let application):
            Self.runAppleScriptPause(application: application)
        }
        // Reflect it immediately rather than waiting up to a second for the
        // next scan: a row that lingers after the sound stops reads as a click
        // that didn't take (UI Principle #4). The scan corrects this either
        // way if the app ignored us.
        sources.removeAll { $0.id == source.id }
    }

    /// `pause` is used rather than `playpause` throughout: this feature only
    /// ever silences something, and a toggle sent to an app that stopped on
    /// its own between the scan and the click would *start* it playing.
    ///
    /// Runs off the main actor — `NSAppleScript` is synchronous, and a busy
    /// app can take seconds to answer an Apple Event, which would freeze the
    /// notch. The `is running` guard keeps Tempo from launching an app just to
    /// pause it (Agent Guideline #3), matching `MusicService`.
    private nonisolated static func runAppleScriptPause(application: String) {
        Task.detached(priority: .userInitiated) {
            let source = """
            if application "\(application)" is running then
            \ttell application "\(application)" to pause
            end if
            """
            guard let script = NSAppleScript(source: source) else { return }
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                // Usually -1743: Automation for this app not granted yet. There
                // is nothing to recover — the system has already put its prompt
                // on screen — but the number is what makes a silent no-op
                // diagnosable (Agent Guideline #11).
                tempoDebug("pause \(application) failed: \(errorInfo[NSAppleScript.errorNumber] ?? "?")")
            }
        }
    }

    // MARK: - Core Audio

    private struct AudibleApp {
        let bundleID: String
        let name: String
    }

    /// Apps with an active output stream right now, coalesced from process
    /// objects to owning applications (several helpers can map to one app).
    private static func audibleApps() -> [AudibleApp] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &objects) == noErr else {
            return []
        }

        var seen = Set<String>()
        var apps: [AudibleApp] = []
        for object in objects where isRunningOutput(object) {
            guard let pid = processPID(object), pid != selfPID,
                  let app = owningApp(of: pid),
                  let bundleID = app.bundleIdentifier,
                  seen.insert(bundleID).inserted
            else { continue }
            apps.append(AudibleApp(bundleID: bundleID, name: app.localizedName ?? bundleID))
        }
        return apps
    }

    private static func isRunningOutput(_ processObject: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(processObject, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    private static func processPID(_ processObject: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(processObject, &address, 0, nil, &size, &pid) == noErr,
              pid > 0 else { return nil }
        return pid
    }

    /// The real application a (possibly helper) pid belongs to.
    ///
    /// **The test is the activation policy, not whether the pid resolves.** A
    /// helper resolves perfectly well: `NSRunningApplication` for Chrome's
    /// helper pid returns a live object whose bundle id is
    /// `com.google.Chrome.helper` and whose policy is `.accessory`, so
    /// accepting the first pid that resolves stops one process too early and
    /// yields a bundle id nothing can match or pause. Measured on this machine:
    /// `com.google.Chrome.helper` and `com.hnc.Discord.helper[.Renderer]` are
    /// `.accessory` while Chrome, Discord and Spotify are `.regular`, so the
    /// walk continues until it reaches a `.regular` app.
    ///
    /// Public `sysctl` rather than the usual
    /// `responsibility_get_pid_responsible_for_pid`: both were measured to give
    /// the identical parent for every helper here, and one of them is a private
    /// symbol whose absence would be a launch-time crash. Bounded at four hops
    /// — Chrome's is one — so a strange process tree costs a few sysctls and
    /// returns nil. Safari's `com.apple.WebKit.GPU` has no resolvable parent at
    /// all and returns nil here by design; a browser is listed through
    /// MediaRemote instead (see `refresh`).
    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0 ..< 4 {
            if let app = NSRunningApplication(processIdentifier: current),
               app.bundleIdentifier != nil,
               app.activationPolicy == .regular {
                return app
            }
            guard let parent = parentPID(of: current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
