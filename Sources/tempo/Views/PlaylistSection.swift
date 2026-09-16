import SwiftUI

/// Add-current-track-to-playlist row (decision 003). Fully self-hiding: no
/// config → EmptyView; configured but not connected → a small "Connect
/// Spotify" button; connected → a compact playlist picker + add button.
struct PlaylistSection: View {
    @ObservedObject var api: SpotifyWebAPI
    @ObservedObject var state: AppState
    @ObservedObject var prefs: Preferences

    @State private var selectedPlaylistID: String?
    @State private var feedback: Feedback = .none
    @State private var isAdding = false
    @State private var isPickerHovered = false

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
                VStack(alignment: .leading, spacing: 4) {
                    playlistRow
                    // The reason, not just a warning glyph: a bare triangle
                    // gave the user nothing to act on (Agent Guideline #11).
                    if feedback == .failure, let error = api.lastAddError {
                        Text(error)
                            .font(NotchType.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var connectButton: some View {
        Button(action: { api.connect() }) {
            Label("Connect Spotify", systemImage: "link")
                .font(NotchType.control.weight(.medium))
        }
        .buttonStyle(NotchButtonStyle())
        .foregroundColor(.primary)
    }

    private var playlistRow: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(offered) { playlist in
                    Button(playlist.name) {
                        selectedPlaylistID = playlist.id
                    }
                }
            } label: {
                // The whole plate is the target, not just the glyphs: a bare
                // `Text` label gave the menu a hit region the width of the
                // rendered characters and no height beyond them, which made it
                // genuinely hard to open and gave no hint it was a control.
                HStack(spacing: 6) {
                    Text(selectedName)
                        .font(NotchType.control)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(NotchType.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .pointingHandCursor()
            .frame(maxWidth: .infinity)
            // Same highlight language as the transport buttons: a resting plate
            // so the control is findable at all, then on hover the buttons' own
            // fill plus an outline marking the hit area.
            //
            // These live on the `Menu`, not inside its `label:`, which is where
            // they were when the hover state produced no visible change.
            // Verified on macOS 26.6 by rendering the panel to a bitmap and
            // sampling the picker's rect: with the decorations here the pixels
            // track the hover state (0.9326 -> 0.9680 with deliberately opaque
            // test colours, switching exactly on the hover events).
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(isPickerHovered ? 0.22 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        Color.primary.opacity(isPickerHovered ? NotchButtonStyle.hoverStroke : 0),
                        lineWidth: 1.5
                    )
            )
            .disabled(offered.isEmpty)
            .accessibilityLabel("Playlist")
            .accessibilityValue(selectedName)
            .help("Choose which playlist the add button adds to")
            .onHover { isPickerHovered = $0 }
            .animation(NotchButtonStyle.hoverAnimation, value: isPickerHovered)

            addButton
        }
        .frame(minHeight: 34)
        .onAppear {
            if api.playlists.isEmpty {
                Task { await api.loadPlaylists() }
            }
            repointSelectionIfNeeded()
        }
        .onChange(of: api.playlists) { _, _ in repointSelectionIfNeeded() }
        .onChange(of: prefs.favoritePlaylistIDs) { _, _ in repointSelectionIfNeeded() }
    }

    /// The playlists this picker offers: the ones chosen in Settings ▸ Music,
    /// or — before any choice is made — every playlist the user can add to, so
    /// the feature works without visiting Settings first. Ordered as picked.
    private var offered: [SpotifyPlaylist] {
        guard !prefs.favoritePlaylistIDs.isEmpty else { return api.playlists }
        // `uniquingKeysWith`, not `uniqueKeysWithValues`: the latter traps on a
        // duplicate id, and Spotify's paginated /me/playlists can repeat one if
        // the underlying list shifts between page fetches — a trap there would
        // crash the notch panel.
        let byID = Dictionary(api.playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return prefs.favoritePlaylistIDs.compactMap { byID[$0] }
    }

    /// Keeps the selection pointing at something that is actually offered — the
    /// set changes when playlists load and when the Settings choice changes, and
    /// a stale id would sit there failing on every press.
    private func repointSelectionIfNeeded() {
        let offered = offered
        if selectedPlaylistID == nil || !offered.contains(where: { $0.id == selectedPlaylistID }) {
            selectedPlaylistID = offered.first?.id
        }
    }

    private var selectedName: String {
        if offered.isEmpty { return "No playlists you can add to" }
        return offered.first(where: { $0.id == selectedPlaylistID })?.name ?? "Select playlist"
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
                    .help(api.lastAddError ?? "")
            }
        }
        .buttonStyle(NotchButtonStyle())
        .foregroundStyle(.primary)
        .font(.body.weight(.medium))
        .disabled(!canAdd || isAdding)
        .opacity(canAdd ? 1 : 0.35)
        .accessibilityLabel(addAccessibilityLabel)
        .help(canAdd
              ? "Add this song to \(selectedName)"
              : "Only songs playing in Spotify can be added to a playlist")
    }

    /// What the add button is currently saying. The three states were a
    /// glyph swap and nothing else — a checkmark and a warning triangle read
    /// identically to VoiceOver, and identically in greyscale.
    private var addAccessibilityLabel: String {
        switch feedback {
        case .none: return "Add to \(selectedName)"
        case .success: return "Added to \(selectedName)"
        case .failure: return api.lastAddError ?? "Could not add to \(selectedName)"
        }
    }

    /// Add-to-playlist is a Spotify Web API call, so it needs the Spotify
    /// track URI — which exists only while Spotify is the thing playing
    /// (decision 049). Playing from any other app leaves the row visible but
    /// disabled rather than silently doing nothing.
    private var canAdd: Bool {
        state.spotifyTrackURI != nil && selectedPlaylistID != nil
    }

    private func addCurrentTrack() {
        guard let trackID = state.spotifyTrackURI, let playlistID = selectedPlaylistID else { return }
        isAdding = true
        Task {
            let ok = await api.add(trackURI: trackID, toPlaylist: playlistID)
            isAdding = false
            feedback = ok ? .success : .failure
            // A failure now carries a sentence to read; 2s isn't enough for it.
            try? await Task.sleep(nanoseconds: ok ? 2_000_000_000 : 6_000_000_000)
            feedback = .none
        }
    }
}
