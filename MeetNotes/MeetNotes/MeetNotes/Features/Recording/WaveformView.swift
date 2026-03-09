import SwiftUI

struct WaveformView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animating = false

    private let barCount = 3
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 1
    private let dotSize: CGFloat = 4
    private let minBarHeight: CGFloat = 3
    private let maxBarHeight: CGFloat = 10

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.primary)
                    .frame(width: barWidth, height: barHeight(for: index))
            }
            Circle()
                .fill(Color.recordingRed)
                .frame(width: dotSize, height: dotSize)
        }
        .frame(height: maxBarHeight)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
            value: animating
        )
        .onAppear {
            if !reduceMotion {
                animating = true
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard !reduceMotion else { return 8 }
        let heights: [[CGFloat]] = [
            [minBarHeight, maxBarHeight],
            [maxBarHeight, minBarHeight],
            [minBarHeight + 2, maxBarHeight - 1]
        ]
        let pair = heights[index]
        return animating ? pair[1] : pair[0]
    }
}
