import SwiftUI

/// Output device chips + volume slider in the expanded panel (decision 050).
///
/// Deliberately not a menu (UI Principle #3): every output device is a visible
/// chip, so switching is one click rather than open-menu-then-pick. The chips
/// wrap onto as many rows as they need rather than scrolling sideways — a
/// horizontally scrolled row hid every device past the panel's ~360pt of
/// content width, so connecting a fourth output (a speaker, AirPods) parked it
/// off the right edge where it read as "the device never showed up"
/// (decision 060).
struct AudioOutputView: View {
    @ObservedObject var audio: AudioOutputService

    var body: some View {
        VStack(alignment: .leading, spacing: NotchMetrics.rowSpacing) {
            volumeRow
            if audio.devices.count > 1 {
                deviceRow
            }
        }
    }

    // MARK: - Volume

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Button {
                audio.setMuted(!audio.isMuted)
            } label: {
                Image(systemName: muteSymbol)
                    .font(NotchType.control)
                    // The glyph stays 12pt; the *target* is a full 28pt
                    // square. A 16x16 button is under half the area every
                    // other control in this panel offers, and it is the one
                    // control here whose miss is audible.
                    .frame(width: NotchMetrics.hitTarget, height: NotchMetrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(audio.isMuted ? "Unmute" : "Mute")
            .help(audio.isMuted ? "Unmute" : "Mute")

            if let volume = audio.volume {
                Slider(
                    value: Binding(
                        get: { Double(volume) },
                        // Dragging the slider on a muted device would otherwise
                        // change nothing audible: raising the volume is an
                        // unmute gesture, and the HAL does not treat it as one.
                        set: { newValue in
                            audio.setVolume(Float(newValue))
                            if audio.isMuted && newValue > 0 { audio.setMuted(false) }
                        }
                    ),
                    in: 0...1
                )
                .controlSize(.mini)
                .accessibilityLabel("Volume")
            } else {
                // Some digital outputs (HDMI here) answer
                // kAudioHardwareUnknownPropertyError for volume — the device
                // owns its own level. Say so rather than showing a dead slider
                // at zero (UI Principle #4).
                Text("Volume controlled on the device")
                    .font(NotchType.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var muteSymbol: String {
        if audio.isMuted { return "speaker.slash.fill" }
        guard let volume = audio.volume else { return "speaker.wave.2" }
        switch volume {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    // MARK: - Devices

    private var deviceRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(audio.devices) { device in
                deviceChip(device)
            }
        }
    }

    private func deviceChip(_ device: AudioOutputDevice) -> some View {
        let isCurrent = device.id == audio.currentDeviceID
        return Button {
            audio.select(device)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: device.symbolName)
                    .font(NotchType.caption)
                Text(device.name)
                    .font(NotchType.caption.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // A single chip must never be wider than the row it wraps
                    // into, or it would be clipped with no way to reach it.
                    // Long names ("Ditoo-Plus-audio-cherry") truncate; the
                    // full name stays available in the tooltip below.
                    .frame(maxWidth: 132, alignment: .leading)
            }
            .padding(.horizontal, 10)
            // 24pt tall, not the old ~19: a full 28pt square each would cost
            // the panel a third of a row per line of chips, and these wrap.
            .frame(minHeight: NotchMetrics.compactHitTarget)
            .background(
                Capsule().fill(Color.primary.opacity(isCurrent ? 0.18 : 0.07))
            )
            // The selected chip was told apart by a semibold weight and a
            // slightly denser fill — a 0.18-vs-0.07 alpha step that is hard to
            // see at a glance and gone entirely in greyscale. An outline is a
            // shape difference, so it survives both.
            .overlay(
                Capsule().strokeBorder(
                    Color.primary.opacity(isCurrent ? 0.45 : 0),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isCurrent ? .primary : .secondary)
        .accessibilityLabel(device.name)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .help(isCurrent ? "\(device.name) (current output)" : "Play through \(device.name)")
    }
}

/// Left-to-right wrapping row. SwiftUI has no built-in flow container, and the
/// alternatives here are worse: an `HStack` clips, and a horizontal `ScrollView`
/// hides devices behind a gesture the non-activating notch panel makes awkward.
/// Sizes every chip at its ideal width and starts a new row when the next one
/// would cross the container's trailing edge; the panel measures its own height
/// from the content, so extra rows simply make the panel taller.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var total = CGSize.zero
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                total.width = max(total.width, rowWidth)
                total.height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        total.width = max(total.width, rowWidth)
        total.height += rowHeight
        return total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
