import SwiftUI

/// 播放页进度：用一条会随播放进度点亮的高低波形代替直线 + 圆点。
/// 波形高度由歌曲 hash 决定，同一首歌每次打开形状一致；
/// 副歌区间使用暖色，未播放部分保持低透明度，形成可见的分段。
struct WaveformProgressView: View {
    let progress: Double
    let duration: Double
    let seed: String
    let chorusRanges: [ClosedRange<Double>]
    let normalColor: Color
    let chorusColor: Color

    private var safeDuration: Double { max(duration, 1) }
    private var safeProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        Canvas { context, size in
            let count = max(Int(size.width / 4.2), 30)
            let barWidth: CGFloat = 2.4
            let gap = max((size.width - CGFloat(count) * barWidth) / CGFloat(max(count - 1, 1)), 1)
            let seedValue = Self.seedValue(seed)

            for index in 0..<count {
                let x = CGFloat(index) * (barWidth + gap)
                let height = Self.barHeight(index: index, count: count, seed: seedValue)
                let time = (Double(index) + 0.5) / Double(count) * safeDuration
                let played = time <= safeProgress * safeDuration
                let chorus = chorusRanges.contains { $0.contains(time) }
                let color: Color
                if chorus {
                    color = chorusColor.opacity(played ? 1.0 : 0.38)
                } else {
                    color = normalColor.opacity(played ? 0.92 : 0.22)
                }
                let rect = CGRect(x: x,
                                  y: (size.height - height) / 2,
                                  width: barWidth,
                                  height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.2), with: .color(color))
            }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int(safeProgress * 100))%")
    }

    private static func seedValue(_ seed: String) -> UInt64 {
        var value: UInt64 = 1469598103934665603
        for scalar in seed.unicodeScalars {
            value ^= UInt64(scalar.value)
            value = value &* 1099511628211
        }
        return value
    }

    private static func barHeight(index: Int, count: Int, seed: UInt64) -> CGFloat {
        var value = seed &+ UInt64(index &* 7919)
        value ^= value >> 17
        value = value &* 2654435761
        value ^= value >> 13
        let random = Double(value % 1000) / 1000.0
        let phase = Double(seed % 97) / 97.0 * Double.pi * 2
        let wave = 0.5 + 0.5 * sin(Double(index) / Double(max(count, 1)) * Double.pi * 8 + phase)
        let envelope = 0.45 + 0.55 * wave
        return CGFloat(4.0 + 15.0 * random * envelope)
    }
}
