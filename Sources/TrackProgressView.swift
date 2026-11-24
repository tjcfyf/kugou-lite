import Foundation
import SwiftUI

/// 播放页进度：酷狗概念版同款细直线。
/// 整体 2pt 线；已播放段更亮，高潮段只在同一条线上提高亮度，
/// 不加粗、不换颜色、不画圆点。
struct TrackProgressView: View, Animatable {
    var progress: Double
    let duration: Double
    let chorusRanges: [ClosedRange<Double>]
    let normalColor: Color

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var safeDuration: Double { max(duration, 1) }
    private var safeProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        Canvas { context, size in
            let centerY = size.height / 2
            let width = size.width
            let progressX = width * CGFloat(safeProgress)

            // 轨道整段：低亮度细线。
            drawLine(context: context,
                     from: 0,
                     to: width,
                     y: centerY,
                     color: normalColor.opacity(0.24))

            // 高潮段在未播放区域也只是同一条线变亮，不加粗。
            for range in chorusRanges {
                let startX = x(for: max(range.lowerBound, 0), width: width)
                let endX = x(for: min(range.upperBound, safeDuration), width: width)
                guard endX > startX + 1 else { continue }
                drawLine(context: context,
                         from: startX,
                         to: endX,
                         y: centerY,
                         color: normalColor.opacity(0.60))
            }

            // 已播放段：整段提亮。
            guard progressX > 1 else { return }
            drawLine(context: context,
                     from: 0,
                     to: progressX,
                     y: centerY,
                     color: normalColor.opacity(0.94))

            // 已播放到的高潮段：再亮一点，线宽完全不变。
            for range in chorusRanges {
                let startX = x(for: max(range.lowerBound, 0), width: width)
                let endX = min(x(for: min(range.upperBound, safeDuration), width: width), progressX)
                guard endX > startX + 1 else { continue }
                drawLine(context: context,
                         from: startX,
                         to: endX,
                         y: centerY,
                         color: normalColor.opacity(1.0))
            }
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int(safeProgress * 100))%")
    }

    private func drawLine(context: GraphicsContext,
                          from startX: CGFloat,
                          to endX: CGFloat,
                          y: CGFloat,
                          color: Color) {
        guard endX > startX else { return }
        var path = Path()
        path.move(to: CGPoint(x: startX, y: y))
        path.addLine(to: CGPoint(x: endX, y: y))
        context.stroke(path,
                       with: .color(color),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private func x(for seconds: Double, width: CGFloat) -> CGFloat {
        width * CGFloat(min(max(seconds / safeDuration, 0), 1))
    }
}
