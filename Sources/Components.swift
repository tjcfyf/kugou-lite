import SwiftUI

enum Theme {
    static let background = Color(red: 0.045, green: 0.045, blue: 0.06)
    static let card = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let accent = Color(red: 1.0, green: 0.27, blue: 0.42)
    static let secondaryText = Color.white.opacity(0.55)
}

struct CoverImage: View {
    let url: URL?
    var size: CGFloat = 44
    var radius: CGFloat = 8

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
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
                .foregroundColor(.white.opacity(0.35))
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

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: song.coverURL, size: 46, radius: 10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(song.SongName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
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
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
