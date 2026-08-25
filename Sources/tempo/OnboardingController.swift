import AppKit
import Combine
import Foundation

/// Drives the first-run hello and the setup cards that follow it
/// (decision 057).
///
/// The whole sequence plays *inside the notch panel* — the hello unrolls out
/// of the notch and the cards take its place — so this owns no window of its
/// own. What it owns is the phase, and one flag on `AppState` that holds the
/// panel open while it runs: `isOnboarding` feeds `displayedExpanded`, so the
/// existing hover-out, outside-click and hit-region machinery all keep the
/// panel open for free, without a second "is it pinned" concept.
///
/// The panel is non-activating and can never become key (Agent Guideline #3),
/// which is why nothing here asks for typed input. Every setup row is a button
/// or a link; the one step that needs a keyboard — the Spotify Client ID —
/// opens the Settings window instead.
@MainActor
final class OnboardingController: ObservableObject {
    enum Phase: Equatable {
        /// Not running. The panel behaves normally.
        case inactive
        /// The word is writing itself.
        case hello
        /// The setup rows.
        case setup
    }

    @Published private(set) var phase: Phase = .inactive
    /// 0...1 along the stroke. Driven by an explicit animation rather than by
    /// the phase, so the writing speed is independent of how long the word is
    /// held afterwards.
    @Published var strokeProgress: CGFloat = 0

    /// How long the word takes to write itself, and how long it is held
    /// complete before the cards replace it.
    static let strokeDuration: TimeInterval = 2.4
    static let holdDuration: TimeInterval = 0.7

    private let state: AppState
    private let prefs: Preferences
    private var advanceTask: Task<Void, Never>?

    init(state: AppState, prefs: Preferences) {
        self.state = state
        self.prefs = prefs
    }

    /// Called once at launch. Does nothing on every run after the first —
    /// `hasSeenHello` is set when the user finishes (or dismisses) the cards,
    /// never when the animation merely plays, so a crash mid-hello does not
    /// silently consume the only first run.
    func startIfFirstRun() {
        guard !prefs.hasSeenHello else { return }
        play()
    }

    /// Replay from Settings ▸ About. Same sequence; finishing it re-sets the
    /// flag, so this is idempotent (Agent Guideline #8).
    func replay() {
        play()
    }

    private func play() {
        guard phase == .inactive else { return }
        advanceTask?.cancel()
        strokeProgress = 0
        phase = .hello
        state.isOnboarding = true

        advanceTask = Task { [weak self] in
            // A frame of slack before the stroke starts, so the panel has
            // actually unrolled out of the notch before the pen touches down —
            // otherwise the first third of the word is written into a panel
            // that is still growing.
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.beginStroke()

            try? await Task.sleep(for: .seconds(Self.strokeDuration + Self.holdDuration))
            guard !Task.isCancelled else { return }
            self?.advanceToSetup()
        }
    }

    private func beginStroke() {
        guard phase == .hello else { return }
        // The view applies the animation; this is only the target value.
        strokeProgress = 1
    }

    private func advanceToSetup() {
        guard phase == .hello else { return }
        phase = .setup
    }

    /// Skip straight to the cards — the click target over the writing word,
    /// so nobody has to sit through 3 seconds of animation twice.
    func skipToSetup() {
        guard phase == .hello else { return }
        advanceTask?.cancel()
        advanceTask = nil
        strokeProgress = 1
        phase = .setup
    }

    /// Done. Records that the hello has been seen and hands the panel back to
    /// its normal hover/pin behaviour, collapsed.
    func finish() {
        advanceTask?.cancel()
        advanceTask = nil
        phase = .inactive
        prefs.hasSeenHello = true
        state.isOnboarding = false
        // Collapse rather than leave the panel pinned open on the expanded
        // view the user never asked for.
        state.isExpanded = false
        state.isHovered = false
    }

    var isActive: Bool { phase != .inactive }

    /// Open a System Settings privacy pane by its anchor. Used by the setup
    /// rows for the two permissions Tempo cannot grant on the user's behalf.
    static func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
