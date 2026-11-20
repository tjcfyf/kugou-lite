import SwiftUI
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.colorScheme) private var colorScheme
    @State private var activeSheet: PlayerSheet?
    @ObservedObject private var library = LibraryStore.shared
    @State private var lyricSize: LyricTextSize = Preferences.lyricSize
    @State private var showRemaining = false
    @GestureState private var coverDragOffset: CGFloat = 0
    @AppStorage(Preferences.coverSwipeKey) private var coverSwipeEnabled = true
    @AppStorage(Preferences.coverDoubleTapKey) private var coverDoubleTapEnabled = true

    private var gestureMode: Bool { coverSwipeEnabled && coverDoubleTapEnabled }

    private enum PlayerSheet: Identifiable {
        case queue
        case settings
        case album(AlbumTarget)

        var id: String {
            switch self {
            case .queue: return "queue"
            case .settings: return "settings"
            case .album(let target): return "album-\(target.id)"
            }
        }
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                grabber

                CoverImage(url: player.current?.coverURL, size: 262, radius: 24)
                    .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
                    .offset(x: coverDragOffset)
                    .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.82), value: coverDragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .updating($coverDragOffset) { value, state, _ in
                                guard coverSwipeEnabled else { return }
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    state = value.translation.width
                                }
                            }
                            .onEnded { value in
                                guard coverSwipeEnabled else { return }
                                let dx = value.translation.width
                                guard abs(dx) > 55, abs(dx) > abs(value.translation.height) else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if dx < 0 { player.next() } else { player.previous() }
                            }
                    )
                    .onTapGesture(count: 2) {
                        guard coverDoubleTapEnabled else { return }
                        player.toggle()
                    }
                    .padding(.top, 8)

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(player.current?.SongName ?? "未在播放")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)

                        if let song = player.current {
                            Button {
                                let added = library.toggleFavorite(song)
                                player.showToast(added ? "已收藏" : "已取消收藏")
                            } label: {
                                Image(systemName: library.favorites.contains(where: { $0.FileHash == song.FileHash }) ? "heart.fill" : "heart")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(library.favorites.contains(where: { $0.FileHash == song.FileHash }) ? Theme.accent : Theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(player.current?.artist ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                        if !player.currentQuality.isEmpty {
                            Text("音质 \(player.currentQuality)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.accent.opacity(0.7), lineWidth: 0.6)
                                )
                        }
                        if player.playbackRate != 1.0 {
                            Text(PlaybackSpeed.allCases.first(where: { abs($0.rawValue - player.playbackRate) < 0.01 })?.title ?? "\(player.playbackRate)x")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.secondaryText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.separator, lineWidth: 0.6)
                                )
                        }
                    }

                    if let song = player.current, let albumID = song.AlbumID,
                       let albumName = song.AlbumName, !albumName.isEmpty {
                        Button {
                            activeSheet = .album(AlbumTarget(id: albumID,
                                                             name: albumName,
                                                             cover: song.coverURL,
                                                             artist: song.artist))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: 10, weight: .medium))
                                Text(albumName)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 1)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)

                progress
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                if !gestureMode {
                    controls
                        .padding(.top, 10)
                }

                lyricView
                    .frame(maxHeight: .infinity)
                    .padding(.top, gestureMode ? 4 : 8)
            }
            .animation(.easeInOut(duration: 0.24), value: gestureMode)

            VStack {
                HStack(spacing: 8) {
                    if gestureMode {
                        Button { activeSheet = .queue } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.text.opacity(0.7))
                                .frame(width: 30, height: 30)
                                .background(Theme.chip)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.text.opacity(0.75))
                            .frame(width: 34, height: 34)
                            .background(Theme.chip)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if let toast = player.toast {
                VStack {
                    ToastView(text: toast)
                    Spacer()
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: player.toast)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .queue:
                QueueView().environmentObject(player)
            case .settings:
                PlayerSettingsView().environmentObject(player)
            case .album(let target):
                AlbumDetailSheet(target: target).environmentObject(player)
            }
        }

    }

    private var background: some View {
        Theme.background
            .overlay(
                GeometryReader { geo in
                    ZStack {
                        if let url = player.current?.coverURL {
                            CoverImage(url: url, size: max(geo.size.width, geo.size.height), radius: 0)
                                .scaleEffect(1.35)
                                .blur(radius: 55)
                                .opacity(colorScheme == .dark ? 0.55 : 0.40)
                        }
                        Theme.background.opacity(colorScheme == .dark ? 0.35 : 0.55)
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                                Color.clear,
                                Theme.background.opacity(0.8),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottom
                        )
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            )
            .ignoresSafeArea()
    }

    private var grabber: some View {
        Capsule()
            .fill(Theme.separator)
            .frame(width: 38, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 8)
    }

    private var progress: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let ratio = player.duration > 0 ? min(max(player.currentTime / player.duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.text.opacity(0.12))
                        .frame(height: 4)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: width * ratio, height: 4)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Theme.card.opacity(0.9), lineWidth: 1.5))
                        .offset(x: width * ratio - 7)
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = min(max(value.location.x / width, 0), 1)
                            player.seek(to: Double(point) * max(player.duration, 1))
                        }
                )
            }
            .frame(height: 22)

            HStack {
                Text(format(player.currentTime))
                Spacer()
                Button {
                    showRemaining.toggle()
                } label: {
                    Text(showRemaining
                         ? "-\(format(max(player.duration - player.currentTime, 0)))"
                         : format(player.duration))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.text.opacity(0.62))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.text.opacity(0.62))
        }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            Button { player.cyclePlayMode() } label: {
                Image(systemName: player.playMode.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(player.playMode == .loop ? Theme.text.opacity(0.55) : Theme.accent)
            }

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.text.opacity(0.85))
            }

            Button { player.toggle() } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 64, height: 64)
                    if player.isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.text.opacity(0.85))
            }

            Button { activeSheet = .queue } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(Theme.text.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
    }

    private var lyricView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if player.lyric.isEmpty {
                    Text(player.isLoading ? "正在缓冲…" : (player.errorMessage ?? "暂无歌词"))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.top, 24)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(player.lyric.enumerated()), id: \.offset) { index, line in
                            Text(line.text)
                                .font(.system(size: index == player.lyricIndex ? lyricSize.fontSize + 2 : lyricSize.fontSize,
                                              weight: index == player.lyricIndex ? .semibold : .regular))
                                .foregroundColor(index == player.lyricIndex ? Theme.text : Theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { player.seek(to: line.time) }
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 30)
                }
            }
            .onChange(of: player.lyricIndex) { index in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .mask(
            LinearGradient(
                colors: [.clear, .black, .black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
