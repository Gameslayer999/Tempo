import CoreLocation
import SwiftUI
import UserNotifications

/// What drops out of the notch on first run (decision 057): the cursive
/// `hello` writing itself, then the handful of things Tempo needs a human to
/// say yes to.
///
/// Lives inside the notch panel, in the slot the expanded view normally
/// occupies, so it inherits the panel's width (405pt on this machine) and its
/// non-activating nature. Nothing here takes keyboard input — the one step
/// that would (the Spotify Client ID) opens the Settings window instead.
struct OnboardingView: View {
    @ObservedObject var onboarding: OnboardingController
    @ObservedObject var prefs: Preferences
    @ObservedObject var api: SpotifyWebAPI
    @ObservedObject var lockCards: LockScreenNotifier
    @ObservedObject var location: LocationService
    let openSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch onboarding.phase {
            case .hello, .inactive:
                helloStroke
            case .setup:
                setupCards
            }
        }
        // Order matters, and getting it wrong is what made the setup cards
        // bleed past the panel's edges: padding applied *after* a fixed frame
        // is added outside it, so the content laid out at panelWidth + 52pt
        // inside a panel exactly panelWidth wide. Pad first, then frame — the
        // same order `ContentView.expandedContent` uses.
        .padding(.horizontal, NotchMetrics.contentInset)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: NotchGeometry.panelWidth, alignment: .top)
    }

    // MARK: hello

    private var helloStroke: some View {
        // The stroke weight is Apple's own — 8% of the word's height — so it
        // has to follow whatever size the word is actually drawn at rather than
        // being a fixed point value. `GeometryReader` supplies that size and
        // `HelloScript.lineWidth(fitting:)` derives it from the same fit the
        // shape performs, so the two cannot drift apart (decision 061).
        GeometryReader { geo in
            HelloScript(progress: onboarding.strokeProgress)
                // Round caps and joins are what make a drawn stroke read as a
                // pen rather than as a plotted curve — and Apple's artwork is
                // authored with a round cap, so this matches it rather than
                // merely resembling it.
                .stroke(
                    style: StrokeStyle(
                        lineWidth: HelloScript.lineWidth(fitting: geo.size),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .foregroundStyle(.white)
                // Barely-there bloom: enough that the ink sits *in* the black
                // panel rather than on it, well short of the neon-sign look a
                // heavier halo gives this stroke weight.
                .shadow(color: .white.opacity(0.18), radius: 7)
        }
        // Apple's word is 3.36 : 1, so at the panel's content width it wants
        // about 105pt of height; this frame leaves it a little air top and
        // bottom without letting it grow past the width.
        .frame(height: 112)
        .padding(.horizontal, 8)
            // A hand writes at a near-steady speed. `easeInOut` over the whole
            // word runs the middle at ~1.6x the average and then brakes hard
            // into the `o`, which is most of what read as clunky; this eases in
            // briefly, holds an even pace, and settles at the end.
            // Reduce Motion gets the finished word, not a 2.6s write-on (HIG,
            // and the same rule the panel's spring follows).
            .animation(
                reduceMotion ? nil : .timingCurve(0.2, 0, 0.35, 1, duration: OnboardingController.strokeDuration),
                value: onboarding.strokeProgress
            )
            .opacity(onboarding.helloOpacity)
            .animation(.easeInOut(duration: OnboardingController.fadeDuration), value: onboarding.helloOpacity)
            // The whole word is a skip target. No visible "Skip" chrome: this
            // is a three-second animation, and a button competing with it would
            // be the loudest thing on a screen whose point is the writing.
            .contentShape(Rectangle())
            .onTapGesture { onboarding.skipToSetup() }
            .accessibilityElement()
            .accessibilityLabel("hello")
            .accessibilityHint("Click to skip the animation")
            .accessibilityAddTraits(.isButton)
            .onAppear {
                if reduceMotion { onboarding.strokeProgress = 1 }
            }
    }

    // MARK: setup

    private var setupCards: some View {
        VStack(alignment: .leading, spacing: NotchMetrics.sectionSpacing) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tempo lives in your notch")
                    // `.title3` is 15pt on macOS — the size this already was,
                    // now tracking the user's text-size setting.
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text("Hover the notch to open this panel. A few things need your say-so — all optional, all changeable in Settings.")
                    .font(NotchType.subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: NotchMetrics.rowSpacing) {
                audioRow
                notificationsRow
                if prefs.showLockScreenCards && prefs.lockCardShowsWeather {
                    locationRow
                }
                spotifyRow
            }

            HStack {
                Button("Open Settings") { openSettings() }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .font(NotchType.subtitle)
                    .foregroundStyle(.secondary)
                    // The secondary escape route was a 11pt text run with no
                    // padding — a ~60x13pt target. Padded out it clears the
                    // same 28pt band the primary button sits in.
                    .padding(.horizontal, 6)
                    .frame(minHeight: NotchMetrics.hitTarget)
                    .contentShape(Rectangle())
                Spacer()
                Button("Get Started") { onboarding.finish() }
                    .buttonStyle(GetStartedButtonStyle())
            }
            .padding(.top, 2)
        }
        .transition(.opacity)
    }

    private var audioRow: some View {
        SetupRow(
            symbol: "waveform",
            title: "Audio visualizer",
            detail: "macOS asks the first time audio plays. Until then the bars stay still.",
            status: .informational,
            actionTitle: "Open",
            action: {
                OnboardingController.openSystemSettings(
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
                )
            }
        )
    }

    private var notificationsRow: some View {
        SetupRow(
            symbol: "lock.display",
            title: "Lock screen cards",
            detail: lockCards.authorization == .denied
                ? "Denied — turn Tempo back on in System Settings."
                : "Weather and what's playing, while your Mac is locked.",
            status: statusFor(lockCards.authorization),
            actionTitle: lockCards.authorization == .denied ? "Open" : "Allow",
            action: {
                if lockCards.authorization == .denied {
                    LockScreenNotifier.openSystemNotificationSettings()
                    return
                }
                Task {
                    await lockCards.requestAuthorization()
                    // Only switch the feature on if the user actually said
                    // yes: turning it on after a denial would leave a switch
                    // claiming a feature that cannot post anything.
                    if lockCards.authorization == .authorized {
                        prefs.showLockScreenCards = true
                    }
                }
            }
        )
    }

    private var locationRow: some View {
        SetupRow(
            symbol: "location",
            title: "Weather location",
            detail: location.authorization == .denied || location.authorization == .restricted
                ? "Denied — set a city in Settings ▸ Weather."
                : "Approximate only, so the weather card knows where you are.",
            status: statusFor(location.authorization),
            actionTitle: location.authorization == .denied ? "Settings" : "Allow",
            action: {
                if location.authorization == .denied {
                    openSettings()
                } else {
                    location.requestAuthorizationIfNeeded()
                }
            }
        )
    }

    private var spotifyRow: some View {
        SetupRow(
            symbol: "music.note",
            title: "Spotify playlists",
            detail: api.isAuthed
                ? "Connected."
                : "Optional — add the playing song to a playlist from the notch.",
            status: api.isAuthed ? .granted : .informational,
            actionTitle: api.isAuthed ? nil : "Set up",
            action: openSettings
        )
    }

    private func statusFor(_ status: UNAuthorizationStatus) -> SetupRow.Status {
        switch status {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        default: return .pending
        }
    }

    private func statusFor(_ status: CLAuthorizationStatus) -> SetupRow.Status {
        if status.grantsLocation { return .granted }
        switch status {
        case .denied, .restricted: return .denied
        default: return .pending
        }
    }
}

/// One thing to say yes to: a glyph, a name, a line of why, and the state it's
/// in. The action button disappears once the thing is granted — a row that has
/// nothing left to do should not still be offering a button.
private struct SetupRow: View {
    enum Status {
        /// Granted — nothing left to do.
        case granted
        /// Not asked yet.
        case pending
        /// Refused; the row's action goes to System Settings instead.
        case denied
        /// Nothing to grant here, just something to know.
        case informational

        /// Semantic, not literal white: the panel is forced to dark
        /// appearance, so `.secondary` resolves to the same dimmed white these
        /// opacities were hand-mixing — and unlike a hard-coded alpha it
        /// brightens when the user turns on Increase Contrast.
        var color: Color {
            switch self {
            case .granted: return .green
            case .pending: return .secondary
            case .denied: return .orange
            case .informational: return Color.primary.opacity(0.3)
            }
        }

        /// Spoken by VoiceOver and shown in the row's tooltip, so the state is
        /// not carried by the glyph's colour alone.
        var label: String {
            switch self {
            case .granted: return "allowed"
            case .pending: return "not asked yet"
            case .denied: return "denied"
            case .informational: return "for information"
            }
        }
    }

    let symbol: String
    let title: String
    let detail: String
    let status: Status
    var actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : symbol)
                .font(.body)
                .foregroundStyle(status.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(NotchType.control.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(NotchType.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: NotchMetrics.tightSpacing)

            if status != .granted, let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(SetupActionButtonStyle())
                    .accessibilityLabel("\(actionTitle) — \(title)")
            }
        }
        // The whole row is one thing to read out, ending with the state the
        // coloured glyph was the only carrier of.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(status.label)")
        .help("\(title) — \(status.label). \(detail)")
    }
}

/// Small pill button for a setup row's action.
private struct SetupActionButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchType.caption.weight(.medium))
            .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.6 : 0.95))
            .padding(.horizontal, 11)
            // Was ~18pt tall. These are the buttons the whole first run turns
            // on, so they are the last place to make the user aim.
            .frame(minHeight: NotchMetrics.compactHitTarget)
            .background(
                Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.22 : (hovering ? 0.18 : 0.12)))
            )
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .pointingHandCursor()
    }
}

/// The one prominent button in the flow.
private struct GetStartedButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchType.control.weight(.semibold))
            // Stays literal black-on-white: this is the flow's one filled
            // button, and its contrast comes from being the inverse of the
            // panel rather than from the appearance it sits in.
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .frame(minHeight: NotchMetrics.hitTarget)
            .background(
                Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.75 : (hovering ? 1 : 0.92)))
            )
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .pointingHandCursor()
    }
}
