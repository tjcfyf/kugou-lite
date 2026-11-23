import SwiftUI

/// 首页「为你推荐」用的专辑对象。由每日推荐歌曲按专辑 ID 去重得到，
/// 卡片只展示专辑名/歌手，点击进入专辑详情，不再把歌曲当推荐卡片。
struct AlbumRecommendation: Identifiable, Equatable {
    let id: Int
    let name: String
    let artist: String
    let coverURL: URL?
}

struct AppleMusicAlbumCard: View {
    let album: AlbumRecommendation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                CoverImage(url: album.coverURL, size: 226, radius: 10)
                    .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 7)
                Text(album.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .frame(width: 226, alignment: .leading)
                Text(album.artist)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 226, alignment: .leading)
            }
        }
        .buttonStyle(AppleMusicPressStyle())
    }
}

/// 顶部低亮度的深蓝黑渐变，让磨砂顶栏和下方内容之间不再是一条
/// 「半透玻璃 + 纯黑」的硬切边；底部仍收回到原来的深色底。
struct AppBackgroundGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.075, green: 0.095, blue: 0.135),
                        Color(red: 0.035, green: 0.043, blue: 0.062),
                        Theme.background
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                Theme.background
            }
        }
        .ignoresSafeArea()
    }
}
