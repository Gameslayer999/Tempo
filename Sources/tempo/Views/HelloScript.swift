import SwiftUI

/// The cursive word "hello" — Apple's own lettering — as a stroke that can be
/// drawn on (decisions 057, 060, 061).
///
/// The geometry is Apple's `hello-en` artwork, which ships as *centreline*
/// paths (`fill="none" stroke-width="60" stroke-linecap="round"`), not as
/// filled glyph outlines. That is the whole reason it can be used here: a
/// filled outline trimmed by `trimmedPath` would draw its own contour, whereas
/// a centreline trimmed by arc length writes itself the way a pen does.
///
/// Two earlier hand-authored passes were replaced by this. What they got wrong,
/// measured against the real thing:
/// - **Proportion.** Apple's word is 3.36 : 1 (width : height). Both hand-drawn
///   passes were about 1.5 : 1 — the letters were cramped to under half their
///   proper width, which is what made it read as the wrong word-shape.
/// - **Curvature.** The ascenders were long straight diagonals; Apple's are
///   continuously curving, with no straight run anywhere in the word.
/// - **Weight.** Apple strokes at 8% of the word's height (`strokeRatio`). The
///   hand-drawn passes used a 3pt hairline, roughly a third of that.
///
/// Apple splits the word into two subpaths — the `h`'s entry-and-ascender, then
/// everything from the `h`'s stem through the `o` — and they meet end to end
/// (subpath 0 finishes at ≈(49, 198), subpath 1 opens at ≈(50, 188)). They are
/// therefore drawn *in sequence*, weighted by arc length, so the pen reads as
/// one continuous hand. Trimming a single `Path` holding both would instead
/// advance both at once — two parts of the word appearing together, which is
/// exactly the failure mode the original single-subpath authoring avoided.
///
/// Design coordinates are y-down, normalised so the artwork is 200 units tall.
struct HelloScript: Shape {
    /// How much of the word has been drawn, 0...1, across both subpaths.
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Apple's stroke weight, as a fraction of the design height.
    static let strokeRatio: CGFloat = 0.0804

    // MARK: Geometry

    /// `(start, curves)` per subpath, in design coordinates.
    private static let subpathData: [(CGPoint, [(CGPoint, CGPoint, CGPoint)])] = [
        (
            CGPoint(x: 0.0, y: 171.9),
            [
                (CGPoint(x: 29.8, y: 155.3), CGPoint(x: 56.9, y: 134.1), CGPoint(x: 87.6, y: 97.9)),
                (CGPoint(x: 108.6, y: 73.1), CGPoint(x: 119.8, y: 44.9), CGPoint(x: 120.4, y: 25.5)),
                (CGPoint(x: 120.6, y: 11.0), CGPoint(x: 113.6, y: 0.0), CGPoint(x: 100.5, y: 0.0)),
                (CGPoint(x: 86.1, y: 0.0), CGPoint(x: 76.9, y: 11.0), CGPoint(x: 71.3, y: 36.2)),
                (CGPoint(x: 65.2, y: 63.9), CGPoint(x: 60.6, y: 95.7), CGPoint(x: 49.1, y: 197.6)),
            ]
        ),
        (
            CGPoint(x: 50.2, y: 187.6),
            [
                (CGPoint(x: 56.1, y: 135.8), CGPoint(x: 78.6, y: 97.9), CGPoint(x: 107.2, y: 97.9)),
                (CGPoint(x: 124.4, y: 97.9), CGPoint(x: 135.3, y: 111.5), CGPoint(x: 132.2, y: 131.1)),
                (CGPoint(x: 130.5, y: 142.6), CGPoint(x: 128.4, y: 154.4), CGPoint(x: 126.1, y: 168.1)),
                (CGPoint(x: 123.3, y: 185.3), CGPoint(x: 131.2, y: 198.7), CGPoint(x: 154.9, y: 198.7)),
                (CGPoint(x: 189.6, y: 198.7), CGPoint(x: 227.4, y: 179.4), CGPoint(x: 246.7, y: 149.6)),
                (CGPoint(x: 253.3, y: 139.4), CGPoint(x: 256.0, y: 130.3), CGPoint(x: 256.3, y: 121.5)),
                (CGPoint(x: 256.5, y: 105.4), CGPoint(x: 247.4, y: 93.3), CGPoint(x: 231.3, y: 93.3)),
                (CGPoint(x: 211.0, y: 93.3), CGPoint(x: 195.4, y: 116.4), CGPoint(x: 195.4, y: 145.9)),
                (CGPoint(x: 195.4, y: 177.5), CGPoint(x: 212.6, y: 199.7), CGPoint(x: 249.0, y: 199.7)),
                (CGPoint(x: 298.5, y: 199.7), CGPoint(x: 353.4, y: 140.3), CGPoint(x: 378.6, y: 73.9)),
                (CGPoint(x: 385.7, y: 55.2), CGPoint(x: 388.4, y: 37.8), CGPoint(x: 388.4, y: 25.6)),
                (CGPoint(x: 388.4, y: 11.2), CGPoint(x: 383.9, y: 0.1), CGPoint(x: 371.0, y: 0.1)),
                (CGPoint(x: 358.4, y: 0.1), CGPoint(x: 350.1, y: 9.9), CGPoint(x: 342.6, y: 25.4)),
                (CGPoint(x: 333.8, y: 43.3), CGPoint(x: 327.3, y: 69.1), CGPoint(x: 324.6, y: 98.3)),
                (CGPoint(x: 317.9, y: 171.6), CGPoint(x: 332.9, y: 198.7), CGPoint(x: 368.6, y: 198.7)),
                (CGPoint(x: 411.9, y: 198.7), CGPoint(x: 460.0, y: 138.4), CGPoint(x: 484.6, y: 73.7)),
                (CGPoint(x: 491.6, y: 55.2), CGPoint(x: 494.3, y: 37.8), CGPoint(x: 494.3, y: 25.6)),
                (CGPoint(x: 494.3, y: 11.2), CGPoint(x: 489.7, y: 0.1), CGPoint(x: 476.9, y: 0.1)),
                (CGPoint(x: 464.3, y: 0.1), CGPoint(x: 456.0, y: 9.9), CGPoint(x: 448.4, y: 25.4)),
                (CGPoint(x: 439.7, y: 43.3), CGPoint(x: 433.2, y: 69.1), CGPoint(x: 430.5, y: 98.3)),
                (CGPoint(x: 423.8, y: 171.6), CGPoint(x: 438.8, y: 198.7), CGPoint(x: 470.7, y: 198.7)),
                (CGPoint(x: 502.5, y: 198.7), CGPoint(x: 519.8, y: 170.9), CGPoint(x: 530.1, y: 141.5)),
                (CGPoint(x: 540.4, y: 112.4), CGPoint(x: 553.0, y: 94.4), CGPoint(x: 579.3, y: 94.4)),
                (CGPoint(x: 601.0, y: 94.4), CGPoint(x: 618.1, y: 110.5), CGPoint(x: 618.1, y: 140.8)),
                (CGPoint(x: 618.1, y: 174.3), CGPoint(x: 596.4, y: 199.5), CGPoint(x: 568.9, y: 199.7)),
                (CGPoint(x: 544.7, y: 200.0), CGPoint(x: 528.9, y: 180.4), CGPoint(x: 530.5, y: 150.9)),
                (CGPoint(x: 532.3, y: 118.2), CGPoint(x: 552.2, y: 94.4), CGPoint(x: 578.2, y: 94.4)),
                (CGPoint(x: 593.2, y: 94.4), CGPoint(x: 605.8, y: 101.1), CGPoint(x: 615.7, y: 108.3)),
                (CGPoint(x: 642.6, y: 127.9), CGPoint(x: 663.3, y: 115.8), CGPoint(x: 671.2, y: 96.4)),
            ]
        ),
    ]

    private static let subpaths: [Path] = subpathData.map { start, curves in
        var path = Path()
        path.move(to: start)
        for (control1, control2, end) in curves {
            path.addCurve(to: end, control1: control1, control2: control2)
        }
        return path
    }

    /// Each subpath's share of the total arc length. This is what makes the two
    /// of them read as one pen: `progress` is spent on subpath 0 in proportion
    /// to how much of the ink it actually is, not 50/50.
    private static let shares: [CGFloat] = {
        let lengths = subpaths.map(arcLength(of:))
        let total = lengths.reduce(0, +)
        guard total > 0 else { return lengths.map { _ in 0 } }
        return lengths.map { $0 / total }
    }()

    /// The ink's own bounds, grown by half a stroke on every side so the
    /// rounded caps and the outer edge of the stroke stay inside the frame
    /// rather than being clipped by it.
    private static let designBounds: CGRect = {
        guard let first = subpaths.first else { return .zero }
        let union = subpaths.dropFirst().reduce(first.boundingRect) { $0.union($1.boundingRect) }
        let bleed = union.height * strokeRatio / 2
        return union.insetBy(dx: -bleed, dy: -bleed)
    }()

    // MARK: Layout

    /// The stroke width to draw with, for a view of `size` — derived from the
    /// same fit the shape itself performs, so the two cannot drift apart.
    static func lineWidth(fitting size: CGSize) -> CGFloat {
        designBounds.height * strokeRatio * scale(fitting: size)
    }

    private static func scale(fitting size: CGSize) -> CGFloat {
        guard designBounds.width > 0, designBounds.height > 0 else { return 0 }
        return min(size.width / designBounds.width, size.height / designBounds.height)
    }

    func path(in rect: CGRect) -> Path {
        let bounds = Self.designBounds
        guard rect.width > 0, rect.height > 0, bounds.width > 0, bounds.height > 0 else { return Path() }

        // Uniform scale, centred — the word must never stretch to the panel's
        // aspect ratio.
        let scale = Self.scale(fitting: rect.size)
        let drawn = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let transform = CGAffineTransform.identity
            .translatedBy(
                x: rect.minX + (rect.width - drawn.width) / 2,
                y: rect.minY + (rect.height - drawn.height) / 2
            )
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)

        let clamped = max(0, min(progress, 1))
        var result = Path()
        var consumed: CGFloat = 0
        for (index, subpath) in Self.subpaths.enumerated() {
            let share = Self.shares[index]
            guard share > 0 else { continue }
            let local = (clamped - consumed) / share
            consumed += share
            guard local > 0 else { break }
            result.addPath(local >= 1 ? subpath : subpath.trimmedPath(from: 0, to: local))
        }
        return result.applying(transform)
    }

    // MARK: Arc length

    /// Flattened length of a path. Cubics are sampled rather than solved — this
    /// runs once, at first use, and only needs to be accurate enough to
    /// apportion `progress` between the two subpaths.
    private static func arcLength(of path: Path) -> CGFloat {
        let samples = 32
        var total: CGFloat = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        path.forEach { element in
            switch element {
            case let .move(to):
                current = to
                subpathStart = to
            case let .line(to):
                total += distance(current, to)
                current = to
            case let .quadCurve(to, control):
                var previous = current
                for step in 1...samples {
                    let point = quadPoint(current, control, to, CGFloat(step) / CGFloat(samples))
                    total += distance(previous, point)
                    previous = point
                }
                current = to
            case let .curve(to, control1, control2):
                var previous = current
                for step in 1...samples {
                    let point = cubicPoint(current, control1, control2, to, CGFloat(step) / CGFloat(samples))
                    total += distance(previous, point)
                    previous = point
                }
                current = to
            case .closeSubpath:
                total += distance(current, subpathStart)
                current = subpathStart
            }
        }
        return total
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func cubicPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return CGPoint(
            x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y
        )
    }

    private static func quadPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
        )
    }
}
