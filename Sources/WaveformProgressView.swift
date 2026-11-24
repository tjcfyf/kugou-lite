import Foundation
import SwiftUI

/// 播放页进度：整体是一条细直线轨道，只有已经播放的那一段用波浪表示。
/// 不再有圆形进度点；副歌区间在轨道上用一小段暖色底标记，
/// 播到副歌时波浪也切成暖色。
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
            let centerY = size.height / 2
            let width = size.width
            let progressX = width * CGFloat(safeProgress)

            // 1. 整体轨道：一条很细的直线，未播放部分保持克制。
            var track = Path()
            track.move(to: CGPoint(x: 0, y: centerY))
            track.addLine(to: CGPoint(x: width, y: centerY))
            context.stroke(track,
                           with: .color(normalColor.opacity(0.24)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // 2. 副歌区间在未播放的轨道上留一小段暖色底，像分段标记。
            for range in chorusRanges {
                let start = max(range.lowerBound, 0)
                let end = min(range.upperBound, safeDuration)
                guard end > start else { continue }
                let startX = width * CGFloat(start / safeDuration)
                let endX = width * CGFloat(end / safeDuration)
                let rect = CGRect(x: startX,
                                  y: centerY - 2,
                                  width: max(endX - startX, 2),
                                  height: 4)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(chorusColor.opacity(0.26)))
            }

            // 3. 已播放段：用一条真正起伏的波形盖在直线上。
            guard progressX > 1 else { return }
            let seedValue = Self.seedValue(seed)
            var wave = Path()
            let step: CGFloat = 1.5
            let amplitude: CGFloat = 5.2
            var x: CGFloat = 0
            while x <= progressX {
                let y = centerY + Self.waveOffset(x: Double(x),
                                                  width: Double(width),
                                                  seed: seedValue) * amplitude
                if x == 0 {
                    wave.move(to: CGPoint(x: x, y: y))
                } else {
                    wave.addLine(to: CGPoint(x: x, y: y))
                }
                x += step
            }

            // 已播放波形先画一层柔光，再画实线，保证在深色背景上也能看清。
            context.stroke(wave,
                           with: .color(normalColor.opacity(0.16)),
                           style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
            context.stroke(wave,
                           with: .color(normalColor.opacity(0.95)),
                           style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))

            // 4. 副歌部分把同一段波形换成暖色。
            for range in chorusRanges {
                let start = max(range.lowerBound, 0)
                let end = min(range.upperBound, safeDuration)
                let startX = width * CGFloat(start / safeDuration)
                let endX = width * CGFloat(end / safeDuration)
                let clippedEnd = min(endX, progressX)
                guard clippedEnd > startX + 1 else { continue }
                var chorusLayer = context
                chorusLayer.clip(to: Path(CGRect(x: startX,
                                                y: 0,
                                                width: clippedEnd - startX,
                                                height: size.height)))
                chorusLayer.stroke(wave,
                                   with: .color(chorusColor.opacity(0.95)),
                                   style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
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

    /// 连续波形：两条频率不同的正弦叠加，再用歌曲 hash 做固定相位，
    /// 同一首歌每次打开形状一致，不会随播放进度抖动。
    private static func waveOffset(x: Double, width: Double, seed: UInt64) -> Double {
        guard width > 1 else { return 0 }
        let phase = Double(seed % 997) / 997.0 * Double.pi * 2
        let t = x / width * Double.pi * 2
        let a = sin(t * 5.2 + phase) * 0.55
        let b = sin(t * 11.7 - phase * 0.6) * 0.28
        let c = sin(t * 2.1 + phase * 1.3) * 0.17
        return a + b + c
    }
}
