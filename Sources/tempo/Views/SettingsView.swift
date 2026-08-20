import AppKit
import SwiftUI

/// Tempo's Settings window content (decision 020): a System-Settings-shaped
/// sidebar of panes on the left, a grouped `Form` on the right. Unlike the
/// notch panel this is an ordinary, focusable, system-appearance window — it
/// has a text field (the Spotify Client ID) that needs real keyboard focus.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var api: SpotifyWebAPI

    enum Pane: String, CaseIterable, Identifiable {
        case general, music, modules, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .music: return "Music"
            case .modules: return "Modules"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .music: return "music.note"
            case .modules: return "square.grid.2x2"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selection: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 168, max: 200)
        } detail: {
            detail
                .navigationTitle((selection ?? .general).title)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general: GeneralPane(prefs: prefs)
        case .music: MusicPane(api: api, prefs: prefs)
        case .modules: ModulesPane(prefs: prefs)
        case .about: AboutPane()
        }
    }
}

// MARK: General

private struct GeneralPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Open Tempo at login", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { prefs.setLaunchAtLogin($0) }
                ))
                .disabled(!prefs.isBundled)
            } footer: {
                if !prefs.isBundled {
                    Text("Available only when running the bundled Tempo.app — build it with `scripts/make-app.sh`.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if prefs.launchAtLoginNeedsApproval {
                    Text("Approve Tempo in System Settings ▸ General ▸ Login Items for this to take effect.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let error = prefs.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section {
                Picker("Expanded panel", selection: $prefs.panelStyle) {
                    ForEach(PanelStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                Text(prefs.panelStyle.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                LabeledContent("Expand") { Text("Hover the notch") }
                LabeledContent("Keep open") { Text("Click the panel") }
                LabeledContent("Close") { Text("Click anywhere outside") }
            } header: {
                Text("Interaction")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Music

/// Spotify account pane.
///
/// The developer-app setup cannot be removed: Spotify's AppleScript dictionary
/// has no playlist support whatsoever (verified against Spotify 1.2.95.453 —
/// its `.sdef` declares only transport commands and track properties), so
/// adding a track to a playlist has to go through the Web API, and Spotify
/// requires every Web API app to be registered under its own developer
/// account. What this pane can do is make each remaining step a single click,
/// and say plainly why the step exists.
private struct MusicPane: View {
    @ObservedObject var api: SpotifyWebAPI
    @ObservedObject var prefs: Preferences

    @State private var clientIDField = ""
    @State private var didLoadField = false
    @State private var didCopyRedirect = false
    @State private var playlistQuery = ""
    @State private var isLoadingPlaylists = false

    private static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")!

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(statusText, systemImage: statusSymbol)
                        .foregroundColor(statusColor)
                }
                HStack {
                    if api.isAuthed {
                        Button("Disconnect") { api.disconnect() }
                    } else if api.isConfigured {
                        Button("Connect Spotify") { api.connect() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text("Complete the three steps below to enable it.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            } header: {
                Text("Spotify account")
            } footer: {
                Text("Only used for adding the current song to a playlist. Artwork, the visualizer and the play / pause / skip controls all work without connecting anything.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if api.isAuthed {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search playlists", text: $playlistQuery)
                            .textFieldStyle(.plain)
                        if !playlistQuery.isEmpty {
                            Button {
                                playlistQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        Button(isLoadingPlaylists ? "Refreshing…" : "Refresh") { reloadPlaylists() }
                            .disabled(isLoadingPlaylists)
                    }

                    if api.playlists.isEmpty {
                        Text(isLoadingPlaylists ? "Loading…" : "No playlists you can add to.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(filteredPlaylists) { playlist in
                                    playlistRow(playlist)
                                }
                                if filteredPlaylists.isEmpty {
                                    Text("No match for “\(playlistQuery)”.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.vertical, 6)
                                }
                            }
                        }
                        .frame(height: 190)
                    }
                } header: {
                    Text("Playlists in the notch")
                } footer: {
                    Text(prefs.favoritePlaylistIDs.isEmpty
                         ? "Tick the ones you add songs to most and only those appear in the notch picker. With none ticked, all \(api.playlists.count) are offered."
                         : "\(prefs.favoritePlaylistIDs.count) selected. The notch picker offers these, starting on the first.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                step(1, "Create an app in the Spotify Developer Dashboard. The name and description can be anything — just tick **Web API** when asked which APIs you'll use.") {
                    Button("Open Dashboard") { NSWorkspace.shared.open(Self.dashboardURL) }
                }

                step(2, "In that app's settings, add this exact Redirect URI:") {
                    Button(didCopyRedirect ? "Copied" : "Copy") { copyRedirectURI() }
                }
                Text(SpotifyWebAPI.redirectURI)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)

                step(3, "Copy the app's **Client ID** from its dashboard page and paste it here:") {
                    EmptyView()
                }
                TextField("Client ID", text: $clientIDField, prompt: Text("Client ID"))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save Client ID") { api.saveClientID(clientIDField) }
                        .disabled(trimmedField.isEmpty || trimmedField == api.configuredClientID)
                    if api.isConfigured {
                        Button("Remove") {
                            api.clearConfiguration()
                            clientIDField = ""
                        }
                    }
                    Spacer()
                }
            } header: {
                Text("One-time setup")
            } footer: {
                Text("Spotify requires every app using its Web API to be registered under its own developer account, so this can't be skipped or shipped inside Tempo. Spotify's AppleScript interface — which drives everything else here — has no playlist commands at all, so there is no way around the Web API for this one feature.\n\nThe Client ID is not a secret (Spotify's PKCE flow publishes it). It is saved to ~/Library/Application Support/Tempo/config.json, owner-only, along with the tokens; nothing is sent anywhere but Spotify.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Load once, so re-selecting the pane doesn't wipe an edit in
            // progress.
            if !didLoadField {
                didLoadField = true
                clientIDField = api.configuredClientID
            }
            if api.isAuthed, api.playlists.isEmpty { reloadPlaylists() }
        }
    }

    private var filteredPlaylists: [SpotifyPlaylist] {
        let query = playlistQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return api.playlists }
        // Substring, not prefix: "worship" should find "Sunday Worship Set".
        return api.playlists.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func playlistRow(_ playlist: SpotifyPlaylist) -> some View {
        let isOn = prefs.isFavoritePlaylist(playlist.id)
        return Button {
            prefs.toggleFavoritePlaylist(playlist.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isOn ? .accentColor : .secondary)
                Text(playlist.name)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func reloadPlaylists() {
        isLoadingPlaylists = true
        Task {
            await api.loadPlaylists()
            isLoadingPlaylists = false
        }
    }

    /// One numbered setup step: the number, the instruction, and an optional
    /// button that performs it.
    private func step(_ number: Int, _ instruction: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(instruction)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            action()
        }
    }

    private func copyRedirectURI() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(SpotifyWebAPI.redirectURI, forType: .string)
        didCopyRedirect = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            didCopyRedirect = false
        }
    }

    private var trimmedField: String {
        clientIDField.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var statusText: String {
        if api.isAuthed { return "Connected" }
        if api.isConfigured { return "Client ID saved — not connected" }
        return "Not set up"
    }

    private var statusSymbol: String {
        if api.isAuthed { return "checkmark.circle.fill" }
        if api.isConfigured { return "link.circle" }
        return "circle.dashed"
    }

    private var statusColor: Color {
        if api.isAuthed { return .green }
        return .secondary
    }
}

// MARK: Modules

private struct ModulesPane: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Audio visualizer", isOn: $prefs.showVisualizer)
                Toggle("CPU and memory graphs", isOn: $prefs.showUsageGraph)
                Toggle("Agent session lights", isOn: $prefs.showAgentLights)
            } header: {
                Text("Show in the notch")
            } footer: {
                Text("The visualizer sits in the collapsed pill; the graphs and agent lights appear in the expanded panel. Each also hides itself automatically when it has nothing to show.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: About

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version") { Text(version) }
                LabeledContent("Agent status") { Text("~/.claude/status (read-only)") }
            } header: {
                Text("Tempo")
            } footer: {
                Text("A notch surface for what's playing, what your Mac is doing, and which Claude Code sessions need you.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let short else { return "development build" }
        return build.map { "\(short) (\($0))" } ?? short
    }
}
