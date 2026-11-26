import SwiftUI
import UIKit

/// Apple Music / iOS 27.2 视觉规范。
///
/// 2026 年 10 月 Apple Music 完成去红色品牌更新：界面回到纸面般的黑白，
/// 只有当前选中的 tab 和少量可操作状态使用 system blue。材质只出现在
/// 真正浮在内容之上的 chrome（tab bar、迷你播放器、关闭按钮、搜索框），
/// 内容区回到无卡片、细分隔线的列表，减少离屏合成和滚动时的重绘。
enum IOS27 {
    static let accent = Color("Accent")
    static let blue = Color("Accent")

    static let pagePadding: CGFloat = 20
    static let rowHeight: CGFloat = 56
    static let sectionSpacing: CGFloat = 28
    static let cardCorner: CGFloat = 18

    static let rowTitle = Font.system(size: 17, weight: .semibold)
    static let rowSubtitle = Font.system(size: 14, weight: .regular)
    static let sectionTitle = Font.system(size: 22, weight: .bold)
    static let groupTitle = Font.system(size: 14, weight: .semibold)
    static let caption = Font.system(size: 13, weight: .medium)

    /// 大标题使用更紧的字距；正文不人为加字距。
    static let displayTracking: CGFloat = -0.45
    static let sectionTracking: CGFloat = -0.25

    static let hairline: CGFloat = 0.5
}

/// Apple Music 的按压反馈：按下立即变淡，抬起用短 ease-out 回来。
/// 只动 opacity / scale，不触发布局；reduce motion 时取消缩放。
struct IOS27PressStyle: ButtonStyle {
    var pressedOpacity: Double = 0.55
    var pressedScale: CGFloat = 0.97
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 列表行：只在按下时铺一层极淡的系统灰，不缩放整行。
/// 这是 Apple Music 资料库、搜索结果和歌单曲目共用的反馈。
struct IOS27RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.055 : 0))
            )
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct IOS27SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var showsChevron: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(IOS27.sectionTitle)
                .tracking(IOS27.sectionTracking)
                .foregroundColor(Theme.text)
            if let subtitle {
                Text(subtitle)
                    .font(IOS27.caption)
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(IOS27.accent)
                }
                .buttonStyle(IOS27PressStyle(pressedOpacity: 0.45, pressedScale: 1))
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, IOS27.pagePadding)
        .padding(.top, IOS27.sectionSpacing)
        .padding(.bottom, 10)
    }
}

/// 无卡片的分组容器：内容平铺在页面上，用 0.5pt 分隔线组织层级。
/// 这是 iOS 27 资料库与设置页的主结构，避免每块内容都套一层磨砂。
struct IOS27PlainGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Theme.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.separator.opacity(0.55))
                .frame(height: IOS27.hairline)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.separator.opacity(0.55))
                .frame(height: IOS27.hairline)
        }
    }
}

struct IOS27RowDivider: View {
    var leading: CGFloat = 66

    var body: some View {
        Rectangle()
            .fill(Theme.separator.opacity(0.55))
            .frame(height: IOS27.hairline)
            .padding(.leading, leading)
    }
}

struct IOS27Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Theme.tertiaryText)
    }
}

/// 索引行里的单色线性图标；iOS 27.2 已经把资料库的彩色小图标全部去色。
struct IOS27IndexIcon: View {
    let systemName: String
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .medium))
            .foregroundColor(Theme.text)
            .frame(width: 28, height: 28)
    }
}

/// 浮在封面/背景上的玻璃圆钮。只在顶栏使用，尺寸固定 44pt。
struct IOS27GlassCircleButton: View {
    let systemName: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 0.6))
        }
        .buttonStyle(IOS27PressStyle())
    }
}

/// 详情页顶部的轻量关闭/返回按钮：圆形玻璃，不抢封面。
struct IOS27DetailCloseButton: View {
    var icon: String = "xmark"
    let action: () -> Void

    var body: some View {
        IOS27GlassCircleButton(systemName: icon, action: action)
            .accessibilityLabel("关闭")
    }
}

/// 详情页的磨砂关闭钮：放在安全区右上角，不随内容滚动。
struct IOS27FloatingClose: ViewModifier {
    let action: () -> Void
    var leading: Bool = false

    func body(content: Content) -> some View {
        content.overlay(alignment: leading ? .topLeading : .topTrailing) {
            IOS27DetailCloseButton(action: action)
                .padding(.top, 10)
                .padding(.horizontal, 16)
        }
    }
}

extension View {
    func ios27FloatingClose(_ action: @escaping () -> Void, leading: Bool = false) -> some View {
        modifier(IOS27FloatingClose(action: action, leading: leading))
    }
}

/// 播放页底部操作图标：线性、低对比，选中态使用蓝色。
struct IOS27PlayerToolButton: View {
    let systemName: String
    var active: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(active ? IOS27.accent : Theme.text.opacity(disabled ? 0.28 : 0.78))
                .frame(width: 52, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(IOS27PressStyle(pressedOpacity: 0.42, pressedScale: 0.94))
        .disabled(disabled)
    }
}
