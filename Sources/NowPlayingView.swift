import SwiftUI
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @ObservedObject private var library = LibraryStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: PlayerSheet?
    @State private var lyricSize: LyricTextSize = Preferences.lyricSize
    @State private var showRemaining = true
    @State private var showLyrics = false
    @AppStorage(Preferences.lyricFollowKey) private var lyricAutoFollow = true
    @AppStorage(Preferences.lyricTranslationKey) private var showTranslation = false
    @AppStorage(Preferences.lyricRomanizationKey) private var showRomanization = false
    @AppStorage(Preferences.lyricPhotoModeKey) private var lyricPhotoMode = false
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
        case comments(Song)
        case sleep
        case lyricSources

        var id: String {
            switch self {
            case .queue: return "queue"
            case .album(let target): return "album-\(target.id)"
            case .artist(let target): return "artist-\(target.id)"
            case .addToPlaylist(let song): return "add-\(song.FileHash)"
            case .comments(let song): return "comments-\(song.FileHash)"
            case .sleep: return "sleep"
            case .lyricSources: return "lyric-sources"
            }
        }
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                grabber

                if showLyrics {
                    lyricsTopBar
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    lyricView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                } else {
                    topBar
                        .transition(.opacity)

                    Spacer(minLength: 14)

                    artwork
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))

                    Spacer(minLength: 16)

                    titleBlock
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    progress
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .transition(.opacity)
                }

                controls
                    .padding(.top, showLyrics ? 8 : 18)

                Spacer(minLength: 8)

                bottomActions
            }
            .animation(.easeInOut(duration: 0.26), value: player.current?.id)

            if let toast = player.toast {
                VStack {
                    ToastView(text: toast)
                    Spacer()
                }
                .zIndex(11)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: showLyrics)
        .animation(.easeOut(duration: 0.22), value: player.toast)
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
            case .comments(let song):
                CommentsView(song: song)
            case .sleep:
                SleepTimerSheet().environmentObject(player)
            case .lyricSources:
                LyricSourceSheet().environmentObject(player)
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
                                .scaleEffect(showLyrics && lyricPhotoMode ? 1.02 : 1.28)
                                .blur(radius: showLyrics && lyricPhotoMode ? 0 : 56)
                                .opacity(showLyrics && lyricPhotoMode
                                         ? (colorScheme == .dark ? 0.88 : 0.82)
                                         : (colorScheme == .dark ? 0.28 : 0.12))
                        }
                        Theme.background.opacity(showLyrics && lyricPhotoMode
                                                 ? (colorScheme == .dark ? 0.38 : 0.56)
                                                 : (colorScheme == .dark ? 0.64 : 0.86))
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: lyricPhotoMode)
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

            moreMenu
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var lyricsTopBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text.opacity(0.72))
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel("关闭播放页")

            CoverImage(url: player.current?.coverURL, size: 44, radius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.SongName ?? "未在播放")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            moreMenu
        }
        .padding(.horizontal, 16)
        .frame(height: 58)
    }

    private var moreMenu: some View {
        Menu {
            if let song = player.current {
                if !song.artist.isEmpty {
                    Button {
                        activeSheet = .artist(ArtistTarget(name: song.artist,
                                                          authorID: song.AuthorID,
                                                          cover: song.coverURL))
                    } label: {
                        Label("查看作者 · \(song.artist)", systemImage: "person.crop.circle")
                    }
                }

                if let albumID = song.AlbumID, let albumName = song.AlbumName, !albumName.isEmpty {
                    Button {
                        activeSheet = .album(AlbumTarget(id: albumID,
                                                         name: albumName,
                                                         cover: song.coverURL,
                                                         artist: song.artist))
                    } label: {
                        Label("查看当前专辑 · \(albumName)", systemImage: "rectangle.stack")
                    }
                }

                Divider()

                Button {
                    activeSheet = .addToPlaylist(song)
                } label: {
                    Label("加入歌单", systemImage: "text.badge.plus")
                }

                Button {
                    activeSheet = .lyricSources
                } label: {
                    Label("歌词来源", systemImage: "text.quote")
                }
            }

            if showLyrics {
                Divider()

                Button {
                    showTranslation.toggle()
                    if showTranslation && !player.lyricTranslationAvailable {
                        player.showToast("当前歌词没有译文")
                    }
                } label: {
                    Label(showTranslation ? "隐藏歌词翻译" : "显示歌词翻译",
                          systemImage: showTranslation ? "captions.bubble.fill" : "captions.bubble")
                }

                Button {
                    showRomanization.toggle()
                    if showRomanization && player.lyric.isEmpty {
                        player.showToast("当前没有可显示的音译")
                    }
                } label: {
                    Label(showRomanization ? "隐藏歌词音译" : "显示歌词音译",
                          systemImage: showRomanization ? "character.book.closed.fill" : "character.book.closed")
                }

                Button {
                    lyricPhotoMode.toggle()
                } label: {
                    Label(lyricPhotoMode ? "关闭写真模式" : "写真模式",
                          systemImage: lyricPhotoMode ? "photo.fill" : "photo")
                }
            }

            if !showLyrics {
                Button {
                    withAnimation(.easeInOut(duration: 0.24)) { showLyrics = true }
                } label: {
                    Label("全屏歌词", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }

            Button {
                activeSheet = .sleep
            } label: {
                Label("睡眠模式", systemImage: "moon.zzz")
            }

            if let song = player.current {
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
                    Label("我喜欢",
                          systemImage: library.isFavorite(song) ? "heart.fill" : "heart")
                }
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

    private var artwork: some View {
        CoverImage(url: player.current?.coverURL, size: artworkSize, radius: 12)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.10),
                    radius: 16, x: 0, y: 8)
            .padding(.horizontal, 36)
            // 封面不再接收切歌/双击手势，让播放页的系统的下拉收出手势覆盖整张封面。
            .allowsHitTesting(false)
    }

    private var titleBlock: some View {
        Text(player.current?.SongName ?? "未在播放")
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(Theme.text)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .id(player.current?.id ?? "")
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

            if !player.currentQuality.isEmpty {
                Text(qualityLabel)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(
                        Theme.tertiaryText.opacity(colorScheme == .dark ? 0.58 : 0.48)
                    )
            }
        }
        .animation(isScrubbing ? nil : .linear(duration: 0.25), value: displayedTime)
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
                            .transition(.opacity.combined(with: .scale(scale: 0.86)))
                    } else {
                        ZStack {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 52, weight: .semibold))
                                .foregroundColor(Theme.text)
                                .opacity(player.isPlaying ? 1 : 0)
                                .scaleEffect(player.isPlaying ? 1 : 0.86)
                            Image(systemName: "play.fill")
                                .font(.system(size: 52, weight: .semibold))
                                .foregroundColor(Theme.text)
                                .opacity(player.isPlaying ? 0 : 1)
                                .scaleEffect(player.isPlaying ? 0.86 : 1)
                        }
                        .frame(width: 64, height: 64)
                        .contentShape(Rectangle())
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.20), value: player.isPlaying)
                .animation(.easeInOut(duration: 0.20), value: player.isLoading)
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
                withAnimation(.easeInOut(duration: 0.32)) { showLyrics.toggle() }
            }
            Spacer()
            bottomAction(title: "评论", icon: "text.bubble", disabled: player.current == nil) {
                guard let song = player.current else { return }
                activeSheet = .comments(song)
            }
            Spacer()
            bottomAction(title: "播放列表", icon: "list.bullet") {
                activeSheet = .queue
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
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(active ? Theme.accent : (disabled ? Theme.tertiaryText : Theme.secondaryText))
            .frame(width: 70, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .disabled(disabled)
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
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(player.lyric.enumerated()), id: \.offset) { index, line in
                            VStack(alignment: .leading, spacing: 5) {
                                lyricText(line, active: index == player.lyricIndex)
                                    .font(.system(size: index == player.lyricIndex
                                                  ? lyricSize.fontSize + 7
                                                  : lyricSize.fontSize + 1,
                                                  weight: index == player.lyricIndex ? .bold : .medium))
                                    .lineSpacing(3)
                                    .multilineTextAlignment(.leading)

                                if showTranslation, let translation = line.translation,
                                   !translation.isEmpty {
                                    Text(translation)
                                        .font(.system(size: lyricSize.fontSize - 1, weight: .regular))
                                        .foregroundColor(Theme.secondaryText.opacity(colorScheme == .dark ? 0.68 : 0.78))
                                        .lineSpacing(2)
                                }

                                if showRomanization, let romanization = line.romanization,
                                   !romanization.isEmpty {
                                    Text(romanization)
                                        .font(.system(size: lyricSize.fontSize - 2, weight: .regular))
                                        .foregroundColor(Theme.tertiaryText.opacity(colorScheme == .dark ? 0.72 : 0.82))
                                        .lineSpacing(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.seek(to: max(0, line.time - Double(player.lyricOffsetMs) / 1000))
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 26)
                    .animation(.easeInOut(duration: 0.22), value: player.lyricIndex)
                }
            }
            .onAppear {
                guard !player.lyric.isEmpty else { return }
                proxy.scrollTo(player.lyricIndex, anchor: .center)
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

    private func lyricText(_ line: LyricLine, active: Bool) -> Text {
        guard active, !line.words.isEmpty else {
            var plain = AttributedString(line.text)
            plain.foregroundColor = active
                ? Theme.text
                : Theme.secondaryText.opacity(colorScheme == .dark ? 0.52 : 0.62)
            return Text(plain)
        }
        let time = player.currentTime + Double(player.lyricOffsetMs) / 1000
        var result = AttributedString()
        for word in line.words {
            var part = AttributedString(word.text)
            part.foregroundColor = time >= word.start ? Theme.accent : Theme.text
            result += part
        }
        return Text(result)
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
