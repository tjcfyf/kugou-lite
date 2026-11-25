import Foundation
import SwiftUI

/// 播放页进度：酷狗概念版同款细直线。
/// 整体 2pt 线；已播放段更亮，高潮段只在同一条线上提高亮度，
/// 不加粗、不换颜色。已播放顶端有一个 2pt 全透明跟随球，
/// 球所在位置把下方进度条整段挖空，不显示线。
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

            // 透明球所在位置把进度条挖空：球直径 2pt，与线宽一致。
            // 用 destinationOut 擦掉 Canvas 已经画出的线，露出页面背景，
            // 所以球经过的地方不显示轨道、不显示已播放线、也不显示高潮高亮。
            let ballCenterX = min(max(progressX, 1), max(width - 1, 1))
            let ballRect = CGRect(x: ballCenterX - 1,
                                  y: centerY - 1,
                                  width: 2,
                                  height: 2)
            context.blendMode = .destinationOut
            context.fill(Path(ellipseIn: ballRect), with: .color(.black))
            context.blendMode = .normal
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
