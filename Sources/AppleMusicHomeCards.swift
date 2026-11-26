import SwiftUI

/// 首页「为你精选」用的专辑对象。由每日推荐歌曲按专辑 ID 去重得到，
/// 卡片只展示专辑名/歌手，点击进入专辑详情，不再把歌曲当推荐卡片。
struct AlbumRecommendation: Identifiable, Equatable {
    let id: Int
    let name: String
    let artist: String
    let coverURL: URL?
}

/// iOS 27 Apple Music 的 Top Picks 大卡：3:4 竖版、封面满铺、
/// 标题压在底部渐变上，不再叠玻璃播放徽章。第一张 278×352，
/// 第二张开始 218×276，让右侧露出下一张的边缘，提示横向可滑。
struct AppleMusicAlbumCard: View {
    let album: AlbumRecommendation
    var featured: Bool = false
    let onTap: () -> Void

    private var width: CGFloat { featured ? 278 : 218 }
    private var height: CGFloat { width * 1.265 }
    private var radius: CGFloat { 14 }
    private var titleSize: CGFloat { featured ? 21 : 17 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                CoverImage(url: album.coverURL, size: height, radius: 0, showsBorder: false)
                    .frame(width: width, height: height)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.42),
                        .init(color: .black.opacity(0.08), location: 0.55),
                        .init(color: .black.opacity(0.72), location: 0.82),
                        .init(color: .black.opacity(0.94), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(album.name)
                        .font(.system(size: titleSize, weight: .bold))
                        .tracking(-0.25)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(album.artist)
                        .font(.system(size: featured ? 14 : 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.74))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.trailing, 22)

                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "music.note")
                                .font(.system(size: 9, weight: .bold))
                            Text("Music")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white.opacity(0.90))
                        .shadow(color: .black.opacity(0.30), radius: 3, y: 1)
                    }
                    Spacer()
                }
                .padding(12)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
            )
        }
        .buttonStyle(IOS27PressStyle(pressedOpacity: 0.68, pressedScale: 0.975))
    }
}

/// Recently Played / Library 的方形专辑卡：封面 + 下方标题，不叠渐变。
struct RecentAlbumCard: View {
    let album: AlbumRecommendation
    var side: CGFloat = 164
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 7) {
                CoverImage(url: album.coverURL, size: side, radius: 8, showsBorder: false)
                    .frame(width: side, height: side)
                    .clipped()
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.text.opacity(0.08), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(album.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text(album.artist)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(width: side, alignment: .leading)
            }
        }
        .buttonStyle(IOS27PressStyle(pressedOpacity: 0.62, pressedScale: 0.98))
    }
}

/// 支撑整页的纸面底色。iOS 27.2 的 Apple Music 已经移除暖色/蓝色渐变，
/// 内容页就是纯白/纯黑；封面自己的颜色只在播放页和歌手页局部出现。
struct AppBackgroundGradient: View {
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}
