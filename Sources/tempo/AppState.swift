import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    /// Pinned by a click on the expanded panel; stays expanded on mouse-out
    /// while true.
    @Published var isExpanded = false
    /// Mouse currently within the active (strip or full-panel) region.
    @Published var isHovered = false
    @Published var nowPlaying: NowPlaying? = nil
    @Published var artwork: NSImage? = nil {
        didSet { artworkTint = artwork?.dominantColor() }
    }
    /// Dominant colour of the current cover, recomputed only when the cover
    /// itself changes. Drives the `.tinted` panel style (decision 030); nil
    /// when there is no artwork, which that style reads as plain glass.
    @Published private(set) var artworkTint: NSColor? = nil
    @Published var sessions: [AgentSession] = []

    /// What the UI actually shows: expanded if either pinned by a click or
    /// currently hovered.
    var displayedExpanded: Bool { isExpanded || isHovered }
}

struct NowPlaying: Equatable {
    var track: String
    var artist: String
    var album: String
    var trackID: String      // spotify:track:… URI
    var artworkURL: String
    var isPlaying: Bool
}

struct AgentSession: Identifiable, Equatable {
    var id: String           // session id (filename stem)
    var state: String        // "running" | "blocked" | "idle" | "error"
    var label: String
    var updatedAt: Date
}


extension NSImage {
    /// The cover's representative colour, for tinting glass.
    ///
    /// A plain average washes out to grey-brown on most covers, because the
    /// dark background and letterboxing outnumber the coloured subject. So
    /// each pixel of a 16x16 downscale is weighted by its own saturation
    /// (plus a small floor, so an entirely grey cover still yields grey), and
    /// the result is floored to a saturation and brightness a glass tint can
    /// actually be seen at.
    func dominantColor() -> NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }

        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var sum = (r: 0.0, g: 0.0, b: 0.0, weight: 0.0)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255
            let g = Double(pixels[i + 1]) / 255
            let b = Double(pixels[i + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            let weight = 0.15 + (high == 0 ? 0 : (high - low) / high)
            sum.r += r * weight
            sum.g += g * weight
            sum.b += b * weight
            sum.weight += weight
        }
        guard sum.weight > 0 else { return nil }

        let average = NSColor(
            srgbRed: sum.r / sum.weight,
            green: sum.g / sum.weight,
            blue: sum.b / sum.weight,
            alpha: 1
        )
        return NSColor(
            hue: average.hueComponent,
            saturation: min(1, max(0.5, average.saturationComponent)),
            brightness: min(1, max(0.6, average.brightnessComponent)),
            alpha: 1
        )
    }
}
