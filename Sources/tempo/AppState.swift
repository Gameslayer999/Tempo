import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    /// Pinned by a click on the expanded panel; stays expanded on mouse-out
    /// while true.
    @Published var isExpanded = false
    /// Mouse currently within the active (strip or full-panel) region.
    @Published var isHovered = false
    @Published var nowPlaying: NowPlaying? = nil
    @Published var artwork: NSImage? = nil
    @Published var sessions: [AgentSession] = []

    /// What the UI actually shows: expanded if either pinned by a click or
    /// currently hovered.
    var displayedExpanded: Bool { isExpanded || isHovered }
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
