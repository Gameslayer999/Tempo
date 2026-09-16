import AppKit
import SwiftUI

/// Typography, metrics and state appearance shared by every Tempo surface
/// (decision 062).
///
/// It exists because the surfaces had accumulated 31 `.system(size:)`
/// literals, several private notions of "secondary text", and two places that
/// each decided independently what colour an agent state is. One vocabulary
/// here is what lets the notch, the panel, the onboarding cards and Settings
/// look like one app — and what makes a rule ("nothing below 10pt", "no state
/// told apart by colour alone") enforceable rather than aspirational.

// MARK: - Typography

/// Every font the notch surfaces use, by role.
///
/// Named text styles rather than `.system(size:)` literals: a style tracks
/// the platform's own metrics and the user's text-size setting, a literal
/// tracks nothing (HIG ▸ Typography). At the default setting these resolve to
/// the sizes the panel already drew — `.caption2` is 10pt on macOS,
/// `.subheadline` 11, `.callout` 12, `.headline` 13 semibold — so this is a
/// change of mechanism, not a change of measurements. The single exception is
/// the file shelf's 9pt item name: macOS has no text style below 10pt, and
/// 9pt was under Apple's own legibility floor, so it moves up to 10.
enum NotchType {
    /// The single most important line on a surface — the track title.
    static let title = Font.headline
    /// The line under a title: artist, a row's explanatory detail.
    static let subtitle = Font.subheadline
    /// A list row's own text — agent labels, task lines, playlist names.
    static let row = Font.subheadline
    /// Button, chip and picker labels.
    static let control = Font.callout
    /// Secondary text: device names, shelf item names, inline notes.
    static let caption = Font.caption2
    /// Figures that must not reflow as they tick.
    static let figure = Font.caption2.monospacedDigit()
    /// The label above a section ("AGENTS").
    static let sectionHeader = Font.caption2.weight(.semibold)
}

// MARK: - Metrics

/// The panel's spacing and hit-target scale. Four spacing values, not
/// fourteen: the sections were spaced 12 / 8 / 7 / 6 / 4 / 3 / 2 by whoever
/// wrote each one, which is what made the stack read as unrelated widgets
/// stacked up rather than one panel (HIG ▸ Layout: alignment and consistent
/// spacing are what show which things are related).
enum NotchMetrics {
    /// Minimum clickable square for a panel control (decision 014).
    static let hitTarget: CGFloat = 28
    /// Minimum for a control that lives in a wrapped row of many, where a
    /// full 28pt square each would cost more panel height than the row earns.
    /// Still comfortably above the 16pt and 12pt targets it replaces.
    static let compactHitTarget: CGFloat = 24

    /// Between two *groups* of sections — the media block and the system
    /// block. Larger than `sectionSpacing` on purpose: proximity is the
    /// cheapest way to show what belongs with what (HIG ▸ Layout), and a panel
    /// whose every gap is identical reads as one undifferentiated list.
    static let groupSpacing: CGFloat = 16
    /// Between sibling sections inside one group.
    static let sectionSpacing: CGFloat = 12
    /// Between sibling rows inside one section.
    static let rowSpacing: CGFloat = 8
    /// Between a label and the thing it labels.
    static let tightSpacing: CGFloat = 4

    /// Horizontal inset of panel content. Clears the shape's straight sides,
    /// which sit `expandedTopRadius` inside the panel rect.
    static let contentInset: CGFloat = NotchShape.expandedTopRadius + 7
}

// MARK: - Agent state appearance

/// How one agent state looks — colour, shape, motion and its spoken name — in
/// one place, so the collapsed dot and the expanded row can never disagree
/// about what a state means.
///
/// Every state carries a **shape** as well as a colour. Before this the five
/// states were green / orange / red / white / grey discs and nothing else,
/// which is precisely the pattern the HIG rules out: rendered in greyscale —
/// or seen by the ~8% of men with a red-green deficiency — a running session
/// and a session that had been blocked on the user for ten minutes were the
/// same grey dot. The fill, the ring and (where there is room for it) the
/// glyph now each differ, so the signal survives with the colour taken away.
struct AgentAppearance {
    var color: Color
    /// Drawn inside the dot wherever there is room — the expanded rows at
    /// 12pt. `nil` for the two states whose meaning is "nothing to do here",
    /// which should stay quiet rather than earn a glyph.
    var symbol: String?
    /// Filled disc versus hollow ring. This is the difference that still
    /// reads at the collapsed pill's 8pt, where a glyph would be mush.
    var isFilled: Bool
    /// Only the state the user has to act on moves (UI Principle #5).
    var pulses: Bool
    /// The halo the attention states carry whether or not they move.
    var glows: Bool
    /// Recessive: present, but not competing with the visualizer beside it.
    var isDim: Bool
    /// Diameter as a fraction of the slot the caller reserved.
    ///
    /// The quiet states draw smaller than the ones that want something. This
    /// is what separates *running* from *blocked* at the collapsed pill's 8pt,
    /// where there is no room for a glyph: measured over a greyscale render,
    /// two same-size discs differing only in hue scored 37 out of a possible
    /// 2500 — indistinguishable — and the size step takes the same pair well
    /// clear. It costs no layout, because the slot width is unchanged.
    var scale: CGFloat
    /// What VoiceOver reads out, and what the state is called in a tooltip.
    var label: String

    /// The summary across a set of sessions — what the collapsed pill draws.
    init(_ summary: AgentSummary) {
        switch summary {
        case .error:
            self.init(color: .red, symbol: "exclamationmark", isFilled: true,
                      pulses: false, glows: true, isDim: false, scale: 1.0, label: "error")
        case .blocked:
            self.init(color: .orange, symbol: "questionmark", isFilled: true,
                      pulses: true, glows: true, isDim: false, scale: 1.0,
                      label: "waiting for you")
        case .finished:
            self.init(color: .white, symbol: "checkmark", isFilled: true,
                      pulses: false, glows: true, isDim: false, scale: 1.0,
                      label: "finished, unread")
        case .running:
            // Full colour, but the smallest disc here: running is the state
            // nobody has to do anything about, and at full size it was within
            // a hair of blocked once the hue was taken away.
            self.init(color: .green, symbol: nil, isFilled: true,
                      pulses: false, glows: false, isDim: false, scale: 0.72,
                      label: "running")
        case .idle, .none:
            // Hollow, not a dim disc: "idle" and "running" were previously
            // told apart only by hue and a 0.4 alpha, which is the exact
            // comparison that disappears in greyscale.
            self.init(color: .gray, symbol: nil, isFilled: false,
                      pulses: false, glows: false, isDim: true, scale: 1.0, label: "idle")
        }
    }

    /// One session's own state. An unacknowledged finished turn outranks the
    /// idle underneath it (decision 044); a state Tempo does not recognise
    /// draws as a hollow grey ring rather than asserting something it cannot
    /// support (UI Principle #4).
    init(_ session: AgentSession) {
        if session.unread {
            self.init(.finished)
            return
        }
        switch session.state {
        case "running": self.init(.running)
        case "blocked": self.init(.blocked)
        case "error": self.init(.error)
        case "idle": self.init(.idle)
        default:
            self.init(color: .gray, symbol: nil, isFilled: false,
                      pulses: false, glows: false, isDim: true, scale: 1.0,
                      label: "unknown state")
        }
    }

    private init(color: Color, symbol: String?, isFilled: Bool, pulses: Bool,
                 glows: Bool, isDim: Bool, scale: CGFloat, label: String) {
        self.color = color
        self.symbol = symbol
        self.isFilled = isFilled
        self.pulses = pulses
        self.glows = glows
        self.isDim = isDim
        self.scale = scale
        self.label = label
    }
}

/// One agent light, at whatever size the caller has room for.
///
/// Below `symbolThreshold` the glyph is dropped and the fill/ring difference
/// carries the state on its own — an `exclamationmark` rendered into 8pt is
/// noise, and noise in the collapsed pill is worse than the plain dot it
/// replaced (UI Principle #1).
struct AgentDot: View {
    var appearance: AgentAppearance
    var size: CGFloat
    /// Driven by the owner, which holds the repeating animation. Passed in
    /// rather than owned here so a row and a pill dot can pulse on their own
    /// schedules without this view needing a lifecycle.
    var pulsePhase: Bool = false

    /// Smallest *drawn* diameter a glyph is legible inside of. The expanded
    /// rows are above it, the collapsed pill's 8pt dots are below.
    static let symbolThreshold: CGFloat = 10

    var body: some View {
        let drawn = size * appearance.scale
        return ZStack {
            if appearance.isFilled {
                Circle().fill(appearance.color)
            } else {
                Circle().strokeBorder(appearance.color, lineWidth: max(1.25, drawn * 0.18))
            }
            if let symbol = appearance.symbol, drawn >= Self.symbolThreshold {
                Image(systemName: symbol)
                    // Solid black on the light, not a `.destinationOut` punch:
                    // the punch let the state's own glow shine up through the
                    // hole, which left the glyph at roughly half contrast
                    // against the disc instead of full. Black works over
                    // white, orange and red alike, so it still needs no
                    // per-state colour.
                    .font(.system(size: drawn * 0.66, weight: .black))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: drawn, height: drawn)
        // The slot the caller reserved, so a smaller disc still occupies its
        // share of the row and nothing shifts as a session changes state.
        .frame(width: size, height: size)
        .opacity(appearance.isDim ? 0.55 : (appearance.pulses && pulsePhase ? 0.45 : 1))
        .scaleEffect(appearance.pulses && pulsePhase ? 1.2 : 1)
        .shadow(color: appearance.color.opacity(appearance.glows ? 0.7 : 0), radius: 3)
    }
}

// MARK: - Album tint

/// The colour the `.tinted` panel style actually paints, derived from the
/// current cover (decision 064).
///
/// Shared by the panel and by its preview in Settings, because those two
/// drifting apart is exactly the "never show a lying signal" failure — the
/// preview's whole job is to show what picking that style will do.
enum PanelTint {
    /// How much album colour the panel carries, and how light that colour is
    /// allowed to get. Both are matters of taste rather than measurement,
    /// which is why they are single named knobs.
    static let washOpacity: Double = 0.22
    static let maxBrightness: CGFloat = 0.62

    /// The wash to paint over the glass, or nil when there is no cover to
    /// sample — in which case `.tinted` is plain regular glass, as documented.
    ///
    /// Hue and saturation are the cover's; **brightness is capped**.
    /// `NSImage.dominantColor()` floors brightness at 0.6 — it wants a tint
    /// vivid enough for `Glass.tint` to do something with — and an uncapped
    /// wash of a bright cover measurably costs white-text contrast. Modelling
    /// the glass as a flat grey and mixing the wash over it, worst case across
    /// the hue circle (fully saturated yellow, the lightest hue):
    ///
    ///     backdrop            no wash   capped 0.62   uncapped
    ///     dark glass 0.15       15.08         10.99       8.17
    ///     mid glass 0.45         4.76          4.44       3.44
    ///     bright glass 0.75      1.83          2.09       1.71
    ///
    /// So the cap is what keeps the mid case near 4.5:1 instead of well under
    /// it, and the album's identity is unharmed because that lives in hue, not
    /// in lightness. Note the wash is not what makes the bright-backdrop case
    /// bad — the glass is already at 1.83 there with no tint at all, and the
    /// wash slightly *improves* it. That is the panel-wide legibility question
    /// tracked separately in NEXT_STEPS, not a tint problem.
    static func wash(for tint: NSColor?) -> Color? {
        guard let tint, let hsb = tint.usingColorSpace(.sRGB) else { return nil }
        let capped = NSColor(
            hue: hsb.hueComponent,
            saturation: hsb.saturationComponent,
            brightness: min(hsb.brightnessComponent, maxBrightness),
            alpha: 1
        )
        return Color(nsColor: capped).opacity(washOpacity)
    }
}

// MARK: - Accent

/// The one colour Tempo's *chrome* is tinted with — chips, rims, the scrubber,
/// drop targets (decision 069).
///
/// **It never touches an agent light.** `AgentAppearance` above is the one
/// place that maps state → colour, and those five hues are the signal itself:
/// decision 062 measured the state encoding at 827 out of 2500 over a greyscale
/// render precisely because red / orange / white / green / grey are fixed and
/// mean something. Repainting them in a user-chosen accent would collapse that
/// to one hue and take the meaning with it (UI Principle #2). `AgentAppearance`
/// is therefore deliberately untouched by everything in this enum, and must
/// stay that way.
///
/// ### Why the accent is clamped
///
/// The panel is forced dark (`NSAppearance(named: .darkAqua)` in
/// `NotchWindow`), and a custom accent can be any hex the user types — a navy,
/// a near-black grey, a deep purple. Unclamped, those draw chrome that is
/// simply not there: modelled against the same flat grey backdrop `PanelTint`
/// uses, `#001F5B` sits at **0.97:1** and pure `#0000FF` at **1.76:1**, which
/// is a control the user cannot see (UI Principle #4 — a signal that isn't
/// legible is worse than none).
///
/// So the clamp is a **floor on relative luminance**, not on HSB brightness.
/// HSB brightness is the wrong knob here: `#0000FF` is already at brightness
/// 1.0, so a `PanelTint`-style brightness floor would leave it exactly as dark
/// as it was. The colour is instead mixed toward white until it clears the
/// floor, which preserves HSB hue *exactly* (mixing with white scales
/// `max − min` uniformly) and spends only saturation.
///
/// Floors are set from the WCAG ratio the two contrast settings each owe, over
/// that same backdrop — 3:1 (non-text/UI) normally, 4.5:1 under Increase
/// Contrast:
///
///     accent            as typed      clamped 0.16   clamped 0.27
///     macOS Blue          3.76:1         3.76:1         4.60:1
///     macOS Purple        3.65:1         3.65:1         4.60:1
///     macOS Graphite      4.63:1         4.63:1         4.63:1
///     macOS Yellow        9.98:1         9.98:1         9.98:1
///     #0000FF             1.76:1         3.02:1         4.60:1
///     #001F5B (navy)      0.97:1         3.02:1         4.60:1
///     #3A0066 (purple)    0.99:1         3.02:1         4.60:1
///     #000000             0.72:1         3.02:1         4.60:1
///
/// The top half of that table is the point: **all eight macOS system accents
/// already clear the normal floor**, so the shipped default (`.system`) passes
/// through byte-identical and the clamp only ever fires on a pick that would
/// otherwise have been invisible.
enum NotchAccent {
    /// Relative luminance floor on the dark panel — 3:1 against the modelled
    /// backdrop, the WCAG minimum for a non-text UI component.
    static let minLuminance: CGFloat = 0.16
    /// The floor under Increase Contrast — 4.5:1, text-grade.
    static let increasedContrastMinLuminance: CGFloat = 0.27

    /// The accent to paint chrome with, clamped for the dark panel.
    @MainActor static func color(for prefs: Preferences) -> Color {
        Color(nsColor: nsColor(for: prefs))
    }

    /// The same colour for AppKit call sites, and for anything that needs to
    /// derive a shade from it.
    ///
    /// `Preferences.resolvedAccent` returns `nil` for "use the system accent" —
    /// which is every case but a `.custom` source with a parseable hex — so the
    /// fallback here is `NSColor.controlAccentColor`, the colour set in System
    /// Settings ▸ Appearance.
    @MainActor static func nsColor(for prefs: Preferences) -> NSColor {
        legible(prefs.resolvedAccent ?? .controlAccentColor)
    }

    /// The clamp on its own, for any colour that has to read as chrome on the
    /// dark panel. Returns the colour unchanged when it already clears the
    /// floor, which is the common case.
    ///
    /// Increase Contrast is read from `NSWorkspace` rather than from
    /// `@Environment(\.colorSchemeContrast)` because these are static tokens
    /// with no view to read an environment from; the consequence is that
    /// toggling the setting takes effect at the next redraw rather than
    /// instantly.
    static func legible(_ color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return color }
        let base = (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        let floor = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ? increasedContrastMinLuminance
            : minLuminance
        guard luminance(base) < floor else { return rgb }
        // Bisect the mix fraction rather than solving for it: the sRGB
        // transfer function makes the closed form ugly, and 16 halvings put
        // the result inside 1/65536 of the floor for a handful of `pow`s.
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<16 {
            let mid = (low + high) / 2
            if luminance(whitened(base, mid)) < floor { low = mid } else { high = mid }
        }
        let lifted = whitened(base, high)
        return NSColor(srgbRed: lifted.0, green: lifted.1, blue: lifted.2,
                       alpha: rgb.alphaComponent)
    }

    private static func whitened(_ rgb: (CGFloat, CGFloat, CGFloat),
                                 _ amount: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        (rgb.0 + (1 - rgb.0) * amount,
         rgb.1 + (1 - rgb.1) * amount,
         rgb.2 + (1 - rgb.2) * amount)
    }

    /// WCAG relative luminance of an sRGB triple.
    private static func luminance(_ rgb: (CGFloat, CGFloat, CGFloat)) -> CGFloat {
        0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }

    private static func linear(_ component: CGFloat) -> CGFloat {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}

// MARK: - Pointer

/// Turns the pointer into a hand over a control.
///
/// The panel's controls draw no chrome at rest — the transport glyphs, the
/// gear, the shelf's remove button and the device chips are bare until the
/// pointer is already on them, so hovering is how you *discover* they are
/// controls at all. The cursor is the one cue that arrives before the hover
/// highlight does.
///
/// macOS 15's `pointerStyle` is the right mechanism where it exists, because
/// the system owns the cursor's lifetime: a control that disappears out from
/// under the pointer — the shelf's remove button, or the whole panel on
/// collapse — cannot strand a hand cursor on the desktop. The macOS 14
/// fallback pushes and pops `NSCursor` itself and unwinds on disappear, which
/// is exactly the case that would otherwise leave it stuck.
///
/// Deliberately *not* applied to the Settings window: those are standard
/// AppKit controls, and on macOS the arrow over a real button is the platform
/// convention (the hand means "link"). This is for Tempo's own chrome-less
/// surfaces, where the convention has nothing to work with.
struct PointingHandCursor: ViewModifier {
    @State private var pushed = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content
                .onHover { inside in
                    if inside {
                        guard !pushed else { return }
                        NSCursor.pointingHand.push()
                        pushed = true
                    } else {
                        popIfPushed()
                    }
                }
                .onDisappear { popIfPushed() }
        }
    }

    private func popIfPushed() {
        guard pushed else { return }
        NSCursor.pop()
        pushed = false
    }
}

extension View {
    /// Pointer becomes a hand over this control. See `PointingHandCursor`.
    func pointingHandCursor() -> some View { modifier(PointingHandCursor()) }
}
