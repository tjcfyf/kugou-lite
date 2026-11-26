import SwiftUI
import UIKit

enum AppleMusicTheme {
    /// Apple Music 的选中态/链接红。
    static let accent = Theme.accent
    static let tabUnselected = Theme.text.opacity(0.58)
    static let hairline = Theme.text.opacity(0.12)
}

/// iOS 26 的浮动底栏：左侧两枚主 tab 的液态玻璃胶囊，右侧独立搜索玻璃圆钮。
/// 向下滚动时胶囊收起成纯图标，回到顶部再展开；迷你播放器浮在整条底栏上方。
struct AppleMusicFloatingChrome: View {
    @Binding var tab: Int
    let onOpenPlayer: () -> Void
    @ObservedObject private var chrome = ChromeState.shared
    @Namespace private var selectionNamespace
    @State private var hasTrack = false
    @State private var currentID: String?

    var body: some View {
        VStack(spacing: 10) {
            if hasTrack {
                AppleMusicMiniPlayer(onOpenPlayer: onOpenPlayer)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.horizontal, 2)
            }

            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    barButton(title: "现在就听", icon: "house.fill", tag: 0)
                    barButton(title: "资料库", icon: "square.stack.fill", tag: 1)
                }
                .padding(.horizontal, 4)
                .frame(width: chrome.compact ? 116 : 200,
                       height: chrome.compact ? LiquidGlassMetrics.compactBarHeight : LiquidGlassMetrics.barHeight)
                .liquidGlass(cornerRadius: chrome.compact ? 25 : LiquidGlassMetrics.barCorner)
                .animation(Motion.chromeMorph, value: chrome.compact)
                .animation(Motion.quick, value: tab)

                searchButton
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, LiquidGlassMetrics.bottomMargin)
        .animation(Motion.chromeMorph, value: chrome.compact)
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

    private func barButton(title: String, icon: String, tag: Int) -> some View {
        let selected = tab == tag
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            tab = tag
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(selected ? AppleMusicTheme.accent : AppleMusicTheme.tabUnselected)
                    .frame(height: 24)
                if !chrome.compact {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(selected ? AppleMusicTheme.accent : AppleMusicTheme.tabUnselected)
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .frame(width: chrome.compact ? 52 : 94,
                   height: chrome.compact ? LiquidGlassMetrics.compactBarHeight : LiquidGlassMetrics.barHeight)
            .background(
                Group {
                    if selected {
                        Capsule()
                            .fill(AppleMusicTheme.accent.opacity(0.10))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 4)
                            .matchedGeometryEffect(id: "selected-tab", in: selectionNamespace)
                    }
                },
                alignment: .center
            )
            .contentShape(Capsule())
        }
        .buttonStyle(AppleMusicPressStyle())
        .accessibilityLabel(title)
    }

    private var searchButton: some View {
        let selected = tab == 2
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            tab = 2
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(selected ? AppleMusicTheme.accent : Theme.text.opacity(0.82))
                .frame(width: chrome.compact ? LiquidGlassMetrics.compactBarHeight : LiquidGlassMetrics.barHeight,
                       height: chrome.compact ? LiquidGlassMetrics.compactBarHeight : LiquidGlassMetrics.barHeight)
                .contentShape(Circle())
        }
        .buttonStyle(AppleMusicPressStyle())
        .background(
            LiquidGlassBackdrop(
                cornerRadius: chrome.compact ? 25 : LiquidGlassMetrics.barCorner,
                tint: selected ? AppleMusicTheme.accent.opacity(0.18) : .clear
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: chrome.compact ? 25 : LiquidGlassMetrics.barCorner,
                                    style: .continuous))
        .animation(Motion.chromeMorph, value: chrome.compact)
        .accessibilityLabel("搜索")
    }
}

/// 浮动迷你播放条：液态玻璃胶囊，可左右轻扫切上一首/下一首。
struct AppleMusicMiniPlayer: View {
    let onOpenPlayer: () -> Void
    @State private var song: Song?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenPlayer) {
                HStack(spacing: 11) {
                    CoverImage(url: song?.coverURL, size: 42, radius: 9)
                        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song?.SongName ?? "")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        Text(song?.artist ?? "")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(AppleMusicPressStyle())

            Button { PlayerEngine.shared.toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppleMusicPressStyle())
            .accessibilityLabel(isPlaying ? "暂停" : "播放")

            Button { PlayerEngine.shared.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text.opacity(0.86))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppleMusicPressStyle())
            .accessibilityLabel("下一首")
        }
        .padding(.horizontal, 12)
        .frame(height: LiquidGlassMetrics.miniHeight)
        .liquidGlass(cornerRadius: LiquidGlassMetrics.miniCorner)
        .contentShape(RoundedRectangle(cornerRadius: LiquidGlassMetrics.miniCorner, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height),
                          abs(horizontal) > 42 else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(Motion.quick) {
                        if horizontal < 0 { PlayerEngine.shared.next() } else { PlayerEngine.shared.previous() }
                    }
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

struct AppleMusicPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.58 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}
