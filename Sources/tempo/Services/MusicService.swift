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
    private var fetchScript: NSAppleScript?
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
            setNowPlaying(nil)
            return
        }

        guard let result = runFetch(), let parsed = Self.parse(result) else {
            // AppleScript failed (dictionary mismatch, no track loaded,
            // etc.) — fail silent per Agent Guideline #3.
            lastTrackID = nil
            setNowPlaying(nil)
            return
        }

        lastTrackID = parsed.trackID
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
    private func runFetch() -> String? {
        let script = fetchScript ?? {
            let compiled = NSAppleScript(source: Self.fetchSource)
            _ = compiled?.compileAndReturnError(nil)
            fetchScript = compiled
            return compiled
        }()
        guard let script else { return nil }

        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, let value = descriptor.stringValue else { return nil }
        return value
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
    \t\treturn playerState & "\\n" & trackName & "\\n" & trackArtist & "\\n" & trackAlbum & "\\n" & trackID & "\\n" & trackArtworkURL
    \telse
    \t\treturn "NOTRUNNING"
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

    // MARK: - State updates

    private func setNowPlaying(_ next: NowPlaying?) {
        guard state.nowPlaying != next else { return }
        state.nowPlaying = next

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
