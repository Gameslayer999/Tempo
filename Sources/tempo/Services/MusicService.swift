import Foundation

@MainActor
final class MusicService: ObservableObject {
    let state: AppState
    init(state: AppState) { self.state = state }
    func start() {}          // begin polling Spotify
    func playPause() {}
    func nextTrack() {}
    func previousTrack() {}
}
