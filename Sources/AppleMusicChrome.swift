import SwiftUI
import UIKit

enum AppleMusicTheme {
    /// Apple Music 的选中态/链接红；播放控制仍然用白色。
    static let accent = Color(red: 0.98, green: 0.20, blue: 0.28)
    static let tabUnselected = Theme.text.opacity(0.62)
    static let hairline = Theme.text.opacity(0.14)
}

/// Apple Music 底部结构：全宽磨砂 tab bar + 上方的迷你播放条。
/// 不再使用原来的悬浮胶囊，避免播放页收起时出现「首页上飘一张封面」。
struct AppleMusicBottomBar: View {
    @Binding var tab: Int
    let onOpenPlayer: () -> Void
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if player.current != nil {
                AppleMusicMiniPlayer(onOpenPlayer: onOpenPlayer)
                Rectangle()
                    .fill(AppleMusicTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)
            }

            HStack(spacing: 0) {
                tabButton(title: "现在就听", icon: "play.rectangle", tag: 0)
                tabButton(title: "资料库", icon: "music.note.list", tag: 1)
                tabButton(title: "搜索", icon: "magnifyingglass", tag: 2)
            }
            .frame(height: 54)
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.02))
                        .allowsHitTesting(false)
                )
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppleMusicTheme.hairline)
                .frame(height: 0.5)
        }
    }

    private func tabButton(title: String, icon: String, tag: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // 底栏切 tab 不要包 withAnimation：首页和搜索是两棵独立视图树，
            // 0.2 秒的透明度过渡会让人先看到「现在就听」再看到搜索页。
            tab = tag
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundColor(tab == tag ? AppleMusicTheme.accent : AppleMusicTheme.tabUnselected)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(tab == tag ? AppleMusicTheme.accent : AppleMusicTheme.tabUnselected)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(Motion.tab, value: tab == tag)
        }
        .buttonStyle(AppleMusicPressStyle())
        .accessibilityLabel(title)
    }
}

/// Apple Music 全宽迷你播放条：封面 + 歌名/歌手 + 播放键。
/// 点击除播放键外的区域打开播放页。
struct AppleMusicMiniPlayer: View {
    let onOpenPlayer: () -> Void
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onOpenPlayer) {
                HStack(spacing: 11) {
                    CoverImage(url: player.current?.coverURL, size: 44, radius: 6)
                        .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.current?.SongName ?? "")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                        Text(player.current?.artist ?? "")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(AppleMusicPressStyle())

            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppleMusicPressStyle())
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AppleMusicPressStyle())
            .accessibilityLabel("下一首")
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
    }
}

struct AppleMusicPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}
