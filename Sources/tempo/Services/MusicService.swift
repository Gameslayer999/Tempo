import AppKit
import Foundation

/// Now-playing signal & transport control for Spotify, via AppleScript to
/// the desktop app (decision 002). Tempo never launches Spotify and never
/// shows a dialog or logs noise on failure — see Agent Guideline #3.
@MainActor
final class MusicService: ObservableObject {
    let state: AppState

    private static let bundleID = "com.spotify.client"

    /// Field order returned by `fetchScript`, one line per field.
    private enum Field: Int, CaseIterable {
        case playerState, name, artist, album, id, artworkURL
    }

    private var timer: Timer?
    private var fetchScript: NSAppleScript?
    private var lastArtworkURL: String?
    private var artworkTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
    }

    /// Begins a ~1s repeating poll of Spotify's player state. A poll (rather
    /// than events) is the simplest thing that keeps the collapsed strip
    /// glanceable without lying (UI Principle #4) and matches the polling
    /// pattern already used by AgentStatusService.
    func start() {
        timer?.invalidate()
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
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

    // MARK: - Polling

    private func poll() {
        guard Self.isSpotifyRunning else {
            setNowPlaying(nil)
            return
        }

        guard let result = runFetch(), let parsed = Self.parse(result) else {
            // AppleScript failed (dictionary mismatch, no track loaded,
            // etc.) — fail silent per Agent Guideline #3.
            setNowPlaying(nil)
            return
        }

        setNowPlaying(parsed)
    }

    /// Compiles the combined fetch script once and reuses it — one
    /// AppleScript round-trip per poll, per the interface contract.
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
        // Fire-and-forget: the caller doesn't await this. Re-poll once the
        // AppleScript actually finishes (not right after dispatch) so the
        // immediate poll reflects the new state instead of racing it.
        Task.detached(priority: .userInitiated) { [weak self] in
            let script = NSAppleScript(source: source)
            var errorInfo: NSDictionary?
            _ = script?.executeAndReturnError(&errorInfo)
            await MainActor.run {
                self?.poll()
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
