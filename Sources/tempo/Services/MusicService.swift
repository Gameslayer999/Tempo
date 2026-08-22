import AppKit
import Foundation

/// Now-playing signal & transport control for Spotify, via AppleScript to
/// the desktop app (decision 002). Tempo never launches Spotify and never
/// shows a dialog or logs noise on failure — see Agent Guideline #3.
///
/// Event-driven (not polled): Spotify's desktop app posts a distributed
/// notification, `com.spotify.client.PlaybackStateChanged`, on every
/// play/pause/track change. Verified live on this machine on 2026-08-20
/// (Agent Guideline #4) by subscribing on `DistributedNotificationCenter`
/// and toggling Spotify's play state — two notifications arrived within
/// the same second as the toggles, each with a `userInfo` dict containing:
/// `Player State` (String, "Playing"/"Paused" — note the capitalization,
/// unlike the lowercase `player state` AppleScript returns), `Name`,
/// `Artist`, `Album`, `Track ID` (String, `spotify:track:…`), `Duration`,
/// `Playback Position`, `Has Artwork`, `Album Artist`, `Popularity`,
/// `Play Count`, `Track Number`, `Disc Number`. No artwork URL is present,
/// so artwork still requires one AppleScript round-trip — but only when
/// the track identity changes, not on every event.
@MainActor
final class MusicService: ObservableObject {
    let state: AppState

    private nonisolated static let bundleID = "com.spotify.client"
    private static let playbackChangedNotification = Notification.Name(
        "com.spotify.client.PlaybackStateChanged"
    )

    /// Field order returned by `fetchScript`, one line per field.
    private enum Field: Int, CaseIterable {
        case playerState, name, artist, album, id, artworkURL
    }

    private var playbackObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    /// Slow reconciliation net (30s), only while Spotify is running. The
    /// distributed notification is reliable but not guaranteed — e.g. a
    /// notification posted before this service's observer registered, or
    /// an OS delivery hiccup — so this safety poll re-syncs state within
    /// 30s of anything missed. It reuses the same AppleScript fetch path
    /// as everything else; it is not a substitute for the event path.
    private var safetyTimer: Timer?
    /// Fires once, `mediaIdleTimeout` after playback stops, and clears
    /// `state.isMediaActive` (decision 038). Re-armed on every real playback
    /// change, cancelled the moment something plays again.
    private var idleTimer: Timer?
    private var fetchScript: NSAppleScript?
    /// 1Hz position reconciliation, armed only while the expanded panel is on
    /// screen *and* something is playing (decision 041). Collapsed there is no
    /// progress bar drawn, so there is nothing a fresh position could correct;
    /// paused, the anchor is already correct by definition.
    private var positionTimer: Timer?
    /// True while a position round-trip is outstanding, so a slow reply cannot
    /// stack up a queue of them behind it.
    private var positionFetchInFlight = false
    /// Set by the view when the panel opens and closes; one half of the
    /// polling condition.
    private var panelOpen = false
    /// Reconciliation results are discarded until this instant. See
    /// `seekSettleWindow` — Spotify keeps reporting the *old* position for a
    /// short while after a seek command returns, and a reconcile landing in
    /// that window would drag the bar back to where the user just left.
    private var seekSettleUntil = Date.distantPast
    private var lastArtworkURL: String?
    private var lastTrackID: String?
    private var artworkTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
    }

    /// Subscribes to Spotify's playback-change broadcast and Spotify's
    /// process lifecycle, then — if Spotify is already running — does one
    /// immediate AppleScript fetch (it may already be playing before Tempo
    /// starts) and arms the safety net. No periodic AppleScript at steady
    /// state.
    func start() {
        playbackObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.playbackChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                self?.handlePlaybackChanged(note)
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        launchObserver = workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard Self.isSpotify(note) else { return }
            Task { @MainActor in
                self?.fetchAndUpdate()
                self?.scheduleSafetyPoll()
            }
        }
        terminateObserver = workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard Self.isSpotify(note) else { return }
            Task { @MainActor in
                self?.safetyTimer?.invalidate()
                self?.safetyTimer = nil
                self?.lastTrackID = nil
                self?.setProgress(nil)
                self?.setNowPlaying(nil)
            }
        }

        guard Self.isSpotifyRunning else { return }
        fetchAndUpdate()
        scheduleSafetyPoll()
    }

    func playPause() {
        runTransport("playpause")
    }

    func nextTrack() {
        runTransport("next track")
    }

    func previousTrack() {
        runTransport("previous track")
    }

    /// Jumps to `seconds` in the current track (decision 041).
    ///
    /// Optimistic: the anchor moves to the target *before* the AppleScript
    /// runs, so the bar stays where the user let go instead of snapping back
    /// to the old position for the length of the round-trip and then jumping
    /// forward. The reconcile afterwards replaces the guess with Spotify's
    /// real position, so an out-of-range or refused seek self-corrects rather
    /// than leaving the bar lying (UI Principle #4).
    func seek(to seconds: TimeInterval) {
        guard Self.isSpotifyRunning, let current = state.progress, current.duration > 0 else { return }
        let target = min(max(seconds, 0), current.duration)
        setProgress(PlaybackProgress(
            duration: current.duration,
            anchorPosition: target,
            anchorDate: Date(),
            isPlaying: current.isPlaying
        ))

        // Formatted with an explicit C locale: AppleScript number literals are
        // always point-decimal, and "%f" against a comma-decimal locale would
        // produce `set player position to 58,4` — two arguments, not one.
        let literal = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), target)
        seekSettleUntil = Date().addingTimeInterval(Self.seekSettleWindow)
        Task.detached(priority: .userInitiated) { [weak self] in
            var errorInfo: NSDictionary?
            let script = NSAppleScript(source: "tell application \"Spotify\" to set player position to \(literal)")
            _ = script?.executeAndReturnError(&errorInfo)
            guard let self else { return }
            // Wait out the settle window before reconciling, or this read
            // gets the pre-seek position and undoes the seek on screen.
            try? await Task.sleep(for: .seconds(Self.seekSettleWindow))
            await MainActor.run { self.refreshPosition() }
        }
    }

    /// How long after a seek Spotify's reported position is not to be
    /// trusted.
    ///
    /// `set player position` returns *before* the player has actually moved.
    /// Measured on this machine (Agent Guideline #4) by tracing the real code
    /// path: a reconcile that started 30ms after the command returned still
    /// read the pre-seek position, and applied it — the bar visibly jumped
    /// back. The observed staleness reached ~56ms past the command's return
    /// and varied run to run, so this is set an order of magnitude above it.
    ///
    /// A long window costs nothing in accuracy: the optimistic anchor set by
    /// `seek` is exactly where the user asked to go, so the only thing
    /// delayed is discovering that Spotify *refused* the seek.
    private static let seekSettleWindow: TimeInterval = 0.5

    /// Called by the view as the expanded panel opens and closes. Opening
    /// reconciles once immediately — the anchor may have been extrapolating
    /// unwatched for a while — and then arms the 1Hz poll; closing disarms it.
    func setPanelOpen(_ open: Bool) {
        guard panelOpen != open else { return }
        panelOpen = open
        if open { refreshPosition() }
        updatePositionPolling()
    }

    // MARK: - Event handling

    private func handlePlaybackChanged(_ note: Notification) {
        guard let info = note.userInfo, let trackID = info["Track ID"] as? String else { return }

        guard trackID == lastTrackID else {
            // Track identity changed — the artwork URL isn't in this
            // notification's userInfo (verified live, see header), so
            // fetch it — and reconfirm everything else — via AppleScript
            // once for this event.
            fetchAndUpdate()
            return
        }

        // Same track: every field Tempo needs is already in userInfo
        // (play state, name, artist, album, id), so update with zero
        // AppleScript round-trips.
        guard let parsed = Self.parse(userInfo: info, artworkURL: state.nowPlaying?.artworkURL ?? "") else { return }
        // `Playback Position` (seconds) and `Duration` (milliseconds) ride
        // along in the same userInfo — verified live 2026-08-22, and they
        // matched `player position` to the millisecond — so a play/pause
        // re-anchors the bar with no AppleScript at all.
        setProgress(Self.progress(
            position: (info["Playback Position"] as? NSNumber)?.doubleValue,
            durationMS: (info["Duration"] as? NSNumber)?.doubleValue,
            isPlaying: parsed.isPlaying
        ))
        setNowPlaying(parsed)
    }

    private func scheduleSafetyPoll() {
        safetyTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchAndUpdate()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        safetyTimer = t
    }

    private nonisolated static func isSpotify(_ note: Notification) -> Bool {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return false
        }
        return app.bundleIdentifier == bundleID
    }

    // MARK: - AppleScript fetch (startup, track changes, safety net, transport)

    private func fetchAndUpdate() {
        guard Self.isSpotifyRunning else {
            lastTrackID = nil
            setProgress(nil)
            setNowPlaying(nil)
            return
        }

        guard let result = runFetch(), let parsed = Self.parse(result.text) else {
            // AppleScript failed (dictionary mismatch, no track loaded,
            // etc.) — fail silent per Agent Guideline #3.
            lastTrackID = nil
            setProgress(nil)
            setNowPlaying(nil)
            return
        }

        lastTrackID = parsed.trackID
        setProgress(Self.progress(
            position: result.position,
            durationMS: result.durationMS,
            isPlaying: parsed.isPlaying
        ))
        setNowPlaying(parsed)
    }

    /// Compiles the combined fetch script once and reuses it — one
    /// AppleScript round-trip per call, never on a timer.
    ///
    /// Verified live against the installed Spotify desktop app on
    /// 2026-08-19 (Agent Guideline #4): `player state`, `name`/`artist`/
    /// `album`/`id`/`artwork url` of `current track` all returned the
    /// expected values. Note: a variable named `st` produced a spurious
    /// "Expected expression but found 'st'" parse error inside Spotify's
    /// `tell` block (collides with a term in Spotify's scripting
    /// dictionary) — field/variable names below avoid short names for that
    /// reason.
    private func runFetch() -> (text: String, position: Double, durationMS: Double)? {
        let script = fetchScript ?? {
            let compiled = NSAppleScript(source: Self.fetchSource)
            _ = compiled?.compileAndReturnError(nil)
            fetchScript = compiled
            return compiled
        }()
        guard let script else { return nil }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, descriptor.numberOfItems == 3,
              let text = descriptor.atIndex(1)?.stringValue,
              let position = descriptor.atIndex(2)?.doubleValue,
              let durationMS = descriptor.atIndex(3)?.doubleValue else { return nil }
        return (text, position, durationMS)
    }

    private func runTransport(_ command: String) {
        guard Self.isSpotifyRunning else { return }
        let source = "tell application \"Spotify\" to \(command)"
        // Fire-and-forget: the caller doesn't await this. Re-fetch once the
        // AppleScript actually finishes (not right after dispatch) so this
        // reflects the new state instead of racing it. The playback
        // notification will usually arrive too; setNowPlaying's equality
        // guard makes that harmless.
        Task.detached(priority: .userInitiated) { [weak self] in
            let script = NSAppleScript(source: source)
            var errorInfo: NSDictionary?
            _ = script?.executeAndReturnError(&errorInfo)
            guard let self else { return }
            await MainActor.run {
                self.fetchAndUpdate()
            }
        }
    }

    private static var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static let fetchSource = """
    tell application "Spotify"
    \tif it is running then
    \t\tset playerState to player state as string
    \t\tset curTrack to current track
    \t\tset trackName to name of curTrack
    \t\tset trackArtist to artist of curTrack
    \t\tset trackAlbum to album of curTrack
    \t\tset trackID to id of curTrack
    \t\tset trackArtworkURL to artwork url of curTrack
    \t\tset textFields to playerState & "\\n" & trackName & "\\n" & trackArtist & "\\n" & trackAlbum & "\\n" & trackID & "\\n" & trackArtworkURL
    \t\treturn {textFields, player position, duration of curTrack}
    \telse
    \t\treturn {"NOTRUNNING", 0, 0}
    \tend if
    end tell
    """

    /// Parses the pipe-of-newlines result from `fetchSource`. Returns nil
    /// on anything unexpected (no track loaded, stopped state, malformed
    /// output) so the caller treats it as "no data" rather than guessing.
    private static func parse(_ raw: String) -> NowPlaying? {
        guard raw != "NOTRUNNING" else { return nil }
        let lines = raw.components(separatedBy: "\n")
        guard lines.count == Field.allCases.count else { return nil }

        let playerState = lines[Field.playerState.rawValue]
        guard playerState == "playing" || playerState == "paused" else { return nil }

        return NowPlaying(
            track: lines[Field.name.rawValue],
            artist: lines[Field.artist.rawValue],
            album: lines[Field.album.rawValue],
            trackID: lines[Field.id.rawValue],
            artworkURL: lines[Field.artworkURL.rawValue],
            isPlaying: playerState == "playing"
        )
    }

    /// Parses a `com.spotify.client.PlaybackStateChanged` notification's
    /// `userInfo` (keys verified live — see header). `artworkURL` is
    /// supplied by the caller since it is never present in this
    /// notification. Returns nil on anything unexpected (missing keys,
    /// unrecognized player state) so the caller treats it as "no update"
    /// rather than guessing.
    private static func parse(userInfo: [AnyHashable: Any], artworkURL: String) -> NowPlaying? {
        guard let playerState = userInfo["Player State"] as? String,
              playerState == "Playing" || playerState == "Paused" else { return nil }
        guard let name = userInfo["Name"] as? String,
              let artist = userInfo["Artist"] as? String,
              let album = userInfo["Album"] as? String,
              let trackID = userInfo["Track ID"] as? String else { return nil }

        return NowPlaying(
            track: name,
            artist: artist,
            album: album,
            trackID: trackID,
            artworkURL: artworkURL,
            isPlaying: playerState == "Playing"
        )
    }

    // MARK: - Position reconciliation

    /// A seek made inside Spotify's own window posts **no** notification —
    /// verified 2026-08-22 by driving `set player position` with a listener
    /// attached and receiving nothing (Agent Guideline #4). Extrapolation
    /// alone would therefore keep drawing the old position after a scrub, so
    /// the bar is re-anchored from Spotify once a second while it is visible.
    ///
    /// Cost, measured on this machine: 33ms median / 54ms p90 per round-trip
    /// off the main actor (16.6ms on the main thread), nearly all of it
    /// blocked waiting on Spotify's reply rather than burning CPU. Far too
    /// much to sit on the main actor once a second, hence `Task.detached`.
    private func updatePositionPolling() {
        let shouldRun = panelOpen && state.progress?.isPlaying == true
        guard shouldRun else {
            positionTimer?.invalidate()
            positionTimer = nil
            return
        }
        guard positionTimer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPosition()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        positionTimer = t
    }

    private func refreshPosition() {
        guard Self.isSpotifyRunning, !positionFetchInFlight else { return }
        positionFetchInFlight = true
        Task.detached(priority: .utility) {
            let fetched = Self.runPositionFetch()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.positionFetchInFlight = false
                guard let fetched else { return }
                // A seek landed while this was in flight: Spotify is still
                // reporting the position the user just left, so this result
                // is stale by construction. Drop it — the seek's own
                // reconcile, scheduled after the settle window, is the one
                // that gets to speak.
                guard Date() >= self.seekSettleUntil else { return }
                // Play state is not re-read here: this runs between events,
                // and the notification path owns that transition. Reusing the
                // known state keeps a reconcile from ever flipping the
                // play/pause glyph on its own.
                self.setProgress(Self.progress(
                    position: fetched.position,
                    durationMS: fetched.durationMS,
                    isPlaying: self.state.progress?.isPlaying ?? false
                ))
            }
        }
    }

    /// One position-only round-trip. A fresh `NSAppleScript` per call rather
    /// than the reused `fetchScript`: this runs on the concurrent executor,
    /// which is not a fixed thread, and `NSAppleScript` is not thread-safe.
    /// Measured to cost the same as a reused instance (33ms median either
    /// way), so nothing is lost by not caching it.
    ///
    /// Returns the numbers as typed AppleEvent numbers rather than
    /// `as string`, so parsing cannot depend on the system's decimal
    /// separator.
    private nonisolated static func runPositionFetch() -> (position: Double, durationMS: Double)? {
        guard let script = NSAppleScript(source: positionSource) else { return nil }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, descriptor.numberOfItems == 2,
              let position = descriptor.atIndex(1)?.doubleValue,
              let durationMS = descriptor.atIndex(2)?.doubleValue else { return nil }
        return (position, durationMS)
    }

    private nonisolated static let positionSource = """
    tell application "Spotify"
    \tif it is running then
    \t\treturn {player position, duration of current track}
    \telse
    \t\treturn {}
    \tend if
    end tell
    """

    /// Builds an anchor from a position/duration pair, converting Spotify's
    /// millisecond duration to seconds. Returns nil for anything unusable —
    /// a missing field, or the zero duration Spotify reports with no track
    /// loaded — so the bar hides rather than drawing a zero-length track.
    private static func progress(position: Double?, durationMS: Double?, isPlaying: Bool) -> PlaybackProgress? {
        guard let position, let durationMS, durationMS > 0 else { return nil }
        return PlaybackProgress(
            duration: durationMS / 1000,
            anchorPosition: position,
            anchorDate: Date(),
            isPlaying: isPlaying
        )
    }

    private func setProgress(_ next: PlaybackProgress?) {
        state.progress = next
        updatePositionPolling()
    }

    // MARK: - Media idle

    /// How long after playback stops the media UI stays up. Deliberately not
    /// instant: a pause to take a call, skip-by-scrub, or an app switch is a
    /// gap in playback, not the end of listening, and the cover blinking away
    /// on every short pause would be worse than leaving it (UI Principle #4).
    static let mediaIdleTimeout: TimeInterval = 60

    /// Shows the media UI while something is actually playing and for
    /// `mediaIdleTimeout` after it stops; hides it then (decision 038).
    ///
    /// Only ever called from `setNowPlaying` *after* its equality guard, so
    /// the 30s safety poll re-reporting the same paused track cannot keep
    /// restarting the countdown.
    private func updateMediaActivity(playing: Bool) {
        idleTimer?.invalidate()
        idleTimer = nil

        if playing {
            state.isMediaActive = true
            return
        }

        // Already hidden (Spotify was never playing this session, or the
        // timeout has passed): nothing to count down to.
        guard state.isMediaActive else { return }

        let t = Timer.scheduledTimer(withTimeInterval: Self.mediaIdleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.state.isMediaActive = false
                self?.idleTimer = nil
            }
        }
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    // MARK: - State updates

    private func setNowPlaying(_ next: NowPlaying?) {
        guard state.nowPlaying != next else { return }
        state.nowPlaying = next
        updateMediaActivity(playing: next?.isPlaying == true)
        tempoDebug("nowPlaying playing=\(next?.isPlaying == true) hasTrack=\(next != nil) mediaActive=\(state.isMediaActive)")

        let nextArtworkURL = next?.artworkURL
        guard nextArtworkURL != lastArtworkURL else { return }
        lastArtworkURL = nextArtworkURL

        artworkTask?.cancel()
        guard let urlString = nextArtworkURL, let url = URL(string: urlString) else {
            state.artwork = nil
            return
        }

        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.lastArtworkURL == urlString else { return }
                self?.state.artwork = image
            }
        }
    }
}
