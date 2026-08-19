import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isExpanded = false
    @Published var nowPlaying: NowPlaying? = nil
    @Published var artwork: NSImage? = nil
    @Published var sessions: [AgentSession] = []
}

struct NowPlaying: Equatable {
    var track: String
    var artist: String
    var album: String
    var trackID: String      // spotify:track:… URI
    var artworkURL: String
    var isPlaying: Bool
}

struct AgentSession: Identifiable, Equatable {
    var id: String           // session id (filename stem)
    var state: String        // "running" | "blocked" | "idle" | "error"
    var label: String
    var updatedAt: Date
}
