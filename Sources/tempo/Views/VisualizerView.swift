import SwiftUI

// Placeholder — replaced with playback-synced animated bars (decision 004).
struct VisualizerView: View {
    var isPlaying: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white)
                    .frame(width: 3, height: height)
            }
        }
    }

    private let barHeights: [CGFloat] = [8, 14, 20, 14, 8]
}
