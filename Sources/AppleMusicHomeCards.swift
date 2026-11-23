import SwiftUI

/// Apple Music「Top Picks」式大封面卡片：封面 + 歌名 + 歌手。
/// 只用于首页横向推荐，避免把每日列表变成卡片墙。
struct AppleMusicFeatureCard: View {
    let song: Song
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                CoverImage(url: song.coverURL, size: 226, radius: 10)
                    .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 7)
                Text(song.SongName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .frame(width: 226, alignment: .leading)
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 226, alignment: .leading)
            }
        }
        .buttonStyle(AppleMusicPressStyle())
    }
}
