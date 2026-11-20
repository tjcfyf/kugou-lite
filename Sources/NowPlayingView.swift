import SwiftUI
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.colorScheme) private var colorScheme
    @State private var activeSheet: PlayerSheet?
    @State private var lyricSize: LyricTextSize = Preferences.lyricSize
    @State private var showRemaining = false
    @GestureState private var coverDragOffset: CGFloat = 0
    @AppStorage(Preferences.coverSwipeKey) private var coverSwipeEnabled = true
    @AppStorage(Preferences.coverDoubleTapKey) private var coverDoubleTapEnabled = true
    @AppStorage(Preferences.keepAwakeKey) private var keepAwake = false
    @AppStorage(Preferences.lyricFollowKey) private var lyricAutoFollow = true
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    private var gestureMode: Bool { coverSwipeEnabled && coverDoubleTapEnabled }

    private var qualityLabel: String {
        let quality = player.currentQuality
        if quality == "128" || quality == "320" {
            return "音质 \(quality)K"
        }
        return "音质 \(quality)"
    }

    private enum PlayerSheet: Identifiable {
        case queue
        case album(AlbumTarget)
        case artist(ArtistTarget)
        case addToPlaylist(Song)

        var id: String {
            switch self {
            case .queue: return "queue"
            case .album(let target): return "album-\(target.id)"
            case .artist(let target): return "artist-\(target.id)"
            case .addToPlaylist(let song): return "add-\(song.FileHash)"
            }
        }
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                grabber

                CoverImage(url: player.current?.coverURL, size: 262, radius: 24)
                    .shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: 12)
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
                    Text(player.current?.SongName ?? "未在播放")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 6) {
                        if let song = player.current {
                            Button {
                                activeSheet = .artist(ArtistTarget(name: song.artist,
                                                                  authorID: song.AuthorID,
                                                                  cover: song.coverURL))
                            } label: {
                                HStack(spacing: 3) {
                                    Text(song.artist)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .semibold))
                                }
                                .font(.system(size: 13))
                                .foregroundColor(Theme.secondaryText)
                            }
                            .buttonStyle(GlassPressButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity)

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
                        .buttonStyle(GlassPressButtonStyle())
                        .padding(.top, 1)
                    }

                    if !player.currentQuality.isEmpty || player.playbackRate != 1.0 {
                        HStack(spacing: 6) {
                            if !player.currentQuality.isEmpty {
                                Text(qualityLabel)
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
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)

                playlistActions
                    .padding(.horizontal, 24)
                    .padding(.top, 14)

                progress
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                if !gestureMode {
                    controls
                        .padding(.top, 10)
                }

                lyricView
                    .frame(maxHeight: .infinity)
                    .padding(.top, gestureMode ? 4 : 8)
            }
            .animation(.easeInOut(duration: 0.24), value: gestureMode)

            if let toast = player.toast {
                VStack {
                    ToastView(text: toast)
                    Spacer()
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: player.toast)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: keepAwake) { enabled in
            UIApplication.shared.isIdleTimerDisabled = enabled
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .queue:
                QueueView().environmentObject(player)
            case .addToPlaylist(let song):
                PlaylistTargetPicker { target in
                    Task { await addToPlaylist(song, target) }
                }
            case .album(let target):
                AlbumDetailSheet(target: target).environmentObject(player)
            case .artist(let target):
                ArtistDetailSheet(target: target).environmentObject(player)
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

    private var playlistActions: some View {
        HStack(spacing: 12) {
            Button { activeSheet = .queue } label: {
                playlistActionLabel(title: "播放列表", icon: "list.bullet")
            }
            .buttonStyle(GlassPressButtonStyle())

            Spacer(minLength: 0)

            Button {
                guard let song = player.current else { return }
                activeSheet = .addToPlaylist(song)
            } label: {
                playlistActionLabel(title: "加入歌单", icon: "text.badge.plus")
            }
            .buttonStyle(GlassPressButtonStyle())
            .disabled(player.current == nil)
            .opacity(player.current == nil ? 0.45 : 1)
        }
    }

    private func playlistActionLabel(title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(Theme.text.opacity(0.88))
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(.regularMaterial))
    }

    private func addToPlaylist(_ song: Song, _ target: CloudPlaylist) async {
        do {
            try await KGService.addSongs([song], to: target)
            player.showToast("已加入「\(target.name)」")
        } catch {
            player.showToast((error as? LocalizedError)?.errorDescription ?? "加入歌单失败")
        }
    }

    private var displayedTime: Double {
        isScrubbing ? scrubTime : player.currentTime
    }

    private var progress: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let ratio = player.duration > 0 ? min(max(displayedTime / player.duration, 0), 1) : 0
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

                    if isScrubbing {
                        Text(format(displayedTime))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.accent)
                            .cornerRadius(8)
                            .position(x: min(max(width * ratio, 30), max(width - 30, 30)), y: -12)
                    }
                }
                .frame(height: 22)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let point = min(max(value.location.x / width, 0), 1)
                            scrubTime = Double(point) * max(player.duration, 1)
                        }
                        .onEnded { value in
                            let point = min(max(value.location.x / width, 0), 1)
                            let target = Double(point) * max(player.duration, 1)
                            scrubTime = target
                            player.seek(to: target)
                            isScrubbing = false
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                )
            }
            .frame(height: 22)

            HStack {
                Text(format(displayedTime))
                Spacer()
                Button {
                    showRemaining.toggle()
                } label: {
                    Text(showRemaining
                         ? "-\(format(max(player.duration - displayedTime, 0)))"
                         : format(player.duration))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.text.opacity(0.62))
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.text.opacity(0.62))
        }
    }

    private var controls: some View {
        HStack(spacing: 30) {
            Spacer(minLength: 0)

            Button { player.previous() } label: {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 48, height: 48)
                    Image(systemName: "backward.fill")
                        .font(.system(size: 21))
                        .foregroundColor(Theme.text.opacity(0.82))
                }
            }
            .buttonStyle(GlassPressButtonStyle())

            Button { player.toggle() } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 66, height: 66)
                    if player.isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(GlassPressButtonStyle())

            Button { player.next() } label: {
                ZStack {
                    Circle()
                        .fill(.regularMaterial)
                        .frame(width: 48, height: 48)
                    Image(systemName: "forward.fill")
                        .font(.system(size: 21))
                        .foregroundColor(Theme.text.opacity(0.82))
                }
            }
            .buttonStyle(GlassPressButtonStyle())

            Spacer(minLength: 0)
        }
    }

    private var lyricView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if player.lyric.isEmpty {
                    VStack(spacing: 12) {
                        Text(player.isLoading ? "正在缓冲…" : (player.lyricLoading ? "歌词加载中…" : (player.errorMessage ?? "暂无歌词")))
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                        if player.errorMessage != nil && !player.isLoading {
                            Button {
                                player.retryCurrent()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("重试")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Theme.accent)
                                .cornerRadius(9)
                            }
                            .buttonStyle(GlassPressButtonStyle())
                        } else if !player.lyricLoading {
                            Button {
                                player.reloadLyric()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("重新加载歌词")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.secondaryText)
                            }
                            .buttonStyle(GlassPressButtonStyle())
                        }
                    }
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
                                .onTapGesture {
                                    player.seek(to: max(0, line.time - Double(player.lyricOffsetMs) / 1000))
                                }
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 30)
                }
            }
            .onChange(of: player.lyricIndex) { index in
                guard lyricAutoFollow else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onChange(of: lyricAutoFollow) { enabled in
                guard enabled else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(player.lyricIndex, anchor: .center)
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
