import AppKit
import SwiftUI

/// A miniature of the expanded panel drawn in one `PanelStyle`, for the
/// picker in Settings ▸ General ▸ Appearance.
///
/// The synthetic desktop behind the mini panel is load-bearing, not
/// decoration: three of the four styles are translucent materials, and a
/// material over the Settings window's own flat background is
/// indistinguishable from an opaque fill. SwiftUI's materials and
/// `glassEffect` both sample whatever is drawn behind them *in the same
/// window*, so drawing a gradient (plus a bright window over it) behind the
/// mini panel is what makes "Regular glass" and "Clear glass" actually look
/// different here.
///
/// The layer stack mirrors `ContentView.backgroundShape` exactly — substrate,
/// material, clear-glass scrim, black top blend, rim light — so the preview
/// can't drift into showing something the panel doesn't do (UI Principle #4).
struct PanelStylePreview: View {
    let style: PanelStyle
    /// The current album's dominant colour, so `.tinted` previews the tint the
    /// panel would carry right now. Nil falls back to plain glass, exactly as
    /// the panel does.
    let tint: NSColor?

    static let size = CGSize(width: 104, height: 74)

    /// Scaled-down counterparts of `NotchShape.expanded*Radius` and the
    /// panel's `stripHeight`.
    private let shape = NotchShape(topCornerRadius: 8, bottomCornerRadius: 10)
    private let stripHeight: CGFloat = 15

    var body: some View {
        ZStack(alignment: .top) {
            backdrop
            // Short of the card's full height, so the desktop stays visible
            // below it — the panel hangs off the notch, it isn't the screen.
            panel
                .frame(height: 56)
                .padding(.horizontal, 9)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// Stand-in desktop: a gradient dark at the top-left and bright at the
    /// bottom-right, with an opaque window over it, so a translucent style
    /// visibly picks up both a dark and a light region.
    private var backdrop: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.13, blue: 0.30),
                    Color(red: 0.45, green: 0.24, blue: 0.44),
                    Color(red: 0.96, green: 0.66, blue: 0.38),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .frame(width: 46, height: 30)
                .offset(x: 6, y: 8)
        }
    }

    private var panel: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black.opacity(0.05))
            glassLayer
            if style == .clear {
                // Tracks `ContentView.contentScrim` at standard contrast.
                // This preview is deliberately not contrast-aware: it shows
                // what the style does, not what the user's accessibility
                // settings will additionally do to it.
                Color.black.opacity(0.30)
            }
            LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: stripHeight + 9)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(shape)
        .overlay(rim)
    }

    @ViewBuilder
    private var glassLayer: some View {
        if style == .solid {
            shape.fill(Color.black.opacity(0.93))
        } else {
            ZStack {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(glass, in: shape)
                } else {
                    shape.fill(style == .clear ? .ultraThinMaterial : .regularMaterial)
                }
                // The same painted wash the panel carries (decision 064) —
                // without it this card showed "Album tint" as plain glass,
                // which is what the panel itself was doing and is exactly the
                // bug being fixed.
                if style == .tinted, let wash = PanelTint.wash(for: tint) {
                    shape.fill(wash)
                }
            }
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        switch style {
        case .clear: return .clear
        case .tinted: return .regular.tint(tint.map { Color(nsColor: $0) })
        case .regular, .solid: return .regular
        }
    }

    private var rim: some View {
        shape
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.16), .white.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: stripHeight)
                    LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10)
                    Color.white
                }
            }
            .allowsHitTesting(false)
    }

    /// Shorthand for the panel's contents: the cover, two title lines and the
    /// transport row. Never text — at this size it would only be noise.
    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(coverColor)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(.white.opacity(0.85)).frame(width: 34, height: 3)
                    Capsule().fill(.white.opacity(0.45)).frame(width: 22, height: 3)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(.white.opacity(0.6)).frame(width: 5, height: 5)
                }
                Spacer(minLength: 0)
                Circle().fill(.green).frame(width: 4, height: 4)
                Circle().fill(.orange).frame(width: 4, height: 4)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, stripHeight + 4)
    }

    /// The real cover when one is playing, so the tint style's preview and its
    /// cover agree; otherwise a neutral placeholder.
    private var coverColor: Color {
        tint.map { Color(nsColor: $0) } ?? Color.white.opacity(0.28)
    }
}
