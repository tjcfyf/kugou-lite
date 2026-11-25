import Foundation
import SwiftUI

/// 播放页进度：酷狗概念版同款细直线。
/// 整体 2pt 线；已播放段更亮，高潮段只在同一条线上提高亮度，
/// 不加粗、不换颜色。已播放顶端有一个 2pt 全透明跟随球，
/// 球所在位置把下方进度条整段断开，不显示线。
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
            let hasBall = safeProgress > 0.002

            // 球心与父视图那个 2pt 透明圆球完全同坐标。
            let ballCenterX = min(max(progressX, 1), max(width - 1, 1))
            let gapStart = max(ballCenterX - 1, 0)
            let gapEnd = min(ballCenterX + 1, width)

            // 轨道整段：低亮度细线。球的位置直接断开，不靠擦除。
            if hasBall {
                if gapStart > 0 {
                    drawSegment(context: context, from: 0, to: gapStart,
                                y: centerY, color: normalColor.opacity(0.24), cap: .butt)
                }
                if gapEnd < width {
                    drawSegment(context: context, from: gapEnd, to: width,
                                y: centerY, color: normalColor.opacity(0.24), cap: .butt)
                }
            } else {
                drawSegment(context: context, from: 0, to: width,
                            y: centerY, color: normalColor.opacity(0.24), cap: .round)
            }

            // 高潮段在未播放区域也只是同一条线变亮，不加粗。
            for range in chorusRanges {
                let startX = x(for: max(range.lowerBound, 0), width: width)
                let endX = x(for: min(range.upperBound, safeDuration), width: width)
                guard endX > startX + 1 else { continue }
                if hasBall {
                    drawOutsideGap(context: context, from: startX, to: endX,
                                   y: centerY, color: normalColor.opacity(0.60),
                                   gapStart: gapStart, gapEnd: gapEnd)
                } else {
                    drawSegment(context: context, from: startX, to: endX,
                                y: centerY, color: normalColor.opacity(0.60), cap: .round)
                }
            }

            // 已播放段：整段提亮。到球边缘就停，不在球下面继续画。
            guard progressX > 1, hasBall else { return }
            if gapStart > 0 {
                drawSegment(context: context, from: 0, to: gapStart,
                            y: centerY, color: normalColor.opacity(0.94), cap: .butt)
            }

            // 已播放到的高潮段：再亮一点，线宽完全不变。
            for range in chorusRanges {
                let startX = x(for: max(range.lowerBound, 0), width: width)
                let endX = min(x(for: min(range.upperBound, safeDuration), width: width), gapStart)
                guard endX > startX + 1 else { continue }
                drawSegment(context: context, from: startX, to: endX,
                            y: centerY, color: normalColor.opacity(1.0), cap: .butt)
            }
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(Int(safeProgress * 100))%")
    }

    private func drawOutsideGap(context: GraphicsContext,
                                from startX: CGFloat,
                                to endX: CGFloat,
                                y: CGFloat,
                                color: Color,
                                gapStart: CGFloat,
                                gapEnd: CGFloat) {
        guard endX > startX else { return }
        if endX <= gapStart || startX >= gapEnd {
            drawSegment(context: context, from: startX, to: endX,
                        y: y, color: color, cap: .round)
            return
        }
        if startX < gapStart {
            drawSegment(context: context, from: startX, to: gapStart,
                        y: y, color: color, cap: .butt)
        }
        if endX > gapEnd {
            drawSegment(context: context, from: gapEnd, to: endX,
                        y: y, color: color, cap: .butt)
        }
    }

    private func drawSegment(context: GraphicsContext,
                             from startX: CGFloat,
                             to endX: CGFloat,
                             y: CGFloat,
                             color: Color,
                             cap: CGLineCap) {
        guard endX > startX + 0.01 else { return }
        var path = Path()
        path.move(to: CGPoint(x: startX, y: y))
        path.addLine(to: CGPoint(x: endX, y: y))
        context.stroke(path,
                       with: .color(color),
                       style: StrokeStyle(lineWidth: 2, lineCap: cap))
    }

    private func x(for seconds: Double, width: CGFloat) -> CGFloat {
        width * CGFloat(min(max(seconds / safeDuration, 0), 1))
    }
}
