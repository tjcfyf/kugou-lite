import SwiftUI
import UIKit
import Combine

// MARK: - iOS 26 Liquid Glass 视觉基元

enum LiquidGlassMetrics {
    static let barHeight: CGFloat = 58
    static let compactBarHeight: CGFloat = 50
    static let miniHeight: CGFloat = 62
    static let barCorner: CGFloat = 29
    static let miniCorner: CGFloat = 20
    static let bottomMargin: CGFloat = 8
}

/// 真正的磨砂玻璃底：材质 + 折射高光 + 镜面描边 + 接触阴影。
/// 不直接铺白色，避免又变成一层白罩。
struct LiquidGlassBackdrop: View {
    var cornerRadius: CGFloat = 26
    var tint: Color = .clear
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(.ultraThinMaterial)

            // iOS 27 去掉会随设备移动的高光，只留下固定的顶部/底部亮边。
            shape.fill(tint.opacity(colorScheme == .dark ? 0.05 : 0.035))

            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.10 : 0.26), location: 0),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.015 : 0.05), location: 0.42),
                        .init(color: Color.clear, location: 0.70),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.035 : 0.08), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.34 : 0.64), location: 0),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.05 : 0.12), location: 0.42),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.20 : 0.34), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.6
            )
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.12),
                radius: 18, x: 0, y: 8)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 26, tint: Color = .clear) -> some View {
        background(
            LiquidGlassBackdrop(cornerRadius: cornerRadius, tint: tint)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - 动态底栏：滚动时收起，回顶部展开

final class ChromeState: ObservableObject {
    static let shared = ChromeState()

    @Published private(set) var compact = false
    private var lastOffset: CGFloat = 0
    private var hasOffset = false
    private var lastChange = Date.distantPast

    private init() {}

    func update(offset: CGFloat) {
        guard offset.isFinite else { return }
        guard hasOffset else {
            lastOffset = offset
            hasOffset = true
            return
        }
        let delta = offset - lastOffset
        lastOffset = offset

        // 顶部一律展开；向下超过 18pt 收起，向上 18pt 展开。
        if offset >= -8 {
            setCompact(false)
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastChange) > 0.06 else { return }
        if delta <= -18 {
            lastChange = now
            setCompact(true)
        } else if delta >= 18 {
            lastChange = now
            setCompact(false)
        }
    }

    func reset() {
        lastOffset = 0
        hasOffset = false
        setCompact(false)
    }

    private func setCompact(_ value: Bool) {
        guard compact != value else { return }
        compact = value
    }
}

enum ChromeScrollSpace {
    static let name = "chromeScroll"
}

private struct ChromeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChromeScrollTracking: ViewModifier {
    func body(content: Content) -> some View {
        // iOS 27 的 tab bar 固定悬浮，不再随滚动收起。这里保留调用点，
        // 但不再安装 GeometryReader / PreferenceKey：列表滚动时不再每帧
        // 读取坐标并触发一次全局 ObservableObject 更新。
        content
    }
}

extension View {
    /// 兼容旧调用点；iOS 27 中底栏不随滚动变化，因此这是一个零成本修饰。
    func chromeScrollTracking() -> some View {
        self
    }
}

// MARK: - 通用 iOS 26 组件
