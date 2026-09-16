import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The file shelf inside the expanded panel (decision 051).
///
/// Two states, never both: while a drag is heading for the notch it is a drop
/// well; the rest of the time it is the row of what the shelf is holding, each
/// item draggable back out. An empty shelf with no drag in flight draws
/// nothing at all — the panel must not carry a permanently empty box.
struct ShelfView: View {
    @ObservedObject var shelf: ShelfService
    /// True while a file drag is close enough that the panel opened for it.
    let isDropTargeting: Bool

    @State private var hoveredID: UUID?

    private static let wellHeight: CGFloat = 54
    private static let itemSide: CGFloat = 52

    var body: some View {
        if isDropTargeting {
            dropWell
        } else if !shelf.items.isEmpty {
            itemRow
        }
    }

    // MARK: - Drop well

    private var dropWell: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                Color.accentColor.opacity(0.9),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .frame(height: Self.wellHeight)
            .overlay {
                HStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down.fill")
                    Text(shelf.items.isEmpty ? "Drop to keep here" : "Add to shelf")
                }
                .font(NotchType.control.weight(.medium))
                .foregroundStyle(.secondary)
            }
            // The well is the affordance; the actual drop is accepted by the
            // whole panel in ContentView, so a drop that lands slightly off
            // the well still works.
            .transition(.opacity)
    }

    // MARK: - Items

    private var itemRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shelf.items) { item in
                    itemChip(item)
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: Self.itemSide + 16)
    }

    private func itemChip(_ item: ShelfItem) -> some View {
        let isHovered = hoveredID == item.id
        return VStack(spacing: 3) {
            Image(systemName: item.symbolName)
                .font(.title3)
                .foregroundStyle(.primary)
            Text(item.name)
                // Was 9pt — below every macOS text style and under Apple's own
                // legibility floor. `.caption2` is the smallest the platform
                // ships (10pt) and it scales with the user's setting.
                .font(NotchType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: Self.itemSide, height: Self.itemSide)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.16 : 0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityHint("Drag out to copy, or use the shortcut menu to reveal or remove")
        // Dragging the chip hands the *stored copy* to the receiving app, so
        // the shelf keeps working after the original is moved or deleted.
        .onDrag { shelf.itemProvider(for: item) }
        .overlay(alignment: .topTrailing) {
            Button {
                shelf.remove(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(NotchType.control)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.primary.opacity(0.85), Color.primary.opacity(0.25))
                    // The glyph is 12pt; the target it sits in is not.
                    // A 12pt close button on a 52pt chip is a dart throw,
                    // and missing it drags the file out instead.
                    .frame(width: NotchMetrics.compactHitTarget,
                           height: NotchMetrics.compactHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .accessibilityLabel("Remove \(item.name) from the shelf")
            .help("Remove from shelf")
            // The button stays *inside* the chip. Offsetting it out of the
            // chip put most of its hit area outside the region `.onHover`
            // tracks, so reaching for it ended hover, which removed the
            // button, which restored hover — a flicker loop at pointer speed.
            // Kept mounted and faded instead, so hit-testing never churns.
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        // Hover is tracked on the whole chip *including* the button overlay.
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in
            if hovering {
                hoveredID = item.id
            } else if hoveredID == item.id {
                // Only clear our own id: leaving one chip for its neighbour
                // can deliver this after the neighbour's enter.
                hoveredID = nil
            }
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contextMenu {
            Button("Reveal in Finder") { shelf.revealInFinder(item) }
            Button("Remove") { shelf.remove(item) }
        }
        .help(item.name)
    }
}
