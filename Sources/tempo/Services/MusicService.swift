import AppKit
import Foundation

/// Supplies the `spotify:track:…` URI of the current track, and nothing else.
///
/// Now-playing metadata and transport moved to `MediaRemoteService` in
/// decision 049, which covers every player rather than just Spotify. But
/// MediaRemote identifies a track only by `contentItemIdentifier` — a
/// per-playback UUID that changes on every seek (observed live: three seeks
/// produced three different identifiers for the same song). The Spotify Web
/// API's "add to playlist" needs the stable `spotify:track:…` URI, so that one
/// value still has to come from Spotify itself.
///
/// Event-driven, no polling: Spotify's desktop app posts
/// `com.spotify.client.PlaybackStateChanged` on every play/pause/track change,
/// and its `userInfo` carries `Track ID` directly (verified live 2026-08-20).
/// AppleScript is used exactly once — at startup, when Spotify is already
/// running and no notification has been posted yet.
///
/// Fails silent per Agent Guideline #3: Spotify absent or not running simply
/// leaves `state.spotifyTrackURI` nil, which hides the add-to-playlist row.
@MainActor
final class MusicService: ObservableObject {
    let state: AppState

    private nonisolated static let bundleID = "com.spotify.client"
    private static let playbackChangedNotification = Notification.Name(
        "com.spotify.client.PlaybackStateChanged"
    )

    private var playbackObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
    }

    func start() {
        playbackObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.playbackChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let trackID = note.userInfo?["Track ID"] as? String
            Task { @MainActor in
                self?.state.spotifyTrackURI = trackID
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        launchObserver = workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard Self.isSpotify(note) else { return }
            Task { @MainActor in self?.fetchTrackURI() }
        }
        terminateObserver = workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard Self.isSpotify(note) else { return }
            Task { @MainActor in self?.state.spotifyTrackURI = nil }
        }

        guard Self.isSpotifyRunning else { return }
        fetchTrackURI()
    }

    func stop() {
        if let playbackObserver {
            DistributedNotificationCenter.default().removeObserver(playbackObserver)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        if let launchObserver { workspace.removeObserver(launchObserver) }
        if let terminateObserver { workspace.removeObserver(terminateObserver) }
        playbackObserver = nil
        launchObserver = nil
        terminateObserver = nil
    }

    // MARK: - AppleScript

    /// One round-trip, only at startup / Spotify launch. Runs off the main
    /// actor: `NSAppleScript` is synchronous and a launching Spotify can take
    /// seconds to answer, which would otherwise freeze the notch.
    private func fetchTrackURI() {
        Task.detached(priority: .utility) {
            let uri = Self.runTrackURIFetch()
            await MainActor.run { [weak self] in
                guard let self, let uri, !uri.isEmpty else { return }
                self.state.spotifyTrackURI = uri
            }
        }
    }

    private nonisolated static func runTrackURIFetch() -> String? {
        // `if application "Spotify" is running` guards against AppleScript
        // launching Spotify just to answer the question (Agent Guideline #3:
        // Tempo never launches it).
        let source = """
        if application "Spotify" is running then
        \ttell application "Spotify" to return id of current track
        else
        \treturn ""
        end if
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return nil }
        return descriptor.stringValue
    }

    // MARK: - Spotify process

    private nonisolated static var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private nonisolated static func isSpotify(_ note: Notification) -> Bool {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier == bundleID
    }
}
