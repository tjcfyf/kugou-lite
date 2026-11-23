import SwiftUI

/// 播放页转场窗口的当前进度。
///
/// 这个值由 `PlayerPanelFrame` 以 `Animatable` 逐帧写入环境；`NowPlayingView`
/// 读它来同步页面内容的淡入与封面飞行，保证几何窗口、页面透明度、封面位置
/// 三者在同一帧上，不会出现「窗口已经展开、封面还在原地」的脱节。
private struct PlayerPanelProgressKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var playerPanelProgress: CGFloat {
        get { self[PlayerPanelProgressKey.self] }
        set { self[PlayerPanelProgressKey.self] = newValue }
    }
}

/// 从底栏封面圆盘到全屏的矩形 + 圆角裁剪形变。
///
/// 这版直接移植 MD3Music-iOS 的 `PlayerPanelFrame` 几何，不再走
/// `opacity + 15% 位移` 的性能退化路径：
/// - 窗口 `top = origin.top * (1-p)`，`bottom = origin.bottom + (screenH - origin.bottom) * p`
/// - 左右同理从 origin 的 56pt 圆盘铺到全屏；
/// - 外轮廓圆角从圆盘的 28pt 收敛到 0；
/// - 页面始终按整屏尺寸布局、只被窗口裁剪，避免逐帧 reflow；
/// - 底色前 4% 行程淡入，页面内容由 `NowPlayingView` 自己按 20% 行程淡入。
struct PlayerPanelFrame<Content: View>: View, Animatable {
    var progress: CGFloat
    let originRect: CGRect
    let originRadius: CGFloat
    let content: Content

    init(progress: CGFloat,
         originRect: CGRect,
         originRadius: CGFloat = 28,
         @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.originRect = originRect
        self.originRadius = originRadius
        self.content = content()
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let screen = geo.size
            let p = min(max(progress, 0), 1)
            let origin = clampedOrigin(in: screen)
            let rect = PlayerPanelGeometry.rect(progress: p, origin: origin, screen: screen)
            let radius = max(0, originRadius * (1 - p))
            let baseOpacity = min(1, Double(p) / 0.04)

            ZStack(alignment: .topLeading) {
                // 过渡态底色：p=0 完全透明，让底栏真身（含封面）在起手第一帧可见；
                // 4% 行程内变成不透明，之后挡住背后的主页面。
                Theme.background
                    .frame(width: max(screen.width, 1), height: max(screen.height, 1))
                    .offset(x: -rect.minX, y: -rect.minY)
                    .opacity(baseOpacity)

                // 整页按整屏尺寸布局，只被窗口裁剪；页面不压扁、不重新排版。
                content
                    .frame(width: max(screen.width, 1), height: max(screen.height, 1))
                    .environment(\.playerPanelProgress, p)
            }
            .frame(width: max(rect.width, 1), height: max(rect.height, 1), alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .position(x: rect.midX, y: rect.midY)
        }
        .ignoresSafeArea()
    }

    private func clampedOrigin(in screen: CGSize) -> CGRect {
        let w = max(screen.width, 1)
        let h = max(screen.height, 1)
        guard originRect.width > 0, originRect.height > 0 else {
            let side: CGFloat = 56
            return CGRect(x: (w - side) / 2, y: h - side - 8, width: side, height: side)
        }
        let left = min(max(originRect.minX, 0), w)
        let right = min(max(originRect.maxX, left), w)
        let top = min(max(originRect.minY, 0), h)
        let bottom = min(max(originRect.maxY, top), h)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

}
