import SwiftUI
import UIKit

enum Theme {
    static let background = Color("Background")
    static let card = Color("Card")
    static let accent = Color("Accent")
    static let text = Color("TextPrimary")
    static let secondaryText = Color("TextSecondary")
    static let tertiaryText = Color("TextTertiary")
    static let chip = Color("Chip")
    static let separator = Color("Separator")
}

/// 全 App 统一的柔和渐变背景，浅色/深色各一套。
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [Theme.accent.opacity(colorScheme == .dark ? 0.16 : 0.13), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 620
            )
            RadialGradient(
                colors: [Color(red: 0.32, green: 0.55, blue: 0.86).opacity(colorScheme == .dark ? 0.12 : 0.14), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 560
            )
        }
        .ignoresSafeArea()
    }
}

private final class CoverCache {
    static let shared = CoverCache()
    let cache = NSCache<NSString, UIImage>()
}

struct CoverImage: View {
    let url: URL?
    var size: CGFloat = 44
    var radius: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: url?.absoluteString) {
            image = nil
            guard let url = url else { return }
            let key = url.absoluteString as NSString
            if let cached = CoverCache.shared.cache.object(forKey: key) {
                image = cached
                return
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let decoded = UIImage(data: data) else { return }
            CoverCache.shared.cache.setObject(decoded, forKey: key)
            image = decoded
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.card, Color.white.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.32, weight: .medium))
                .foregroundColor(Theme.tertiaryText)
        }
    }
}


struct SongActionsSheet: View {
    let song: Song
    @EnvironmentObject private var player: PlayerEngine
    @ObservedObject private var library = LibraryStore.shared
    @Environment(\.dismiss) private var dismiss

    private var isFavorite: Bool {
        library.isFavorite(song)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                CoverImage(url: song.coverURL, size: 52, radius: 10)
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.SongName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
                Spacer()
            }
            .padding(16)

            Divider().background(Theme.separator)

            actionRow(title: "下一首播放", icon: "arrow.up.forward") {
                player.playNext(song)
                dismiss()
            }
            actionRow(title: isFavorite ? "取消我喜欢" : "我喜欢", icon: isFavorite ? "heart.fill" : "heart") {
                dismiss()
                Task {
                    let added = await library.toggleFavorite(song)
                    if let added = added {
                        player.showToast(added ? "已加入我喜欢" : "已从我喜欢移除")
                    } else {
                        player.showToast(library.favoritesMessage)
                    }
                }
            }
            actionRow(title: "加入播放列表末尾", icon: "text.badge.plus") {
                player.appendToQueue(song)
                dismiss()
            }

            Button("取消") { dismiss() }
                .font(.system(size: 15))
                .foregroundColor(Theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.chip)
                .cornerRadius(12)
                .padding(16)

            Spacer(minLength: 0)
        }
        .background(AppBackground())
    }

    private func actionRow(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 歌曲右侧三个点的可点菜单；用于歌单/我喜欢等自定义行，避免点三个点变成播放。
struct SongMoreMenu: View {
    let song: Song
    @EnvironmentObject private var player: PlayerEngine
    @ObservedObject private var library = LibraryStore.shared

    private var isFavorite: Bool {
        library.isFavorite(song)
    }

    var body: some View {
        Menu {
            Button {
                player.playNext(song)
            } label: {
                Label("下一首播放", systemImage: "arrow.up.forward")
            }
            Button {
                player.appendToQueue(song)
            } label: {
                Label("加入播放列表", systemImage: "text.badge.plus")
            }
            Button {
                Task {
                    let added = await library.toggleFavorite(song)
                    if let added = added {
                        player.showToast(added ? "已加入我喜欢" : "已从我喜欢移除")
                    } else {
                        player.showToast(library.favoritesMessage)
                    }
                }
            } label: {
                Label(isFavorite ? "取消我喜欢" : "我喜欢",
                      systemImage: isFavorite ? "heart.fill" : "heart")
            }
            Button {
                UIPasteboard.general.string = "\(song.SongName) - \(song.artist)"
                player.showToast("已复制歌曲信息")
            } label: {
                Label("复制歌名和歌手", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.tertiaryText)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 统一的“整行播放 + 右侧独立菜单”行，避免三个点被整行按钮吞掉。
struct SongRowWithMenu: View {
    let song: Song
    var index: Int? = nil
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    if let index = index {
                        Text("\(index)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                            .frame(width: 22, alignment: .leading)
                    }
                    SongRow(song: song, showsMore: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            SongMoreMenu(song: song)
        }
    }
}

/// 悬浮底栏：发现 / 当前歌曲专辑图 / 我的。
struct FloatingTabBar: View {
    @Binding var tab: Int
    let onOpenPlayer: () -> Void

    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        HStack(spacing: 0) {
            tabButton(title: "发现", icon: "sparkles", tag: 0)

            Spacer(minLength: 0)

            albumButton

            Spacer(minLength: 0)

            tabButton(title: "我的", icon: "person.crop.circle", tag: 1)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 340)
        .frame(height: 66)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Theme.separator.opacity(0.5), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func tabButton(title: String, icon: String, tag: Int) -> some View {
        Button {
            tab = tag
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(tab == tag ? Theme.accent : Theme.secondaryText)
            .frame(width: 76, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var albumButton: some View {
        Button {
            guard player.current != nil else {
                player.showToast("先选一首歌")
                return
            }
            onOpenPlayer()
        } label: {
            ZStack {
                if let song = player.current, let url = song.coverURL {
                    CoverImage(url: url, size: 46, radius: 23)
                } else {
                    RotatingAlbumPlaceholder(size: 46)
                }

                if player.current != nil, player.duration > 0 {
                    Circle()
                        .trim(from: 0, to: min(max(player.currentTime / player.duration, 0), 1))
                        .stroke(Theme.accent, lineWidth: 2)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 51, height: 51)
                }
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("当前播放")
    }
}

/// 没有歌曲封面时的通用圆形封面，缓慢旋转。
struct RotatingAlbumPlaceholder: View {
    let size: CGFloat
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Theme.card,
                            Theme.accent.opacity(0.42),
                            Theme.card,
                            Theme.accent.opacity(0.16),
                            Theme.card
                        ]),
                        center: .center
                    )
                )
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            Image(systemName: "music.note")
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundColor(Theme.text.opacity(0.72))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(.linear(duration: 7).repeatForever(autoreverses: false), value: spinning)
        .onAppear {
            spinning = true
        }
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.82))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct SongRow: View {
    let song: Song
    var showsMore: Bool = false
    @EnvironmentObject private var player: PlayerEngine
    @ObservedObject private var library = LibraryStore.shared

    private var isFavorite: Bool {
        library.isFavorite(song)
    }

    var body: some View {
        HStack(spacing: 14) {
            CoverImage(url: song.coverURL, size: 54, radius: 14)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(song.SongName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    if song.needsPurchase {
                        Text("VIP")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Theme.accent.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
                Text(song.artist)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.accent)
            }
            if showsMore {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.tertiaryText)
                    .frame(width: 24, height: 30)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                player.playNext(song)
            } label: {
                Label("下一首播放", systemImage: "arrow.up.forward")
            }
            Button {
                player.appendToQueue(song)
            } label: {
                Label("加入播放列表", systemImage: "text.badge.plus")
            }
            Button {
                Task {
                    let added = await library.toggleFavorite(song)
                    if let added = added {
                        player.showToast(added ? "已加入我喜欢" : "已从我喜欢移除")
                    } else {
                        player.showToast(library.favoritesMessage)
                    }
                }
            } label: {
                Label(isFavorite ? "取消我喜欢" : "我喜欢",
                      systemImage: isFavorite ? "heart.fill" : "heart")
            }
            Button {
                UIPasteboard.general.string = "\(song.SongName) - \(song.artist)"
                player.showToast("已复制歌曲信息")
            } label: {
                Label("复制歌名和歌手", systemImage: "doc.on.doc")
            }
        }
    }
}
