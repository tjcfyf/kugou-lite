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
    var featured: Bool = false
    let onTap: () -> Void

    private var side: CGFloat { featured ? 292 : 186 }
    private var radius: CGFloat { featured ? 24 : 19 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                CoverImage(url: album.coverURL, size: side, radius: radius, showsBorder: false)
                    .frame(width: side, height: side)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.04), location: 0.34),
                        .init(color: .black.opacity(0.76), location: 0.78),
                        .init(color: .black.opacity(0.92), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(album.name)
                        .font(.system(size: featured ? 22 : 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(album.artist)
                        .font(.system(size: featured ? 14 : 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(.horizontal, featured ? 16 : 12)
                .padding(.bottom, featured ? 16 : 12)
                .padding(.trailing, 48)

                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "music.note")
                                .font(.system(size: 10, weight: .bold))
                            Text("Music")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    }
                    Spacer()
                    HStack {
                        Spacer()
                        playBadge
                    }
                }
                .padding(featured ? 14 : 10)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.26), radius: featured ? 20 : 12, x: 0, y: 10)
        }
        .buttonStyle(AppleMusicPressStyle())
    }

    private var playBadge: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: featured ? 40 : 32, height: featured ? 40 : 32)
            Circle()
                .stroke(Color.white.opacity(0.34), lineWidth: 0.7)
                .frame(width: featured ? 40 : 32, height: featured ? 40 : 32)
            Image(systemName: "play.fill")
                .font(.system(size: featured ? 15 : 12, weight: .semibold))
                .foregroundColor(.white)
        }
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
                        Color(red: 0.055, green: 0.055, blue: 0.065),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.985, green: 0.985, blue: 0.992),
                        Color(red: 0.955, green: 0.955, blue: 0.965)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}
