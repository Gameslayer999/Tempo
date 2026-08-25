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
        .padding(.horizontal, NotchShape.expandedTopRadius + 7)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: NotchGeometry.panelWidth, alignment: .top)
    }

    // MARK: hello

    private var helloStroke: some View {
        VStack(spacing: 10) {
            HelloScript(progress: onboarding.strokeProgress)
                // Round caps and joins are what make a drawn stroke read as a
                // pen rather than as a plotted curve.
                // Thin and even, which is the single most recognisable thing
                // about Apple's hello — a heavier stroke reads as a logo
                // rather than as handwriting.
                .stroke(style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.white)
                .frame(height: 96)
                // Reduce Motion gets the finished word, not a 2.4s write-on
                // (HIG, and the same rule the panel's spring follows).
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: OnboardingController.strokeDuration),
                    value: onboarding.strokeProgress
                )

            Text("Tempo")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                // Fades in behind the tail of the stroke rather than landing
                // with it, so the word stays the only thing moving.
                .opacity(onboarding.strokeProgress > 0.75 ? 1 : 0)
                .animation(.easeIn(duration: 0.5), value: onboarding.strokeProgress > 0.75)
        }
        // The whole word is a skip target. No visible "Skip" chrome: this is a
        // three-second animation, and a button competing with it would be the
        // loudest thing on a screen whose point is the writing.
        .contentShape(Rectangle())
        .onTapGesture { onboarding.skipToSetup() }
        .onAppear {
            if reduceMotion { onboarding.strokeProgress = 1 }
        }
    }

    // MARK: setup

    private var setupCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tempo lives in your notch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Hover the notch to open this panel. A few things need your say-so — all optional, all changeable in Settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
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
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
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

        var color: Color {
            switch self {
            case .granted: return .green
            case .pending: return .white.opacity(0.35)
            case .denied: return .orange
            case .informational: return .white.opacity(0.25)
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
                .font(.system(size: 13))
                .foregroundStyle(status.color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if status != .granted, let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(SetupActionButtonStyle())
            }
        }
    }
}

/// Small pill button for a setup row's action.
private struct SetupActionButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.6 : 0.95))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(.white.opacity(configuration.isPressed ? 0.22 : (hovering ? 0.18 : 0.12)))
            )
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }
}

/// The one prominent button in the flow.
private struct GetStartedButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(.white.opacity(configuration.isPressed ? 0.75 : (hovering ? 1 : 0.92)))
            )
            .contentShape(Capsule())
            .onHover { hovering = $0 }
    }
}
