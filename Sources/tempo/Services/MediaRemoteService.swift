import AppKit
import Foundation

/// Now-playing signal & transport control for *any* macOS media app, via the
/// private MediaRemote framework (decision 049).
///
/// macOS 15.4 restricted MediaRemote to processes Apple entitles for it, so
/// Tempo cannot call it directly. Instead the vendored adapter
/// (`Vendor/mediaremote-adapter`, BSD 3-Clause) is loaded inside
/// `/usr/bin/perl` — an Apple-signed, entitled binary — which streams
/// newline-delimited JSON to stdout and accepts one-shot commands.
/// `scripts/build-media-adapter.sh` builds it and verifies the entitlement
/// still holds on the running macOS.
///
/// Verified live on macOS 26.6.1 on 2026-08-22 (Agent Guideline #4): the
/// `get` command returned real now-playing metadata from Google Chrome and
/// from Spotify, and `stream --debounce=100 --micros` pushed diffs within a
/// second of every play/pause in the player. Payload keys observed:
/// `title`, `artist`, `album`, `playing` (Bool), `playbackRate`,
/// `durationMicros`, `elapsedTimeMicros`, `timestampEpochMicros`,
/// `bundleIdentifier`, `processIdentifier`, `contentItemIdentifier`,
/// `artworkData` (base64), `artworkMimeType`, `mediaType`, `trackNumber`.
///
/// The stream is diff-based: the first frame after a change carries only the
/// keys that changed, so this service merges into a running snapshot rather
/// than replacing it. An empty payload (`{}`) means nothing is playing.
///
/// Fails silent per Agent Guideline #3: a missing adapter, a perl that is no
/// longer entitled, or a crashed stream simply leaves the media UI hidden.
@MainActor
final class MediaRemoteService: ObservableObject {
    let state: AppState

    /// Told about every now-playing handover so it can route a row's pause and
    /// run the auto-pause rule (decision 099). Weak because that service holds
    /// a closure back into this one; set by `AppDelegate` after both exist.
    weak var audioSources: AudioSourcesService?

    /// MRCommand IDs, as documented by the adapter's `send` command.
    private enum Command: Int {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
    }

    /// Debounce for the stream, in milliseconds. Players emit bursts of
    /// updates around a track change; 100ms collapses each burst into one
    /// frame without being perceptible.
    private static let streamDebounceMS = 100

    private var streamProcess: Process?
    /// Splits stdout into whole lines. Lives outside the actor because it is
    /// fed from the pipe's read callback; only finished lines cross to the
    /// main actor.
    private var lineBuffer = LineBuffer()
    /// The merged snapshot the diffs apply to.
    private var snapshot: [String: Any] = [:]
    /// Guards against a restart storm if the adapter is broken: back off
    /// rather than respawning perl in a tight loop.
    private var restartDelay: TimeInterval = 1
    private var restartTask: Task<Void, Never>?
    private var isStopping = false

    /// Fires once, `mediaIdleTimeout` after playback stops, and clears
    /// `state.isMediaActive` (decision 038).
    private var idleTimer: Timer?
    /// Identity of the artwork currently decoded, so an unchanged artwork
    /// blob is not re-decoded on every diff that happens to carry it.
    private var lastArtworkFingerprint: String?
    private var artworkTask: Task<Void, Never>?

    /// Serialises the short-lived command processes (`send`, `seek`) off the
    /// main actor. Transport must never block the UI.
    private let commandQueue = DispatchQueue(label: "com.gameslayer999.tempo.mediaremote.command")
    /// Stream stdout is drained on its own queue; only merged results hop to
    /// the main actor.
    private let streamQueue = DispatchQueue(label: "com.gameslayer999.tempo.mediaremote.stream")

    init(state: AppState) {
        self.state = state
    }

    // MARK: - Adapter location

    /// Path to the adapter, resolved once. In a packaged run both files sit
    /// in `Contents/Resources`; in a `swift run` dev build they are in
    /// `Vendor/build` beside the repo, reached from the executable's own
    /// location so it does not depend on the working directory.
    private static let adapterPaths: (script: String, framework: String)? = {
        let fm = FileManager.default

        func candidate(_ dir: String) -> (String, String)? {
            let script = (dir as NSString).appendingPathComponent("mediaremote-adapter.pl")
            let framework = (dir as NSString).appendingPathComponent("MediaRemoteAdapter.framework")
            guard fm.fileExists(atPath: script), fm.fileExists(atPath: framework) else { return nil }
            return (script, framework)
        }

        if let resources = Bundle.main.resourcePath, let found = candidate(resources) {
            return found
        }

        // Dev fallback: walk up from the executable to a directory holding
        // Vendor/build. `.build/<config>/tempo` puts us three levels down.
        var dir = URL(fileURLWithPath: CommandLine.arguments[0])
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0..<6 {
            let vendor = dir.appendingPathComponent("Vendor/build").path
            if let found = candidate(vendor) { return found }
            dir.deleteLastPathComponent()
        }
        return nil
    }()

    // MARK: - Lifecycle

    func start() {
        guard Self.adapterPaths != nil else {
            tempoDebug("mediaremote adapter not found; now-playing disabled")
            return
        }
        isStopping = false
        reapOrphanedStreams()
        startStream()
    }

    func stop() {
        isStopping = true
        restartTask?.cancel()
        restartTask = nil
        idleTimer?.invalidate()
        idleTimer = nil
        artworkTask?.cancel()
        let process = streamProcess
        streamProcess = nil
        // Terminate off the main actor: waitUntilExit on a stuck child must
        // never stall the notch.
        commandQueue.async {
            process?.terminationHandler = nil
            if process?.isRunning == true { process?.terminate() }
        }
    }

    /// Kills adapter streams left behind by a previous Tempo that died
    /// without running `applicationWillTerminate` (a crash, or SIGKILL).
    ///
    /// The child normally dies on its own: once Tempo's read end of the pipe
    /// closes, the adapter's next write takes SIGPIPE. But a stream with
    /// nothing playing never writes, so it can sit orphaned indefinitely —
    /// observed live on 2026-08-22, three of them accumulated across debug
    /// launches. Only processes running *this* adapter path whose parent is
    /// already `launchd` (ppid 1) are killed, so a live stream owned by a
    /// running Tempo is never touched.
    ///
    /// The path comparison is **case-insensitive**, and that is not
    /// belt-and-braces. `Bundle.main.resourcePath` reports the bundle the way
    /// it was reached: through LaunchServices (`open`) it is the canonical
    /// on-disk case, but exec'd straight off the path a shell happened to be
    /// sitting in — the dev route — it keeps that shell's spelling. On a
    /// case-insensitive filesystem both spellings name the same file and both
    /// turn up in `ps`, so an exact compare silently skipped every orphan
    /// whose spelling differed from the running bundle's. Measured: an adapter
    /// left by a directly-exec'd Tempo survived six hours and every relaunch
    /// in between, because each reaping Tempo had been started by `open` and
    /// was comparing the other case (decision 068).
    private func reapOrphanedStreams() {
        guard let script = Self.adapterPaths?.script else { return }
        commandQueue.async {
            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-eo", "pid=,ppid=,command="]
            let pipe = Pipe()
            ps.standardOutput = pipe
            ps.standardError = FileHandle.nullDevice
            guard (try? ps.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            ps.waitUntilExit()

            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                guard fields.count >= 3,
                      let pid = pid_t(fields[0]),
                      fields[1] == "1",
                      line.range(of: script, options: .caseInsensitive) != nil,
                      line.contains("stream")
                else { continue }
                kill(pid, SIGTERM)
            }
        }
    }

    private func startStream() {
        guard let paths = Self.adapterPaths, streamProcess == nil, !isStopping else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            paths.script,
            paths.framework,
            "stream",
            "--debounce=\(Self.streamDebounceMS)",
            "--micros",
        ]

        let pipe = Pipe()
        process.standardOutput = pipe

        // Captured by the read handler directly: reading it back off `self`
        // inside that closure would be a main-actor access from the pipe's
        // own queue.
        let buffer = LineBuffer()
        lineBuffer = buffer
        // The adapter writes diagnostics to stderr; Tempo does not log them
        // (Agent Guideline #5 — payloads can carry track titles).
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            guard let self else { return }
            self.streamQueue.async { [weak self] in
                let lines = buffer.take(chunk)
                guard !lines.isEmpty else { return }
                // FIFO matters: the stream sends diffs, so applying two
                // chunks out of order would merge a stale frame over a fresh
                // one. Separate `Task { @MainActor }` instances have no
                // ordering guarantee between them; the main queue does.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        for line in lines { self?.handle(line: line) }
                    }
                }
            }
        }

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleStreamExit()
            }
        }

        do {
            try process.run()
            streamProcess = process
            snapshot = [:]
            tempoDebug("mediaremote stream started")
        } catch {
            tempoDebug("mediaremote stream failed to launch")
            scheduleRestart()
        }
    }

    private func handleStreamExit() {
        streamProcess = nil
        guard !isStopping else { return }
        tempoDebug("mediaremote stream exited; restarting in \(restartDelay)s")
        setNowPlaying(nil)
        setProgress(nil)
        scheduleRestart()
    }

    private func scheduleRestart() {
        restartTask?.cancel()
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 60)
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.startStream()
        }
    }

    // MARK: - Stream parsing

    private func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // The adapter also emits non-data frames (e.g. errors). Only "data"
        // carries a payload.
        guard (object["type"] as? String) == "data",
              let payload = object["payload"] as? [String: Any]
        else { return }

        // A successful launch is proven by the first frame, not by run() —
        // reset the backoff only once the adapter has actually spoken.
        restartDelay = 1

        if (object["diff"] as? Bool) == true {
            snapshot.merge(payload) { _, new in new }
        } else {
            snapshot = payload
        }

        publish()
    }

    private func publish() {
        guard let title = snapshot["title"] as? String, !title.isEmpty else {
            setNowPlaying(nil)
            setProgress(nil)
            return
        }

        let isPlaying = (snapshot["playing"] as? Bool) ?? false
        let bundleID = (snapshot["bundleIdentifier"] as? String) ?? ""

        setNowPlaying(NowPlaying(
            track: title,
            artist: (snapshot["artist"] as? String) ?? "",
            album: (snapshot["album"] as? String) ?? "",
            sourceBundleID: bundleID,
            isPlaying: isPlaying
        ))

        setProgress(progressFromSnapshot(isPlaying: isPlaying))
        updateArtwork()
    }

    /// Builds the extrapolation anchor decision 041's progress bar consumes.
    /// MediaRemote hands over exactly that shape — an elapsed time plus the
    /// instant it was measured — so no clock correction is needed here.
    private func progressFromSnapshot(isPlaying: Bool) -> PlaybackProgress? {
        guard let durationMicros = snapshot["durationMicros"] as? Double, durationMicros > 0,
              let elapsedMicros = snapshot["elapsedTimeMicros"] as? Double
        else { return nil }

        let anchorDate: Date
        if let stampMicros = snapshot["timestampEpochMicros"] as? Double {
            anchorDate = Date(timeIntervalSince1970: stampMicros / 1_000_000)
        } else {
            anchorDate = Date()
        }

        return PlaybackProgress(
            duration: durationMicros / 1_000_000,
            anchorPosition: elapsedMicros / 1_000_000,
            anchorDate: anchorDate,
            isPlaying: isPlaying
        )
    }

    // MARK: - Transport

    func playPause() { send(.togglePlayPause) }

    /// Plays or pauses whichever app currently holds now-playing — the only
    /// app MediaRemote can address. `AudioSourcesService` calls these for a row
    /// whose route is `.mediaRemote`; everything else there is controlled by
    /// name over AppleScript (decisions 099 and 104). Explicit `play`/`pause`
    /// rather than `playPause()` above, because the row's button is drawn from
    /// a known state and must do what its glyph says.
    func pauseNowPlaying() { send(.pause) }
    func playNowPlaying() { send(.play) }
    func nextTrack() { send(.nextTrack) }
    func previousTrack() { send(.previousTrack) }

    func seek(to seconds: TimeInterval) {
        let duration = state.progress?.duration ?? 0
        let target = min(max(seconds, 0), duration > 0 ? duration : seconds)
        let micros = Int((target * 1_000_000).rounded())

        // Move the anchor immediately. The player will confirm via the stream
        // within a beat, but the bar must not snap back to the old position
        // while that round-trip is in flight (UI Principle #5).
        if var progress = state.progress {
            progress.anchorPosition = target
            progress.anchorDate = Date()
            state.progress = progress
        }

        runAdapter(["seek", String(micros)])
    }

    private func send(_ command: Command) {
        runAdapter(["send", String(command.rawValue)])
    }

    private func runAdapter(_ arguments: [String]) {
        guard let paths = Self.adapterPaths else { return }
        commandQueue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = [paths.script, paths.framework] + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    // MARK: - Artwork

    /// Decodes `artworkData` only when the blob actually changes. The stream
    /// re-sends artwork on a track change, and the base64 payload runs to
    /// hundreds of kilobytes, so the fingerprint check is what keeps a track
    /// change from costing a redundant decode.
    private func updateArtwork() {
        let base64 = snapshot["artworkData"] as? String
        let fingerprint = base64.map { "\($0.count):\($0.suffix(64))" }

        guard fingerprint != lastArtworkFingerprint else { return }
        lastArtworkFingerprint = fingerprint

        artworkTask?.cancel()

        guard let base64 else {
            state.artwork = nil
            return
        }

        artworkTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
                  let image = NSImage(data: data)
            else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.lastArtworkFingerprint == fingerprint else { return }
                self.state.artwork = image
            }
        }
    }

    // MARK: - State updates

    private func setNowPlaying(_ next: NowPlaying?) {
        guard state.nowPlaying != next else { return }
        state.nowPlaying = next
        updateMediaActivity(playing: next?.isPlaying == true)
        // Normalised to nil: `sourceBundleID` is "" when the payload carried
        // no bundle identifier, and an empty string there would read as a real
        // app that no row could ever match.
        let source = next?.sourceBundleID
        audioSources?.nowPlayingChanged(
            bundleID: (source?.isEmpty == false) ? source : nil,
            isPlaying: next?.isPlaying == true
        )
        tempoDebug("nowPlaying playing=\(next?.isPlaying == true) hasTrack=\(next != nil) source=\(next?.sourceBundleID ?? "-") mediaActive=\(state.isMediaActive)")

        if next == nil {
            lastArtworkFingerprint = nil
            artworkTask?.cancel()
            state.artwork = nil
        }
    }

    private func setProgress(_ next: PlaybackProgress?) {
        state.progress = next
    }

    // MARK: - Media idle

    /// How long after playback stops the media UI stays up. Deliberately not
    /// instant: a pause to take a call, a scrub, or an app switch is a gap in
    /// playback, not the end of listening (UI Principle #4).
    ///
    /// This was a fixed 60s until decision 073 made it a setting — the right
    /// value was always a matter of taste, and boringNotch exposes the same
    /// knob. `Preferences.defaultMediaIdleSeconds` is still 60, so an install
    /// that never touches the slider behaves exactly as it did before
    /// (Agent Guideline #7). 0 means never drop it.
    static var mediaIdleTimeout: TimeInterval { Preferences.shared.mediaIdleSeconds }

    /// Shows the media UI while something is playing and for
    /// `mediaIdleTimeout` after it stops (decision 038).
    private func updateMediaActivity(playing: Bool) {
        idleTimer?.invalidate()
        idleTimer = nil

        if playing {
            state.isMediaActive = true
            return
        }

        guard state.isMediaActive else { return }

        // 0 means the media UI never times out — leave it up with no timer
        // rather than scheduling one that would fire immediately.
        let timeout = Self.mediaIdleTimeout
        guard timeout > 0 else { return }

        let t = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.state.isMediaActive = false
                self?.idleTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }
}

/// Accumulates stdout chunks and yields whole lines. A single JSON object
/// spans several pipe reads once artwork base64 is in it, so the trailing
/// partial line has to be carried over.
///
/// Only ever touched from `MediaRemoteService.streamQueue`.
private final class LineBuffer: @unchecked Sendable {
    private var pending = Data()

    func take(_ chunk: Data) -> [String] {
        pending.append(chunk)

        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<newline]
            pending = Data(pending[pending.index(after: newline)...])
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}
