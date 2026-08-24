import SwiftUI

/// Output device row + volume slider in the expanded panel (decision 050).
///
/// Deliberately not a menu (UI Principle #3): every output device is a visible
/// chip, so switching is one click rather than open-menu-then-pick. Machines
/// here have two or three outputs, which fits the panel width; the row scrolls
/// if a dock or several displays push it wider.
struct AudioOutputView: View {
    @ObservedObject var audio: AudioOutputService

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
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
                    .font(.system(size: 12))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
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
            } else {
                // Some digital outputs (HDMI here) answer
                // kAudioHardwareUnknownPropertyError for volume — the device
                // owns its own level. Say so rather than showing a dead slider
                // at zero (UI Principle #4).
                Text("Volume controlled on the device")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(audio.devices) { device in
                    deviceChip(device)
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: 26)
    }

    private func deviceChip(_ device: AudioOutputDevice) -> some View {
        let isCurrent = device.id == audio.currentDeviceID
        return Button {
            audio.select(device)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: device.symbolName)
                    .font(.system(size: 10))
                Text(device.name)
                    .font(.system(size: 10, weight: isCurrent ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.primary.opacity(isCurrent ? 0.18 : 0.07))
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isCurrent ? .primary : .secondary)
        .help(device.name)
    }
}
