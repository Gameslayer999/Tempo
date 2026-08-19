import Foundation

@MainActor
final class AgentStatusService: ObservableObject {
    let state: AppState
    init(state: AppState) { self.state = state }
    func start() {}          // begin watching ~/.claude/status/sessions
}
