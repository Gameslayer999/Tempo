import SwiftUI

/// The cursive word "hello", as one continuous stroke that can be drawn on
/// (decision 057).
///
/// Authored as a single unbroken path — pen down at the foot of the `h`, pen
/// up at the end of the `o`'s flourish — because that is the whole point:
/// `.trim(from: 0, to: progress)` walks one subpath by arc length, so a single
/// stroke writes itself letter by letter the way a hand would. Split into five
/// per-letter subpaths it would instead draw all five at once, each a fifth of
/// the way along.
///
/// Coordinates are in a fixed 640 x 230 design box (`designSize`) and scaled to
/// whatever frame the view gets, preserving aspect. The control points were
/// tuned by rendering the curve and looking at it, not by arithmetic.
struct HelloScript: Shape {
    /// How much of the stroke has been drawn, 0...1.
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// The design box the control points below are expressed in.
    static let designSize = CGSize(width: 588, height: 238)
    /// Origin of that box within the raw coordinates (the curve was authored
    /// on a larger canvas and is shifted back here rather than re-typed).
    private static let designOrigin = CGPoint(x: 44, y: 14)

    /// Start point, then one `(control1, control2, end)` triple per cubic
    /// segment, in raw authoring coordinates.
    private static let start = CGPoint(x: 78, y: 220)
    private static let segments: [(CGPoint, CGPoint, CGPoint)] = [
        // h — the ascender goes up, loops over, and comes back to the baseline…
        (CGPoint(x: 58, y: 152), CGPoint(x: 56, y: 76), CGPoint(x: 100, y: 46)),
        (CGPoint(x: 132, y: 25), CGPoint(x: 148, y: 70), CGPoint(x: 136, y: 116)),
        (CGPoint(x: 127, y: 152), CGPoint(x: 116, y: 186), CGPoint(x: 116, y: 220)),
        // …then the shoulder.
        (CGPoint(x: 122, y: 176), CGPoint(x: 146, y: 144), CGPoint(x: 176, y: 148)),
        (CGPoint(x: 202, y: 152), CGPoint(x: 206, y: 182), CGPoint(x: 200, y: 220)),
        // e — up into the eye, around it, and out to the right.
        (CGPoint(x: 214, y: 204), CGPoint(x: 230, y: 170), CGPoint(x: 251, y: 152)),
        (CGPoint(x: 272, y: 135), CGPoint(x: 290, y: 149), CGPoint(x: 279, y: 173)),
        (CGPoint(x: 268, y: 197), CGPoint(x: 234, y: 198), CGPoint(x: 216, y: 188)),
        (CGPoint(x: 208, y: 216), CGPoint(x: 234, y: 234), CGPoint(x: 264, y: 229)),
        (CGPoint(x: 290, y: 224), CGPoint(x: 306, y: 209), CGPoint(x: 318, y: 192)),
        // l — a tall narrow loop.
        (CGPoint(x: 312, y: 146), CGPoint(x: 314, y: 84), CGPoint(x: 334, y: 52)),
        (CGPoint(x: 350, y: 26), CGPoint(x: 374, y: 35), CGPoint(x: 368, y: 71)),
        (CGPoint(x: 361, y: 113), CGPoint(x: 338, y: 153), CGPoint(x: 332, y: 197)),
        (CGPoint(x: 328, y: 222), CGPoint(x: 348, y: 234), CGPoint(x: 372, y: 223)),
        // l — and the second one.
        (CGPoint(x: 392, y: 170), CGPoint(x: 394, y: 90), CGPoint(x: 414, y: 54)),
        (CGPoint(x: 430, y: 27), CGPoint(x: 454, y: 37), CGPoint(x: 448, y: 73)),
        (CGPoint(x: 441, y: 115), CGPoint(x: 418, y: 155), CGPoint(x: 412, y: 199)),
        (CGPoint(x: 408, y: 224), CGPoint(x: 428, y: 236), CGPoint(x: 452, y: 225)),
        // o — round, closing on itself, then the short exit tick. Apple's
        //     hello ends on a tick, not a long flourish; a trailing swash was
        //     the most obviously wrong thing about the first pass.
        (CGPoint(x: 474, y: 213), CGPoint(x: 486, y: 193), CGPoint(x: 508, y: 177)),
        (CGPoint(x: 537, y: 157), CGPoint(x: 574, y: 167), CGPoint(x: 576, y: 197)),
        (CGPoint(x: 578, y: 225), CGPoint(x: 547, y: 241), CGPoint(x: 521, y: 232)),
        (CGPoint(x: 497, y: 223), CGPoint(x: 492, y: 195), CGPoint(x: 510, y: 177)),
        (CGPoint(x: 530, y: 156), CGPoint(x: 562, y: 158), CGPoint(x: 586, y: 180)),
        (CGPoint(x: 598, y: 190), CGPoint(x: 606, y: 186), CGPoint(x: 612, y: 172)),
    ]

    func path(in rect: CGRect) -> Path {
        // Uniform scale, centred — the word must never stretch to the panel's
        // aspect ratio.
        let scale = min(rect.width / Self.designSize.width, rect.height / Self.designSize.height)
        let drawn = CGSize(width: Self.designSize.width * scale, height: Self.designSize.height * scale)
        let offset = CGPoint(
            x: rect.minX + (rect.width - drawn.width) / 2,
            y: rect.minY + (rect.height - drawn.height) / 2
        )

        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: offset.x + (point.x - Self.designOrigin.x) * scale,
                y: offset.y + (point.y - Self.designOrigin.y) * scale
            )
        }

        var path = Path()
        path.move(to: place(Self.start))
        for (control1, control2, end) in Self.segments {
            path.addCurve(to: place(end), control1: place(control1), control2: place(control2))
        }
        // Trimming here rather than via the `.trim` modifier keeps the shape
        // self-contained, so `progress` is the only thing a caller animates.
        return path.trimmedPath(from: 0, to: max(0, min(progress, 1)))
    }
}
