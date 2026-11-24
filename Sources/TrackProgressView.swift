import Foundation
import SwiftUI

/// 播放页进度：完全照酷狗概念版的细直线样式。
/// 整体一条细线；已播放部分变亮，未播放部分是低透明度。
/// 副歌/高潮只在同一条线上加粗高亮，不换任何颜色。
struct TrackProgressView: View {
    let progress: Double
    let duration: Double
    let chorusRanges: [ClosedRange<Double>]
    let normalColor: Color

    private var safeDuration: Double { max(duration, 1) }
    private var safeProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        Canvas { context, size in
            let centerY = size.height / 2
            let width = size.width
            let progressX = width * CGFloat(safeProgress)

            // 整体轨道：一条 2pt 细直线。
            var track = Path()
            track.move(to: CGPoint(x: 0, y: centerY))
            track.addLine(to: CGPoint(x: width, y: centerY))
            context.stroke(track,
                           with: .color(normalColor.opacity(0.28)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // 未播放到的高潮段：同色，加粗一点，提前露出高亮位置。
            for range in chorusRanges {
                let startX = x(for: max(range.lowerBound, 0), width: width)
                let endX = x(for: min(range.upperBound, safeDuration), width: width)
                guard endX > startX else { continue }
                let rect = CGRect(x: startX,
                                  y: centerY - 2,
                                  width: max(endX - startX, 2),
                                  height: 4)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(normalColor.opacity(0.52)))
            }

            // 已播放段：同一条线变亮，不改变线宽。
            guard progressX > 1 else { return }
            var played = Path()
            played.move(to: CGPoint(x: 0, y: centerY))
            played.addLine(to: CGPoint(x: progressX, y: centerY))
            context.stroke(played,
                           with: .color(normalColor.opacity(0.96)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // 已播放部分里的高潮段：仍用同色，只加粗到 4pt。
            for range in chorusRanges {
                let startX = x(for: max(range.lowerBound, 0), width: width)
                let endX = min(x(for: min(range.upperBound, safeDuration), width: width), progressX)
                guard endX > startX + 1 else { continue }
                let rect = CGRect(x: startX,
                                  y: centerY - 2,
                                  width: endX - startX,
                                  height: 4)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .color(normalColor.opacity(0.96)))
            }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int(safeProgress * 100))%")
    }

    private func x(for seconds: Double, width: CGFloat) -> CGFloat {
        width * CGFloat(min(max(seconds / safeDuration, 0), 1))
    }
}
