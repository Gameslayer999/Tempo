import Foundation

@MainActor
final class SpotifyWebAPI: ObservableObject {
    @Published var isConfigured = false   // config.json with client id exists
    @Published var isAuthed = false       // have a valid token
    @Published var playlists: [SpotifyPlaylist] = []
    func start() {}                        // load config + stored tokens
    func connect() {}                      // begin PKCE flow in browser
    func loadPlaylists() async {}
    @discardableResult
    func add(trackURI: String, toPlaylist playlistID: String) async -> Bool { false }
}

struct SpotifyPlaylist: Identifiable, Equatable {
    var id: String
    var name: String
}
