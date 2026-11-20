import SwiftUI
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var albumTheme: AlbumThemeStore
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
    @State private var lyricClockTime: Double = 0
    @State private var lyricClockDate = Date()
    @State private var dragOffset: CGFloat = 0

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

                if !showLyrics {
                    controls
                        .padding(.top, 18)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer(minLength: 8)

                bottomActions
            }

            if let toast = player.toast {
                VStack {
                    ToastView(text: toast)
                    Spacer()
                }
                .zIndex(11)
            }
        }
        .offset(y: dragOffset)
        .background(Theme.background.ignoresSafeArea())
        .simultaneousGesture(dismissGesture)
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
        GeometryReader { geo in
            ZStack {
                Theme.background

                if !(showLyrics && lyricPhotoMode), let palette = albumTheme.paletteColor {
                    LinearGradient(
                        stops: [
                            .init(color: palette.opacity(colorScheme == .dark ? 0.88 : 0.60), location: 0),
                            .init(color: palette.opacity(colorScheme == .dark ? 0.46 : 0.30), location: 0.42),
                            .init(color: palette.opacity(colorScheme == .dark ? 0.18 : 0.10), location: 0.76),
                            .init(color: Theme.background, location: 1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                if showLyrics && lyricPhotoMode, let url = player.current?.coverURL {
                    CoverImage(url: url, size: max(geo.size.width, geo.size.height), radius: 0)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.02)
                        .blur(radius: 0)
                        .opacity(colorScheme == .dark ? 0.88 : 0.82)
                }

                if showLyrics && lyricPhotoMode {
                    Theme.background.opacity(colorScheme == .dark ? 0.38 : 0.56)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: lyricPhotoMode)
        .animation(.easeInOut(duration: 0.55), value: albumTheme.paletteKey)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard activeSheet == nil else { return }
                guard !showLyrics || value.startLocation.y < 100 else { return }
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                guard vertical > 0, vertical > horizontal * 1.25 else { return }
                dragOffset = min(vertical * 0.88, 280)
            }
            .onEnded { value in
                guard activeSheet == nil else { return }
                guard !showLyrics || value.startLocation.y < 100 else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { dragOffset = 0 }
                    return
                }
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                let predicted = value.predictedEndTranslation.height
                if vertical > 110, vertical > horizontal, predicted > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
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

                Divider()
            }

            Button {
                activeSheet = .queue
            } label: {
                Label("播放列表", systemImage: "list.bullet")
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
        CrossfadeArtwork(url: player.current?.coverURL, size: artworkSize)
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
            .animation(.easeInOut(duration: 0.26), value: player.current?.id)
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
                    // 透明进度：底线接近音质标签的淡度，播放段用主色渐变保持可读。
                    Capsule()
                        .fill(Theme.text.opacity(colorScheme == .dark ? 0.11 : 0.08))
                        .frame(height: 2.5)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [albumTheme.accentColor.opacity(0.42), albumTheme.accentColor.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * ratio, height: 2.5)
                    Circle()
                        .fill(albumTheme.accentColor.opacity(0.62))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Theme.background.opacity(0.34), lineWidth: 0.6))
                        .offset(x: width * ratio - 4.5)

                    if isScrubbing {
                        Text(format(displayedTime))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(albumTheme.accentColor.opacity(0.78))
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
            Spacer(minLength: 0)
            bottomAction(title: "评论", icon: "text.bubble", disabled: player.current == nil) {
                guard let song = player.current else { return }
                activeSheet = .comments(song)
            }
        }
        .padding(.horizontal, 42)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func bottomAction(title: String, icon: String, active: Bool = false,
                              disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(active ? Theme.accent : (disabled ? Theme.tertiaryText : Theme.secondaryText))
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(title)
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
                                .background(Theme.accentGradient)
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
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(player.lyric.enumerated()), id: \.offset) { index, line in
                            VStack(alignment: .leading, spacing: 5) {
                                Group {
                                    if index == player.lyricIndex, !line.words.isEmpty, player.isPlaying {
                                        TimelineView(.periodic(from: .now, by: 0.05)) { context in
                                            lyricText(line, active: true, timeOverride: lyricClock(context.date))
                                        }
                                    } else {
                                        lyricText(line, active: index == player.lyricIndex)
                                    }
                                }
                                .font(.system(size: index == player.lyricIndex
                                              ? lyricSize.fontSize + 7
                                              : lyricSize.fontSize,
                                              weight: index == player.lyricIndex ? .bold : .medium))
                                .lineSpacing(6)
                                .multilineTextAlignment(.leading)

                                if showTranslation, let translation = line.translation,
                                   !translation.isEmpty {
                                    Text(translation)
                                        .font(.system(size: lyricSize.fontSize - 2, weight: .regular))
                                        .foregroundColor(Theme.secondaryText.opacity(colorScheme == .dark ? 0.68 : 0.78))
                                        .lineSpacing(2)
                                }

                                if showRomanization, let romanization = line.romanization,
                                   !romanization.isEmpty {
                                    Text(romanization)
                                        .font(.system(size: lyricSize.fontSize - 3, weight: .regular))
                                        .foregroundColor(Theme.tertiaryText.opacity(colorScheme == .dark ? 0.72 : 0.82))
                                        .lineSpacing(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .blur(radius: index == player.lyricIndex ? 0 : 2.2)
                            .opacity(index == player.lyricIndex ? 1 : 0.48)
                            .animation(.easeInOut(duration: 0.28), value: player.lyricIndex)
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
                lyricClockTime = player.currentTime
                lyricClockDate = Date()
                guard !player.lyric.isEmpty else { return }
                proxy.scrollTo(player.lyricIndex, anchor: .center)
            }
            .onChange(of: player.currentTime) { time in
                lyricClockTime = time
                lyricClockDate = Date()
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

    private func lyricClock(_ date: Date) -> Double {
        let elapsed = player.isPlaying ? max(0, date.timeIntervalSince(lyricClockDate)) : 0
        return lyricClockTime + elapsed
    }

    private func lyricText(_ line: LyricLine, active: Bool, timeOverride: Double? = nil) -> Text {
        guard active, !line.words.isEmpty else {
            var plain = AttributedString(line.text)
            plain.foregroundColor = active
                ? Theme.text
                : Theme.secondaryText.opacity(colorScheme == .dark ? 0.52 : 0.62)
            return Text(plain)
        }

        let time = (timeOverride ?? player.currentTime) + Double(player.lyricOffsetMs) / 1000
        var result = AttributedString()

        for word in line.words {
            let characters = Array(word.text)
            guard !characters.isEmpty else { continue }

            let wordProgress: Double
            if word.duration > 0.001 {
                wordProgress = min(max((time - word.start) / word.duration, 0), 1)
            } else {
                wordProgress = time >= word.start ? 1 : 0
            }

            for (index, character) in characters.enumerated() {
                let progress = min(max(wordProgress * Double(characters.count) - Double(index), 0), 1)
                var part = AttributedString(String(character))
                part.foregroundColor = karaokeColor(progress)
                result += part
            }
        }

        return Text(result)
    }

    private func karaokeColor(_ progress: Double) -> Color {
        let base: (Double, Double, Double) = colorScheme == .dark
            ? (1.0, 1.0, 1.0)
            : (0.043, 0.071, 0.125)
        let accent = albumTheme.accentComponents(for: colorScheme)
        let p = min(max(progress, 0), 1)
        return Color(
            red: base.0 + (accent.0 - base.0) * p,
            green: base.1 + (accent.1 - base.1) * p,
            blue: base.2 + (accent.2 - base.2) * p
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

/// 播放页封面：旧图留在底层，新图彻底载入后再淡入，避免切歌时闪占位图。
private struct CrossfadeArtwork: View {
    let url: URL?
    let size: CGFloat

    @State private var frontURL: URL?
    @State private var currentImage: UIImage?
    @State private var previousImage: UIImage?
    @State private var frontLoaded = true
    @State private var loadToken = UUID()

    init(url: URL?, size: CGFloat) {
        self.url = url
        self.size = size
        _frontURL = State(initialValue: url)
        _frontLoaded = State(initialValue: true)
    }

    var body: some View {
        ZStack {
            if let previousImage = previousImage {
                Image(uiImage: previousImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 0.5)
                    )
            }

            if let frontURL = frontURL {
                CoverImage(url: frontURL, size: size, radius: 12) { loadedURL, image in
                    guard let image = image, loadedURL == frontURL else { return }
                    currentImage = image
                    completeLoad()
                }
                .id(frontURL.absoluteString)
                .opacity(frontLoaded ? 1 : 0)
            }
        }
        .frame(width: size, height: size)
        .onChange(of: url) { newURL in
            transition(to: newURL)
        }
    }

    private func transition(to newURL: URL?) {
        guard newURL != frontURL else { return }

        previousImage = currentImage
        currentImage = nil
        frontURL = newURL

        guard newURL != nil else {
            previousImage = nil
            frontLoaded = true
            return
        }

        // 第一次加载没有旧图可托底，直接显示占位图，由 CoverImage 自己淡入。
        if previousImage == nil {
            frontLoaded = true
            return
        }

        frontLoaded = false
        let token = UUID()
        loadToken = token

        // 新封面加载失败或太慢时，1.8 秒后退回占位图，旧图不会一直挂着。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard loadToken == token, !frontLoaded else { return }
            completeLoad()
        }
    }

    private func completeLoad() {
        let token = UUID()
        loadToken = token
        withAnimation(.easeInOut(duration: 0.32)) {
            frontLoaded = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
            guard loadToken == token else { return }
            previousImage = nil
        }
    }
}
