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

            shape.fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.10))

            // 顶部左上到右下的折射高光；只在大面积玻璃上出现。
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.14 : 0.34), location: 0),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.03 : 0.10), location: 0.34),
                        .init(color: Color.clear, location: 0.62),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.05 : 0.12), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.42 : 0.72), location: 0),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.14), location: 0.45),
                        .init(color: Color.white.opacity(colorScheme == .dark ? 0.24 : 0.40), location: 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.14),
                radius: 26, x: 0, y: 14)
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
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ChromeScrollOffsetKey.self,
                        value: proxy.frame(in: .named(ChromeScrollSpace.name)).minY
                    )
                }
            )
            .onPreferenceChange(ChromeScrollOffsetKey.self) { offset in
                ChromeState.shared.update(offset: offset)
            }
    }
}

extension View {
    /// 贴在滚动内容（不是 ScrollView 本身）上，和 `.coordinateSpace(name:)` 配合。
    func chromeScrollTracking() -> some View {
        modifier(ChromeScrollTracking())
    }
}

// MARK: - 通用 iOS 26 组件
