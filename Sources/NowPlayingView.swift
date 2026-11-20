import SwiftUI
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: PlayerSheet?
    @State private var lyricSize: LyricTextSize = Preferences.lyricSize
    @State private var showRemaining = true
    @State private var showLyrics = false
    @GestureState private var coverDragOffset: CGFloat = 0
    @AppStorage(Preferences.coverSwipeKey) private var coverSwipeEnabled = true
    @AppStorage(Preferences.coverDoubleTapKey) private var coverDoubleTapEnabled = true
    @AppStorage(Preferences.keepAwakeKey) private var keepAwake = false
    @AppStorage(Preferences.lyricFollowKey) private var lyricAutoFollow = true
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    private var qualityLabel: String {
        let quality = player.currentQuality
        if quality == "128" || quality == "320" {
            return "音质 \(quality)K"
        }
        return "音质 \(quality)"
    }

    private var artworkSize: CGFloat {
        min(UIScreen.main.bounds.width - 72, 330)
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
                topBar

                Spacer(minLength: 14)

                artwork

                Spacer(minLength: 16)

                titleBlock
                progress
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                controls
                    .padding(.top, 18)

                Spacer(minLength: 8)

                bottomActions
            }

            if showLyrics {
                lyricsOverlay
                    .zIndex(10)
            }

            if let toast = player.toast {
                VStack {
                    ToastView(text: toast)
                    Spacer()
                }
                .zIndex(11)
            }
        }
        .animation(.easeInOut(duration: 0.26), value: showLyrics)
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
                                .scaleEffect(1.28)
                                .blur(radius: 52)
                                .opacity(colorScheme == .dark ? 0.34 : 0.16)
                        }
                        Theme.background.opacity(colorScheme == .dark ? 0.58 : 0.82)
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(colorScheme == .dark ? 0.10 : 0.04),
                                Color.clear,
                                Theme.background.opacity(colorScheme == .dark ? 0.92 : 0.96)
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
            .fill(Theme.text.opacity(0.16))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 6)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel("关闭播放页")

            Spacer()

            Text("正在播放")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.secondaryText)

            Spacer()

            Menu {
                Button {
                    activeSheet = .queue
                } label: {
                    Label("播放列表", systemImage: "list.bullet")
                }
                if let song = player.current {
                    Button {
                        activeSheet = .addToPlaylist(song)
                    } label: {
                        Label("加入歌单", systemImage: "text.badge.plus")
                    }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.26)) { showLyrics = true }
                } label: {
                    Label("歌词", systemImage: "music.note")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.text.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多")
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var artwork: some View {
        CoverImage(url: player.current?.coverURL, size: artworkSize, radius: 16)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.42 : 0.16),
                    radius: 22, x: 0, y: 12)
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
            .padding(.horizontal, 36)
    }

    private var titleBlock: some View {
        VStack(spacing: 5) {
            Text(player.current?.SongName ?? "未在播放")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let song = player.current {
                Button {
                    activeSheet = .artist(ArtistTarget(name: song.artist,
                                                      authorID: song.AuthorID,
                                                      cover: song.coverURL))
                } label: {
                    HStack(spacing: 4) {
                        Text(song.artist)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .opacity(0.55)
                    }
                    .font(.system(size: 16))
                    .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(song.artist.isEmpty)
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
                            .font(.system(size: 9, weight: .medium))
                        Text(albumName)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7, weight: .semibold))
                            .opacity(0.5)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(Theme.tertiaryText)
                }
                .buttonStyle(GlassPressButtonStyle())
            }

            if !player.currentQuality.isEmpty {
                Text(qualityLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(.horizontal, 28)
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
                        .fill(Theme.text.opacity(0.14))
                        .frame(height: 3)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: width * ratio, height: 3)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.background.opacity(0.9), lineWidth: 1))
                        .offset(x: width * ratio - 6)

                    if isScrubbing {
                        Text(format(displayedTime))
                            .font(.system(size: 10, weight: .semibold))
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
                        .foregroundColor(Theme.secondaryText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.secondaryText)
        }
    }

    private var controls: some View {
        HStack(spacing: 42) {
            Spacer(minLength: 0)

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundColor(Theme.text.opacity(0.90))
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())

            Button { player.toggle() } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.text))
                            .frame(width: 56, height: 56)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .frame(width: 64, height: 64)
                            .contentShape(Rectangle())
                    }
                }
            }
            .buttonStyle(GlassPressButtonStyle())

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundColor(Theme.text.opacity(0.90))
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private var bottomActions: some View {
        HStack(spacing: 0) {
            bottomAction(title: "歌词", icon: "music.note", active: showLyrics) {
                withAnimation(.easeInOut(duration: 0.26)) { showLyrics = true }
            }
            Spacer()
            bottomAction(title: "播放列表", icon: "list.bullet") {
                activeSheet = .queue
            }
            Spacer()
            bottomAction(title: "加入歌单", icon: "text.badge.plus", disabled: player.current == nil) {
                guard let song = player.current else { return }
                activeSheet = .addToPlaylist(song)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func bottomAction(title: String, icon: String, active: Bool = false,
                              disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(active ? Theme.accent : (disabled ? Theme.tertiaryText : Theme.secondaryText))
            .frame(width: 70, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .disabled(disabled)
    }

    private var lyricsOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Text("歌词")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.26)) { showLyrics = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Theme.separator)
                .frame(height: 0.5)

            lyricView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background.opacity(0.96).ignoresSafeArea())
        .transition(.move(edge: .bottom).combined(with: .opacity))
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

    private func addToPlaylist(_ song: Song, _ target: CloudPlaylist) async {
        do {
            try await KGService.addSongs([song], to: target)
            player.showToast("已加入「\(target.name)」")
        } catch {
            player.showToast((error as? LocalizedError)?.errorDescription ?? "加入歌单失败")
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
