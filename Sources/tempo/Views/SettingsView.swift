import AppKit
import Combine
import SwiftUI

/// Tempo's Settings window content (decision 020): a System-Settings-shaped
/// sidebar of panes on the left, a grouped `Form` on the right. Unlike the
/// notch panel this is an ordinary, focusable, system-appearance window — it
/// has a text field (the Spotify Client ID) that needs real keyboard focus.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var api: SpotifyWebAPI
    /// Read for one thing only: the current album's dominant colour, so the
    /// "Album tint" preview shows the tint the panel would carry right now.
    /// Deliberately not an `@ObservedObject` — the Settings window has no
    /// reason to redraw on every playback or session publish.
    let state: AppState
    @ObservedObject var weather: WeatherService
    @ObservedObject var location: LocationService
    @ObservedObject var lockCards: LockScreenNotifier
    let onboarding: OnboardingController

    enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, displays, music, agents, weather, modules, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .appearance: return "Appearance"
            case .displays: return "Displays"
            case .music: return "Music"
            case .agents: return "Agents"
            case .weather: return "Weather"
            case .modules: return "Modules"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape.fill"
            case .appearance: return "paintbrush.fill"
            case .displays: return "display"
            case .music: return "music.note"
            case .agents: return "dot.radiowaves.left.and.right"
            case .weather: return "cloud.sun.fill"
            case .modules: return "square.grid.2x2.fill"
            case .about: return "info"
            }
        }

        /// The tile colour behind the glyph. System Settings gives every pane
        /// its own colour so the row is found by colour before it is read;
        /// these follow the same instinct and echo what the pane controls —
        /// the agents pane green like a running light, weather sky blue.
        var tint: Color {
            switch self {
            case .general: return Color(red: 0.45, green: 0.47, blue: 0.51)
            case .appearance: return Color(red: 0.66, green: 0.36, blue: 0.86)
            case .displays: return Color(red: 0.20, green: 0.55, blue: 0.92)
            case .music: return Color(red: 0.95, green: 0.28, blue: 0.36)
            case .agents: return Color(red: 0.20, green: 0.72, blue: 0.40)
            case .weather: return Color(red: 0.24, green: 0.68, blue: 0.94)
            case .modules: return Color(red: 0.96, green: 0.60, blue: 0.13)
            case .about: return Color(red: 0.38, green: 0.42, blue: 0.90)
            }
        }
    }

    /// One sidebar row's icon: the pane's glyph in white on a rounded tile of
    /// the pane's colour, the shape macOS System Settings uses. Drawn at the
    /// list's own text size so the rows stay the height AppKit gives them.
    private struct PaneIcon: View {
        let pane: Pane

        var body: some View {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(pane.tint.gradient)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: pane.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }

    @State private var selection: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    PaneIcon(pane: pane)
                }
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
        case .appearance: AppearancePane(prefs: prefs, state: state)
        case .displays: DisplaysPane(prefs: prefs)
        case .music: MusicPane(api: api, prefs: prefs)
        case .agents: AgentsPane(prefs: prefs, usage: UsageHistoryService.shared)
        case .weather: WeatherPane(prefs: prefs, weather: weather, location: location, lockCards: lockCards)
        case .modules: ModulesPane(prefs: prefs, onboarding: onboarding)
        case .about: AboutPane()
        }
    }
}

// MARK: - Shared rows

/// A slider row in the shape every slider in this window uses: the label on
/// the left, a fixed-width slider, and the current value right-aligned in
/// monospaced digits so it cannot reflow as the slider moves.
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    /// The value as the user should read it — already carries its unit.
    let valueText: String
    /// Turns what the user typed back into a value (decision 094). Handed the
    /// field's text verbatim, unit and all, because only the row knows what
    /// its own units mean — `%` of what, `M` of what, or the word "Never".
    /// Returning nil rejects the edit and the field reverts.
    let parse: (String) -> Double?

    /// Non-nil only while the field is being edited: what the user is typing,
    /// which must not be reformatted under them between keystrokes.
    @State private var draft: String?
    @FocusState private var editing: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 170)
                TextField("", text: Binding(
                    get: { draft ?? valueText },
                    set: { draft = $0 }
                ))
                .focused($editing)
                .onSubmit { commit() }
                // Clicking away is as much a commit as pressing Return; the
                // alternative is a typed value that silently evaporates.
                .onChange(of: editing) { _, isEditing in
                    if !isEditing { commit() }
                }
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .font(.callout.monospacedDigit())
                .frame(width: 74)
            }
        }
    }

    /// Clamped to the row's range, and deliberately *not* snapped to `step`:
    /// dragging is what steps, and typing exists precisely to reach the values
    /// in between (decision 094).
    private func commit() {
        defer { draft = nil }
        guard let draft, let typed = parse(draft) else { return }
        value = min(max(typed, range.lowerBound), range.upperBound)
    }
}

/// The number in a slider field, ignoring any unit left in place: "150",
/// "150 ms" and "150ms" all read as 150. A decimal comma is accepted for the
/// locales that type one.
private func sliderNumber(_ text: String) -> Double? {
    let digits = text
        .filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        .replacingOccurrences(of: ",", with: ".")
    return Double(digits)
}

/// The same, for the token budget, whose own display is abbreviated: "2.5M"
/// and "500K" mean what they say, and a bare number is taken as tokens.
private func sliderTokens(_ text: String) -> Double? {
    guard let number = sliderNumber(text) else { return nil }
    let lowered = text.lowercased()
    if lowered.contains("m") { return number * 1_000_000 }
    if lowered.contains("k") { return number * 1_000 }
    return number
}

/// The caption every `footer:` in this window is drawn in.
///
/// Two initialisers, matching `Text`'s own: a literal keeps the markdown these
/// footers use (`**bold**`, `` `code` ``), while a string already computed
/// elsewhere — an enum's `detail`, say — is drawn verbatim so its punctuation
/// is never reinterpreted as markup.
private struct FooterText: View {
    private let content: Text

    init(_ key: LocalizedStringKey) { content = Text(key) }
    init(verbatim string: String) { content = Text(string) }

    var body: some View {
        content
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

// MARK: - General

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
                    FooterText("Available only when running the bundled Tempo.app — build it with `scripts/make-app.sh`.")
                } else if prefs.launchAtLoginNeedsApproval {
                    FooterText("Approve Tempo in System Settings ▸ General ▸ Login Items for this to take effect.")
                } else if let error = prefs.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section {
                LabeledContent("Expand") { Text("Hover the notch") }
                LabeledContent("Keep open") { Text("Click the panel") }
                LabeledContent("Close") { Text("Click anywhere outside") }

                SliderRow(
                    title: "Hover delay",
                    value: $prefs.hoverExpandDelayMS,
                    range: Preferences.minHoverExpandDelayMS...Preferences.maxHoverExpandDelayMS,
                    step: 10,
                    valueText: "\(Int(prefs.hoverExpandDelayMS)) ms",
                    parse: sliderNumber
                )
            } header: {
                Text("Interaction")
            } footer: {
                FooterText("How long the pointer must rest on the notch before the panel opens. The haptic tick fires at the same moment, so a shorter delay is also more likely to land while your finger is still on the trackpad. Longer keeps a pointer that is only passing over the notch from opening it. 0 opens the instant the pointer arrives.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

/// Everything about how the panel and the collapsed pill *look*: the panel's
/// material, the accent that tints its chrome, what is painted behind the
/// artwork, and how the visualizer bars are coloured.
private struct AppearancePane: View {
    @ObservedObject var prefs: Preferences
    let state: AppState

    @State private var artworkTint: NSColor?

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(PanelStyle.allCases) { style in
                        styleOption(style)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Expanded panel")
            } footer: {
                FooterText(verbatim: prefs.panelStyle.detail)
            }

            Section {
                Picker("Accent", selection: accentSourceBinding) {
                    ForEach(AccentSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                ColorPicker("Colour", selection: customAccentBinding, supportsOpacity: false)
                    .disabled(prefs.accentSource != .custom)
                LabeledContent("As the notch draws it") {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(NotchAccent.color(for: prefs))
                            .frame(width: 44, height: 18)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.primary.opacity(0.15))
                            )
                        Text(Preferences.hex(from: NotchAccent.nsColor(for: prefs)))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Accent as drawn, \(Preferences.hex(from: NotchAccent.nsColor(for: prefs)))")
                }
            } header: {
                Text("Accent colour")
            } footer: {
                FooterText("The accent tints chrome only — chips, rims, the scrubber, the file-drop target. It deliberately never reaches the agent lights: red, orange, white, green and grey are the signal itself there, and repainting them one colour would take the meaning with it.\n\nThe panel is always drawn dark, so a colour too dark to see on it is mixed toward white until it clears 3:1 against the panel — 4.5:1 with Increase Contrast on. That keeps the hue exactly and spends only saturation. All eight macOS system accents already clear the floor, so the clamp fires only on a pick that would otherwise have been invisible; the swatch above is the colour after any lift, which is what the notch actually paints.")
            }

            Section {
                Toggle("Glow behind the artwork", isOn: $prefs.albumGlow)
                SliderRow(
                    title: "Strength",
                    value: $prefs.albumGlowStrength,
                    range: 0...1,
                    step: 0.05,
                    valueText: "\(Int((prefs.albumGlowStrength * 100).rounded()))%",
                    // Shown as a percentage, stored as a 0…1 fraction.
                    parse: { sliderNumber($0).map { $0 / 100 } }
                )
                .disabled(!prefs.albumGlow)
                Toggle("Blurred cover behind the artwork", isOn: $prefs.albumArtBlur)
            } header: {
                Text("Album artwork")
            } footer: {
                FooterText("The glow is a bloom in the cover's own dominant colour, painted behind the artwork; strength scales its radius and its peak alpha together, from barely there to unmistakable. The blur is a separate look — a blurred copy of the cover sitting behind it — and the two combine in any order. Both need a cover: with no artwork neither is drawn, and nothing else on the panel changes.")
            }

            Section {
                Picker("Bars", selection: $prefs.spectrogramPalette) {
                    ForEach(SpectrogramPalette.allCases) { palette in
                        Text(palette.title).tag(palette)
                    }
                }
            } header: {
                Text("Visualizer")
            } footer: {
                FooterText("\(prefs.spectrogramPalette.detail)\n\nEvery option is a colour mapping over the five band magnitudes the audio tap already publishes, so this changes how the bars look and nothing about what they measure or what they cost. The bars still move only while audio is playing.")
            }
        }
        .formStyle(.grouped)
        .onAppear { artworkTint = state.artworkTint }
        .onReceive(state.objectWillChange) { _ in
            // `artworkTint` is published, but reading it in the same runloop
            // turn as `objectWillChange` would still see the old value.
            DispatchQueue.main.async { artworkTint = state.artworkTint }
        }
    }

    /// Picking "Custom" while no usable hex is stored would otherwise appear to
    /// do nothing — `resolvedAccent` falls back to the system accent — so the
    /// switch seeds the current system accent as the starting colour.
    private var accentSourceBinding: Binding<AccentSource> {
        Binding(
            get: { prefs.accentSource },
            set: { source in
                if source == .custom, Preferences.color(fromHex: prefs.customAccentHex) == nil {
                    prefs.customAccentHex = Preferences.hex(from: .controlAccentColor)
                }
                prefs.accentSource = source
            }
        )
    }

    private var customAccentBinding: Binding<Color> {
        Binding(
            get: {
                Color(nsColor: Preferences.color(fromHex: prefs.customAccentHex) ?? .controlAccentColor)
            },
            set: { picked in
                // A colour that cannot be expressed in sRGB hands back an empty
                // string; keeping the previous hex beats storing a value that
                // would silently resolve to the system accent.
                let hex = Preferences.hex(from: NSColor(picked))
                if !hex.isEmpty { prefs.customAccentHex = hex }
            }
        )
    }

    /// One preview card: the mini panel in that style, its name under it, and
    /// a ring when it is the chosen one. The whole card is the hit target —
    /// clicking a style applies it to the live notch immediately, so the panel
    /// itself is the real preview and this is only how you get there.
    private func styleOption(_ style: PanelStyle) -> some View {
        let isOn = prefs.panelStyle == style
        return Button {
            prefs.panelStyle = style
        } label: {
            VStack(spacing: 6) {
                PanelStylePreview(style: style, tint: artworkTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isOn ? Color.accentColor : Color.primary.opacity(0.12),
                                    lineWidth: isOn ? 2.5 : 1)
                    )
                Text(style.title)
                    .font(.caption)
                    .foregroundColor(isOn ? .primary : .secondary)
                    .fontWeight(isOn ? .semibold : .regular)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Displays

/// One attached display, for the picker. A struct rather than the tuple
/// `NotchGeometry.availableDisplays` returns, because `ForEach` needs an
/// `Identifiable` and a tuple cannot be one.
private struct DisplayOption: Identifiable {
    let id: String
    let name: String
    let hasNotch: Bool
}

/// Which screen Tempo lives on, what it does when an app goes full screen, and
/// whether it appears in a screen recording.
private struct DisplaysPane: View {
    @ObservedObject var prefs: Preferences

    @State private var displays: [DisplayOption] = []

    var body: some View {
        Form {
            Section {
                Picker("Show Tempo on", selection: $prefs.preferredDisplayUUID) {
                    Text("Automatic").tag("")
                    ForEach(displays) { display in
                        Text(display.hasNotch ? "\(display.name) (notch)" : display.name)
                            .tag(display.id)
                    }
                    if isPinnedDisplayMissing {
                        Text("Pinned display — not attached").tag(prefs.preferredDisplayUUID)
                    }
                }
                Toggle("Show the strip on external displays", isOn: $prefs.showStripOnExternalDisplays)

                SliderRow(
                    title: "Edge hold",
                    value: $prefs.edgeHoldDelayMS,
                    range: Preferences.minEdgeHoldDelayMS...Preferences.maxEdgeHoldDelayMS,
                    step: 10,
                    valueText: "\(Int(prefs.edgeHoldDelayMS)) ms",
                    parse: sliderNumber
                )
                .disabled(prefs.showStripOnExternalDisplays)
            } header: {
                Text("Placement")
            } footer: {
                FooterText("Automatic hugs the built-in notched display whenever it is attached, and falls back to whichever display carries the menu bar — with the lid closed, or on a Mac with no notch at all. Pinning overrides that order and keeps Tempo on the display you chose. The choice is stored as the display's UUID, not its ID, because macOS reassigns display IDs across reconnects; a pinned display that is currently unplugged is remembered, and Tempo falls back to the automatic order until it returns.\n\n“Show the strip on external displays” governs that notchless fallback. Off hides the strip: nothing is drawn, and clicks at the top of the screen go straight through to whatever is behind it. To open Tempo there, push the pointer into the very top edge until the menu bar drops — it opens only once that bar is down, so reaching for a full-screen browser's tabs at the same edge leaves it shut.\n\n**Edge hold** is how long the pointer must stay there *after* the menu bar has finished dropping. Longer makes the gesture more deliberate; 0 opens as soon as the bar lands. It applies only while the strip is hidden.")
            }

            Section {
                Picker("When an app is full screen", selection: $prefs.fullScreenBehavior) {
                    ForEach(FullScreenBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
            } header: {
                Text("Full screen")
            } footer: {
                FooterText(verbatim: prefs.fullScreenBehavior.detail)
            }

            Section {
                Toggle("Hide Tempo from screen capture", isOn: $prefs.hideFromScreenCapture)
            } header: {
                Text("Privacy")
            } footer: {
                FooterText("Sets the panel's window sharing type to none, so screenshots, screen recordings and shared screens capture whatever is behind it instead of the panel. The agent labels are folder names and the task lines are prompt excerpts — exactly what should not land in a screen share.\n\nIt changes nothing about what you see, and it does not cover the lock-screen cards: those are notifications, composited by macOS, and out of Tempo's reach.")
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshDisplays() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )) { _ in
            refreshDisplays()
        }
    }

    /// True when a display is pinned but is not among the attached ones — a
    /// monitor that has been unplugged since. The picker keeps a row for it so
    /// the choice reads as remembered rather than as a blank selection.
    private var isPinnedDisplayMissing: Bool {
        !prefs.preferredDisplayUUID.isEmpty
            && !displays.contains { $0.id == prefs.preferredDisplayUUID }
    }

    private func refreshDisplays() {
        displays = NotchGeometry.availableDisplays.map {
            DisplayOption(id: $0.uuid, name: $0.name, hasNotch: $0.hasNotch)
        }
    }
}

// MARK: - Music

/// The transport row, the track-change peek, how long paused media stays up,
/// and the Spotify account.
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
                MusicControlSlotsEditor(prefs: prefs)
            } header: {
                Text("Transport row")
            } footer: {
                FooterText("Drag a control from the palette onto a slot, or drag one slot onto another to swap them. Every slot is also a menu of the same controls — that is the keyboard and VoiceOver path, and it does everything dragging does.\n\nEmpty slots are skipped rather than drawn as gaps: the panel lays out only the controls you assigned and spreads them evenly, so the row is centred as a whole under the track title and an odd number of controls puts the middle one on the centre line. That is why the default fills the middle three of five and leaves the ends empty — it centres Play / Pause.\n\nMute is Tempo's own output mute, not the player's. Adding to a playlist is deliberately not offered here: it needs a target playlist, and that choice lives in the panel's playlist row, which carries its own button.")
            }

            Section {
                Toggle("Flash the track on a change", isOn: $prefs.sneakPeek)
                SliderRow(
                    title: "Stays up for",
                    value: $prefs.sneakPeekSeconds,
                    range: Preferences.minSneakPeekSeconds...Preferences.maxSneakPeekSeconds,
                    step: 0.5,
                    valueText: String(format: "%.1f s", prefs.sneakPeekSeconds),
                    parse: sliderNumber
                )
                .disabled(!prefs.sneakPeek)
                SliderRow(
                    title: "Paused media stays up",
                    value: $prefs.mediaIdleSeconds,
                    range: Preferences.minMediaIdleSeconds...Preferences.maxMediaIdleSeconds,
                    step: 10,
                    valueText: prefs.mediaIdleSeconds > 0 ? "\(Int(prefs.mediaIdleSeconds)) s" : "Never",
                    // "Never" is this row's own word for 0, so typing it back
                    // has to mean the same thing.
                    parse: { $0.lowercased().hasPrefix("n") ? 0 : sliderNumber($0) }
                )
            } header: {
                Text("Playback")
            } footer: {
                FooterText("A track change flashes the new title and artist under the collapsed notch and then fades. It never expands the panel and never takes focus; hovering the notch still opens it as usual.\n\n“Paused media stays up” is how long after playback stops the artwork, visualizer and controls remain before Tempo stops treating media as active. A pause to take a call, a scrub, or an app switch is a gap in listening, not the end of it — which is why this is a slider and not the fixed 60 seconds it used to be. At the far left it never times out, and the media UI stays until the player itself goes away.")
            }

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
                FooterText("Only used for adding the current song to a playlist. Artwork, the visualizer and the play / pause / skip controls all work without connecting anything.")
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
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear the search field")
                            .help("Clear")
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
                    FooterText(prefs.favoritePlaylistIDs.isEmpty
                               ? "Tick the ones you add songs to most and only those appear in the notch picker. With none ticked, all \(api.playlists.count) are offered."
                               : "\(prefs.favoritePlaylistIDs.count) selected. The notch picker offers these, starting on the first.")
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
                FooterText("Spotify requires every app using its Web API to be registered under its own developer account, so this can't be skipped or shipped inside Tempo. Spotify's AppleScript interface — which drives everything else here — has no playlist commands at all, so there is no way around the Web API for this one feature.\n\nThe Client ID is not a secret (Spotify's PKCE flow publishes it). It is saved to ~/Library/Application Support/Tempo/config.json, owner-only, along with the tokens; nothing is sent anywhere but Spotify.")
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
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text(playlist.name)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            // A 20pt row in a 190pt scroller is a small target for a list the
            // user ticks several of in a row.
            .frame(minHeight: 24)
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playlist.name)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
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

// MARK: Transport row editor

/// The five transport slots, laid out left to right the way the panel draws
/// them (decision 074).
///
/// Two ways to fill a slot, and the second is not a fallback. Dragging is the
/// direct one — a control from the palette onto a slot, or one slot onto
/// another to swap them — but a drag is unreachable from the keyboard and
/// invisible to VoiceOver, and decision 062 made that disqualifying. So every
/// slot is also a pull-down menu of the same five controls, which does
/// everything dragging does and is what the keyboard and VoiceOver drive.
///
/// The drag payload is a string rather than a `MusicControl`, because the drop
/// has to tell a control arriving *from the palette* (assign it) from a slot
/// arriving from elsewhere in the row (swap the two).
private struct MusicControlSlotsEditor: View {
    @ObservedObject var prefs: Preferences

    /// The slot the pointer is currently over during a drag, for the ring that
    /// shows where the drop will land.
    @State private var dropTarget: Int?

    private static let palettePrefix = "control:"
    private static let slotPrefix = "slot:"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Drag onto a slot")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ForEach(MusicControl.allCases) { control in
                        paletteChip(control)
                    }
                }
            }

            HStack(alignment: .top, spacing: 6) {
                ForEach(0..<Preferences.musicControlSlotCount, id: \.self) { index in
                    slot(index)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("In the panel")
                    .font(.caption)
                    .foregroundColor(.secondary)
                preview
            }

            HStack {
                Button("Reset to default") {
                    prefs.musicControlSlots = Preferences.defaultMusicControlSlots
                }
                .disabled(prefs.musicControlSlots == Preferences.defaultMusicControlSlots)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    /// One draggable source in the palette. `.none` is a source too — dragging
    /// it onto a slot is how a slot is emptied without opening its menu.
    private func paletteChip(_ control: MusicControl) -> some View {
        VStack(spacing: 3) {
            Image(systemName: control.symbol)
                .font(.body)
                .frame(width: 34, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
            Text(control.title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .draggable(Self.palettePrefix + control.rawValue)
        .help(control.title)
        .accessibilityLabel("\(control.title), drag onto a slot")
    }

    /// One slot: a draggable, droppable face carrying the assigned glyph, and
    /// under it the menu that assigns the same thing without a drag.
    private func slot(_ index: Int) -> some View {
        let control = prefs.musicControlSlots[index]
        return VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(control == .none ? 0.04 : 0.09))
                .frame(height: 38)
                .overlay(
                    Image(systemName: control.symbol)
                        .font(.title3)
                        .foregroundStyle(control == .none ? .secondary : .primary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(dropTarget == index ? Color.accentColor : Color.primary.opacity(0.12),
                                lineWidth: dropTarget == index ? 2 : 1)
                )
                .contentShape(Rectangle())
                .draggable(Self.slotPrefix + String(index))
                .dropDestination(for: String.self) { payloads, _ in
                    guard let payload = payloads.first else { return false }
                    return handle(payload, at: index)
                } isTargeted: { targeted in
                    dropTarget = targeted ? index : (dropTarget == index ? nil : dropTarget)
                }
                .accessibilityLabel("Slot \(index + 1), \(control.title)")

            Menu {
                ForEach(MusicControl.allCases) { option in
                    Button {
                        prefs.musicControlSlots[index] = option
                    } label: {
                        Label(option.title, systemImage: option.symbol)
                    }
                }
            } label: {
                Text(control.title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.button)
            .controlSize(.small)
            .help("Slot \(index + 1): \(control.title)")
            .accessibilityLabel("Slot \(index + 1)")
            .accessibilityValue(control.title)
        }
        .frame(maxWidth: .infinity)
    }

    /// The panel's own layout at Settings scale: empty slots dropped, the rest
    /// spread with equal spacers, which is what puts the middle control on the
    /// centre line. Mirrors `ContentView`'s transport row exactly, so this
    /// cannot show an arrangement the panel would not draw (UI Principle #4).
    private var preview: some View {
        let assigned = prefs.musicControlSlots.filter { $0 != .none }
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(assigned.enumerated()), id: \.offset) { _, control in
                Image(systemName: control.symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.85))
        )
        .overlay {
            if assigned.isEmpty {
                Text("No controls — the panel draws no transport row.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(assigned.isEmpty
                            ? "Preview: no transport row"
                            : "Preview: " + assigned.map(\.title).joined(separator: ", "))
    }

    /// Applies a dropped payload to `index`. A slot dragged onto another slot
    /// swaps the two — the row is a fixed five wide, so there is nowhere to
    /// insert into and a swap is the only reorder that keeps the width.
    private func handle(_ payload: String, at index: Int) -> Bool {
        if payload.hasPrefix(Self.slotPrefix) {
            guard let source = Int(payload.dropFirst(Self.slotPrefix.count)),
                  prefs.musicControlSlots.indices.contains(source),
                  source != index else { return false }
            prefs.musicControlSlots.swapAt(source, index)
            return true
        }
        if payload.hasPrefix(Self.palettePrefix),
           let control = MusicControl(rawValue: String(payload.dropFirst(Self.palettePrefix.count))) {
            prefs.musicControlSlots[index] = control
            return true
        }
        return false
    }
}

// MARK: - Agents

/// The agent lights, and the two token modules that read Claude Code's
/// transcripts (decision 079).
private struct AgentsPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var usage: UsageHistoryService

    var body: some View {
        Form {
            Section {
                Toggle("Agent session lights", isOn: $prefs.showAgentLights)
                Toggle("Token and timing figures", isOn: $prefs.showAgentStats)
                    .disabled(!prefs.showAgentLights)
                Picker("Collapsed pill", selection: $prefs.collapsedAgentLight) {
                    ForEach(CollapsedAgentLightMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Session lights")
            } footer: {
                FooterText("One light per open Claude Code session in the expanded panel, read from the status files under ~/.claude/status — Tempo only ever reads them, and installs no hooks of its own.\n\nThe figures put each session's context size, total tokens spent and turn length on its row, read from Claude Code's own transcripts. Switching them off stops those reads entirely.\n\n\(prefs.collapsedAgentLight.detail)")
            }

            Section {
                Toggle("Seven-day token history", isOn: $prefs.showUsageHistory)
            } header: {
                Text("Token history")
            } footer: {
                FooterText("A bar per day for the last seven days, plus the model you spent the most on, rolled up from every project's transcripts under ~/.claude/projects. That is a wider read than the per-session figures above — every project rather than the sessions you have open — which is why it stays off until you ask for it.\n\nNumbers only are taken out of a transcript: a timestamp, a model name and the token counts. Prompt text, tool output and file paths are never decoded, retained or logged. Tempo counts input + cache-creation + output tokens and excludes cache reads, which dominate the raw totals and would make every figure here meaningless.")
            }

            Section {
                Toggle("Five-hour pace bar", isOn: $prefs.showRateLimitPace)
                SliderRow(
                    title: "Window budget",
                    value: $prefs.rateLimitWindowTokens,
                    range: Preferences.minRateLimitWindowTokens...Preferences.maxRateLimitWindowTokens,
                    step: 250_000,
                    valueText: UsageHistoryService.shortTokens(Int(prefs.rateLimitWindowTokens)),
                    parse: sliderTokens
                )
                .disabled(!prefs.showRateLimitPace)
                Text(calibrationHint)
                    .font(.caption)
                    .foregroundColor(.secondary)
                SliderRow(
                    title: "Warn at",
                    value: $prefs.rateLimitWarnPercent,
                    range: Preferences.minRateLimitWarnPercent...Preferences.maxRateLimitWarnPercent,
                    step: 1,
                    valueText: "\(Int(prefs.rateLimitWarnPercent))%",
                    parse: sliderNumber
                )
                .disabled(!prefs.showRateLimitPace)
            } header: {
                Text("Rate-limit pace")
            } footer: {
                FooterText("This figure is an estimate. Claude Code persists no rate-limit signal on disk — verified on this machine — so Tempo cannot read your real limit, how much of it you have used, or when it resets. The bar compares tokens counted out of local transcripts in a rolling five-hour window against the budget you set here, and nothing else. Read it as a pace gauge, not as a limit.\n\nThe budget is therefore yours to calibrate: set it near the busiest window you actually run, shown above, rather than guessing. Counting matches the history above — input + cache-creation + output, cache reads excluded — so a budget set from that figure and the bar measure the same thing.\n\nPast the warning threshold the bar changes appearance, not just hue: a warning glyph appears, the percentage goes semibold, and the fill visibly crosses the mark drawn on the track.")
            }
        }
        .formStyle(.grouped)
    }

    /// The only honest calibration Tempo can offer: the heaviest five-hour
    /// window it has actually seen. Deliberately does not start the scan —
    /// that read is what the pace switch turns on, and a Settings visit must
    /// not sweep every project's transcripts on its own (Agent Guideline #5).
    private var calibrationHint: String {
        if usage.busiestWindowTokens > 0 {
            return "Busiest five-hour window in the last seven days: "
                + "\(UsageHistoryService.shortTokens(usage.busiestWindowTokens)) tokens."
        }
        if usage.lastScan == nil {
            return "Nothing scanned yet — the busiest window Tempo has seen appears here "
                + "after the first scan, which runs once the pace bar is on."
        }
        return "No token spend found in the last seven days, so there is nothing to calibrate against yet."
    }
}

// MARK: - Modules

private struct ModulesPane: View {
    @ObservedObject var prefs: Preferences
    let onboarding: OnboardingController

    var body: some View {
        Form {
            Section {
                Toggle("Audio visualizer", isOn: $prefs.showVisualizer)
                Toggle("CPU and memory graphs", isOn: $prefs.showUsageGraph)
                Toggle("Audio output and volume", isOn: $prefs.showAudioOutput)
                Toggle("File shelf", isOn: $prefs.showFileShelf)
            } header: {
                Text("Show in the notch")
            } footer: {
                FooterText("The visualizer sits in the collapsed pill; the graphs, audio row and file shelf appear in the expanded panel. Each also hides itself automatically when it has nothing to show.\n\nThe file shelf opens the notch as a drop target when you drag a file near it, and keeps a copy you can drag back out later. Switching it off stops Tempo watching for drags at all.\n\nThe agent lights and the token modules have their own pane.")
            }

            Section {
                LabeledContent("Welcome") {
                    Button("Show the welcome again") { onboarding.replay() }
                }
            } header: {
                Text("First run")
            } footer: {
                FooterText("Replays the first-run hello and the permission steps in the notch.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

/// What Tempo is, and the one thing you can do *to* Tempo rather than
/// configure about it: quit.
///
/// Quit lives here because `LSUIElement` leaves Tempo with no Dock icon and no
/// menu-bar item, so the main menu's ⌘Q is reachable only while the Settings
/// window is key — which is not a way out anyone can be expected to find
/// (decision 066).
private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version") { Text(version) }
                LabeledContent("Agent status") { Text("~/.claude/status (read-only)") }
            } header: {
                Text("Tempo")
            } footer: {
                FooterText("A notch surface for what's playing, what your Mac is doing, and which Claude Code sessions need you.")
            }
            Section {
                LabeledContent("Quit") {
                    Button("Quit Tempo") { NSApplication.shared.terminate(nil) }
                }
            } footer: {
                FooterText("Stops Tempo entirely — the notch panel, the lock-screen cards and the agent lights all go away. Tempo has no Dock icon or menu-bar item, so this pane is the only place it can be quit apart from ⌘Q while this window is in front. Open Tempo from Finder or Spotlight to bring it back; with “Open Tempo at login” on it also returns at your next login.")
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

// MARK: - Weather

/// The lock-screen cards and where their weather comes from (decisions 058,
/// 059).
///
/// This pane carries the one thing Tempo cannot do for itself: two switches in
/// System Settings decide whether a delivered card is *legible* on the lock
/// screen, and neither is ours to set. It says so plainly rather than letting
/// a granted-but-invisible card read as a broken feature.
private struct WeatherPane: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var weather: WeatherService
    @ObservedObject var location: LocationService
    @ObservedObject var lockCards: LockScreenNotifier

    var body: some View {
        Form {
            Section {
                Toggle("Show cards on the lock screen", isOn: $prefs.showLockScreenCards)
                Toggle("Weather", isOn: $prefs.lockCardShowsWeather)
                    .disabled(!prefs.showLockScreenCards)
                Toggle("What's playing", isOn: $prefs.lockCardShowsMusic)
                    .disabled(!prefs.showLockScreenCards)
            } header: {
                Text("Lock screen")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tempo cannot draw on the lock screen — macOS composites it in a secure context that excludes app windows. These are ordinary notifications, posted when the screen locks, updated in place while it stays locked, and withdrawn when you unlock.")
                    authorizationNote
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section {
                Toggle("Use my location", isOn: $prefs.weatherUseLocation)
                    .disabled(!weatherActive)
                TextField("City", text: $prefs.weatherCity, prompt: Text("Hoboken"))
                    .disabled(!weatherActive)
                Picker("Units", selection: $prefs.weatherUnit) {
                    ForEach(TemperatureUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .disabled(!weatherActive)
            } header: {
                Text("Location")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if location.isResolvingCity {
                        Text("Looking up that city…")
                    } else if let failure = location.cityLookupFailure {
                        Text(failure)
                    } else if let place = location.place {
                        Text(place.name.isEmpty
                             ? "Using \(coordinateText(place))."
                             : "Using \(place.name).")
                    }
                    locationNote
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section {
                LabeledContent("Now") {
                    HStack(spacing: 6) {
                        if let reading = weather.reading {
                            Image(systemName: reading.symbolName)
                            Text(reading.summary)
                        } else {
                            Text(weatherActive ? (weather.failure ?? "Loading…") : "Weather is off.")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Button("Refresh") { weather.fetch() }
                    .disabled(!weatherActive)
            } header: {
                Text("Current conditions")
            } footer: {
                FooterText("Weather comes from Open-Meteo, which needs no account and no key. Tempo sends it a rounded coordinate and nothing else — no identifier, and never your Mac's name or your session data.")
            }
        }
        .formStyle(.grouped)
    }

    /// Whether anything weather-related is actually running — both switches.
    private var weatherActive: Bool { prefs.showLockScreenCards && prefs.lockCardShowsWeather }

    @ViewBuilder
    private var authorizationNote: some View {
        if lockCards.registrationBlocked {
            // Checked first, because this is not a permission state at all and
            // reporting it as one sends the user to a System Settings pane
            // where Tempo does not appear (decision 081).
            VStack(alignment: .leading, spacing: NotchMetrics.tightSpacing) {
                Text("macOS did not answer Tempo's request to read its notification settings, so no card can be posted and there is nothing here for the Notifications pane to fix.")
                Text("Observed once on this machine with an ad-hoc signed build, where the call never returned rather than failing. It has since answered normally. If this message is showing, a rebuild — `scripts/make-app.sh` — and a relaunch is the first thing to try.")
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            authorizationStateNote
        }
    }

    @ViewBuilder
    private var authorizationStateNote: some View {
        switch lockCards.authorization {
        case .authorized, .provisional, .ephemeral:
            // Granted is not sufficient, and this is the trap the feature dies
            // in silently: the *default* preview setting renders a locked card
            // as a contentless "Tempo · Notification".
            HStack(spacing: 6) {
                Text("Allowed. In System Settings ▸ Notifications ▸ Tempo, also turn on **Show on Lock Screen** and set **Show previews** to *Always*, or the cards appear locked but blank.")
                Button("Open") { LockScreenNotifier.openSystemNotificationSettings() }
                    .buttonStyle(.link)
            }
        case .denied:
            HStack(spacing: 6) {
                Text("Notifications are turned off for Tempo, so no card can be posted.")
                Button("Open Notification settings") { LockScreenNotifier.openSystemNotificationSettings() }
                    .buttonStyle(.link)
            }
        default:
            HStack(spacing: 6) {
                Text("Tempo has not asked for notification permission yet.")
                Button("Ask now") { Task { await lockCards.requestAuthorization() } }
                    .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private var locationNote: some View {
        switch location.authorization {
        case .denied, .restricted:
            Text("Location access is off, so the typed city is used. Turn it back on in System Settings ▸ Privacy & Security ▸ Location Services.")
        case .notDetermined:
            if prefs.weatherUseLocation {
                Text("macOS will ask for approximate location the first time weather is fetched. Until then, the typed city is used.")
            } else {
                Text("Weather uses the typed city.")
            }
        default:
            if !prefs.weatherUseLocation {
                Text("Weather uses the typed city.")
            }
        }
    }

    private func coordinateText(_ place: WeatherPlace) -> String {
        String(format: "%.2f, %.2f", place.latitude, place.longitude)
    }
}
