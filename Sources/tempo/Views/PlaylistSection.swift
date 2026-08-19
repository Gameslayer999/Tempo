import SwiftUI

/// Add-current-track-to-playlist row (decision 003). Fully self-hiding: no
/// config → EmptyView; configured but not connected → a small "Connect
/// Spotify" button; connected → a compact playlist picker + add button.
struct PlaylistSection: View {
    @ObservedObject var api: SpotifyWebAPI
    @ObservedObject var state: AppState

    @State private var selectedPlaylistID: String?
    @State private var feedback: Feedback = .none
    @State private var isAdding = false

    private enum Feedback: Equatable {
        case none
        case success
        case failure
    }

    var body: some View {
        Group {
            if !api.isConfigured {
                EmptyView()
            } else if !api.isAuthed {
                connectButton
            } else {
                playlistRow
            }
        }
    }

    private var connectButton: some View {
        Button(action: { api.connect() }) {
            Label("Connect Spotify", systemImage: "link")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.85))
    }

    private var playlistRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(api.playlists) { playlist in
                    Button(playlist.name) {
                        selectedPlaylistID = playlist.id
                    }
                }
            } label: {
                Text(selectedName)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 220)
            .disabled(api.playlists.isEmpty)

            Spacer(minLength: 4)

            addButton
        }
        .frame(height: 20)
        .onAppear {
            if api.playlists.isEmpty {
                Task { await api.loadPlaylists() }
            }
            if selectedPlaylistID == nil {
                selectedPlaylistID = api.playlists.first?.id
            }
        }
        .onChange(of: api.playlists) { _, playlists in
            if selectedPlaylistID == nil {
                selectedPlaylistID = playlists.first?.id
            }
        }
    }

    private var selectedName: String {
        if api.playlists.isEmpty { return "No playlists" }
        return api.playlists.first(where: { $0.id == selectedPlaylistID })?.name ?? "Select playlist"
    }

    private var addButton: some View {
        Button(action: addCurrentTrack) {
            switch feedback {
            case .none:
                Image(systemName: "text.badge.plus")
            case .success:
                Image(systemName: "checkmark")
                    .foregroundColor(.green)
            case .failure:
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.white.opacity(0.85))
        .font(.system(size: 13, weight: .medium))
        .disabled(!canAdd || isAdding)
        .opacity(canAdd ? 1 : 0.35)
    }

    private var canAdd: Bool {
        state.nowPlaying != nil && selectedPlaylistID != nil
    }

    private func addCurrentTrack() {
        guard let trackID = state.nowPlaying?.trackID, let playlistID = selectedPlaylistID else { return }
        isAdding = true
        Task {
            let ok = await api.add(trackURI: trackID, toPlaylist: playlistID)
            isAdding = false
            feedback = ok ? .success : .failure
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            feedback = .none
        }
    }
}
