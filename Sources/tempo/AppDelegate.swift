import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel?
    private var state: AppState?
    private var music: MusicService?
    private var agentStatus: AgentStatusService?
    private var spotifyAPI: SpotifyWebAPI?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = AppState()
        let music = MusicService(state: state)
        let agentStatus = AgentStatusService(state: state)
        let spotifyAPI = SpotifyWebAPI()

        self.state = state
        self.music = music
        self.agentStatus = agentStatus
        self.spotifyAPI = spotifyAPI

        music.start()
        agentStatus.start()
        spotifyAPI.start()
        // Start sampling at launch (not first panel-open) so the usage graph
        // has real history the first time the user expands. ~2 Mach calls/sec.
        SystemStatsService.shared.start()

        let content = ContentView(state: state, music: music, api: spotifyAPI)
        let panel = NotchPanel(state: state, content: content)
        panel.orderFrontRegardless()
        self.panel = panel
    }
}
