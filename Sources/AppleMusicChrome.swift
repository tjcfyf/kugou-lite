import SwiftUI
import UIKit

enum AppleMusicTheme {
    static let accent = IOS27.accent
    static let tabUnselected = Theme.text.opacity(0.62)
    static let hairline = Theme.separator
}

/// iOS 27 的底部 chrome：一整块浮在内容上的玻璃 tab bar。
///
/// 和 iOS 26 的“双 tab 胶囊 + 独立搜索圆钮”不同，27 把所有入口收进同一条
/// 玻璃栏；选中项是一枚带折射高光的玻璃片，图标与文字一起变成系统蓝。
/// 栏本身不随滚动收起——滚动时变更形态会让 tab bar 每帧重新测量，
/// 也会让列表内容在手指下发生位移，这正是此前掉帧和“晃”的主要来源。
struct AppleMusicFloatingChrome: View {
    @Binding var tab: Int
    let onOpenPlayer: () -> Void
    @State private var hasTrack = false
    @State private var currentID: String?
    @Namespace private var selectionNamespace

    private let items: [(title: String, icon: String, tag: Int)] = [
        ("主页", "house.fill", 0),
        ("资料库", "square.stack.fill", 1),
        ("搜索", "magnifyingglass", 2)
    ]

    var body: some View {
        VStack(spacing: 8) {
            if hasTrack {
                AppleMusicMiniPlayer(onOpenPlayer: onOpenPlayer)
                    .padding(.horizontal, 14)
                    .transition(.opacity.combined(with: .offset(y: 10)))
            }

            HStack(spacing: 0) {
                ForEach(items, id: \.tag) { item in
                    tabButton(item.title, icon: item.icon, tag: item.tag)
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 64)
            .animation(Motion.tab, value: tab)
            .background(
                ZStack {
                    LiquidGlassBackdrop(cornerRadius: 28, tint: .clear)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 7)
        .animation(Motion.chromeMorph, value: hasTrack)
        .animation(Motion.chromeMorph, value: currentID)
        .onAppear {
            hasTrack = PlayerEngine.shared.current != nil
            currentID = PlayerEngine.shared.current?.id
        }
        .onReceive(PlayerEngine.shared.$current) { song in
            withAnimation(Motion.chromeMorph) {
                hasTrack = song != nil
                currentID = song?.id
            }
        }
    }

    private func tabButton(_ title: String, icon: String, tag: Int) -> some View {
        let selected = tab == tag
        return Button {
            guard tab != tag else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            tab = tag
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? IOS27.accent : AppleMusicTheme.tabUnselected)
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? IOS27.accent : AppleMusicTheme.tabUnselected)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Group {
                    if selected {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.38), lineWidth: 0.6)
                            )
                            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
                            .matchedGeometryEffect(id: "selected-tab", in: selectionNamespace)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(IOS27PressStyle(pressedOpacity: 0.50, pressedScale: 0.98))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// 浮动迷你播放条：同样是一条玻璃，封面 44pt，标题/歌手优先。
struct AppleMusicMiniPlayer: View {
    let onOpenPlayer: () -> Void
    @State private var song: Song?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenPlayer) {
                HStack(spacing: 11) {
                    CoverImage(url: song?.coverURL, size: 44, radius: 8, showsBorder: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song?.SongName ?? "")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        Text(song?.artist ?? "")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(IOS27PressStyle(pressedOpacity: 0.72, pressedScale: 0.98))

            Button { PlayerEngine.shared.toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(width: 36, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IOS27PressStyle(pressedOpacity: 0.45, pressedScale: 0.94))
            .accessibilityLabel(isPlaying ? "暂停" : "播放")

            Button { PlayerEngine.shared.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text.opacity(0.80))
                    .frame(width: 32, height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IOS27PressStyle(pressedOpacity: 0.45, pressedScale: 0.94))
            .accessibilityLabel("下一首")
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .background(
            LiquidGlassBackdrop(cornerRadius: 24, tint: .clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical),
                          abs(horizontal) > 48 else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if horizontal < 0 { PlayerEngine.shared.next() } else { PlayerEngine.shared.previous() }
                }
        )
        .onAppear {
            song = PlayerEngine.shared.current
            isPlaying = PlayerEngine.shared.isPlaying
        }
        .onReceive(PlayerEngine.shared.$current) { updated in
            song = updated
        }
        .onReceive(PlayerEngine.shared.$isPlaying) { playing in
            withAnimation(Motion.quick) { isPlaying = playing }
        }
    }
}

/// 保留这个类型，供旧的（已不再使用的）tab bar 代码编译；视觉已由
/// AppleMusicFloatingChrome 统一，不再单独出现。
struct AppleMusicPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.58 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
