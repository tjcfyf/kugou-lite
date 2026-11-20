import SwiftUI
import UIKit

enum Theme {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light })
    }

    static let background = dynamic(
        light: UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.045, green: 0.045, blue: 0.06, alpha: 1)
    )
    static let card = dynamic(
        light: UIColor.white,
        dark: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    )
    static let accent = Color(red: 1.0, green: 0.27, blue: 0.42)
    static let text = dynamic(light: .black, dark: .white)
    static let secondaryText = dynamic(
        light: UIColor.black.withAlphaComponent(0.55),
        dark: UIColor.white.withAlphaComponent(0.55)
    )
    static let tertiaryText = dynamic(
        light: UIColor.black.withAlphaComponent(0.28),
        dark: UIColor.white.withAlphaComponent(0.35)
    )
    static let chip = dynamic(
        light: UIColor.black.withAlphaComponent(0.06),
        dark: UIColor.white.withAlphaComponent(0.08)
    )
    static let separator = dynamic(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.08)
    )
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
        library.favorites.contains(where: { $0.FileHash == song.FileHash })
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
            actionRow(title: isFavorite ? "取消收藏" : "收藏", icon: isFavorite ? "heart.fill" : "heart") {
                let added = library.toggleFavorite(song)
                player.showToast(added ? "已收藏" : "已取消收藏")
                dismiss()
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
        .background(Theme.background.ignoresSafeArea())
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
    @EnvironmentObject private var player: PlayerEngine
    @ObservedObject private var library = LibraryStore.shared

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: song.coverURL, size: 46, radius: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(song.SongName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    if song.needsPurchase {
                        Text("VIP")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Theme.accent.opacity(0.7), lineWidth: 0.7)
                            )
                    }
                }
                Text(song.artist)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "play.circle")
                .font(.system(size: 22))
                .foregroundColor(Theme.tertiaryText)
        }
        .padding(.vertical, 6)
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
                let added = library.toggleFavorite(song)
                player.showToast(added ? "已收藏" : "已取消收藏")
            } label: {
                Label(library.favorites.contains(where: { $0.FileHash == song.FileHash }) ? "取消收藏" : "收藏",
                      systemImage: library.favorites.contains(where: { $0.FileHash == song.FileHash }) ? "heart.fill" : "heart")
            }
        }
    }
}
