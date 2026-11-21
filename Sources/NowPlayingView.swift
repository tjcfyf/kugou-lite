import SwiftUI
import UIKit

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    var onClose: (() -> Void)? = nil
    @ObservedObject private var library = LibraryStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: PlayerSheet?
    @State private var showSleepSheet = false
    @State private var showKaraokeSheet = false
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
    @State private var artworkPalette: [Color] = []

    private var qualityLabel: String {
        let quality = player.currentQuality
        if quality == "128" || quality == "320" {
            return "音质 \(quality)K"
        }
        return "音质 \(quality)"
    }

    private var playerPrimary: Color { Theme.text }
    private var playerSecondary: Color { Theme.secondaryText }
    private var playerTertiary: Color { Theme.tertiaryText }
    private var playerAccent: Color { Theme.accent }
    private var playerAccentForeground: Color { Theme.onAccent }

    private var artworkSize: CGFloat {
        min(UIScreen.main.bounds.width - 72, 330)
    }

    private enum PlayerSheet: Identifiable {
        case queue
        case album(AlbumTarget)
        case artist(ArtistTarget)
        case addToPlaylist(Song)
        case comments(Song)
        case lyricSources

        var id: String {
            switch self {
            case .queue: return "queue"
            case .album(let target): return "album-\(target.id)"
            case .artist(let target): return "artist-\(target.id)"
            case .addToPlaylist(let song): return "add-\(song.FileHash)"
            case .comments(let song): return "comments-\(song.FileHash)"
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

            if showSleepSheet {
                GlassHalfSheet(isPresented: $showSleepSheet, heightRatio: 0.50) {
                    SleepTimerSheet(onClose: { showSleepSheet = false }).environmentObject(player)
                }
                .zIndex(20)
            }

            if showKaraokeSheet {
                GlassHalfSheet(isPresented: $showKaraokeSheet, heightRatio: 0.60) {
                    KaraokeSheet(onClose: { showKaraokeSheet = false }).environmentObject(player)
                }
                .zIndex(20)
            }

            if let toast = player.toast {
                VStack {
                    ToastView(text: toast)
                    Spacer()
                }
                .zIndex(30)
            }
        }
        .offset(y: dragOffset)
        .background(Theme.background.ignoresSafeArea())
        .simultaneousGesture(dismissGesture)
        .animation(.easeInOut(duration: 0.32), value: showLyrics)
        .animation(.easeOut(duration: 0.22), value: player.toast)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: showSleepSheet)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: showKaraokeSheet)
        .onChange(of: player.current?.FileHash) { _ in
            artworkPalette = []
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
            case .comments(let song):
                CommentsView(song: song)
            case .lyricSources:
                LyricSourceSheet().environmentObject(player)
            }
        }
    }

    private var background: some View {
        GeometryReader { geo in
            ZStack {
                // 专辑图取三色 → 纯色渐变铺底 → iOS 原生磨砂玻璃。
                // 不再用封面图直接铺底，也不叠任何颜色遮罩。
                if artworkPalette.count >= 3 {
                    LinearGradient(gradient: Gradient(colors: artworkPalette),
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .transition(.opacity)
                } else {
                    Theme.background
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                NativeFrostedGlass(style: colorScheme == .dark ? .systemThinMaterialDark : .systemThinMaterialLight)
                    .frame(width: geo.size.width, height: geo.size.height)

                if showLyrics && lyricPhotoMode, let url = player.current?.coverURL {
                    CoverImage(url: url, size: max(geo.size.width, geo.size.height), radius: 0, showsBorder: false)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.02)
                }

                // 只负责下载封面并提取三色，本身不显示。
                if let url = player.current?.coverURL {
                    CoverImage(url: url, size: 2, radius: 0, showsBorder: false) { _, image in
                        guard let image else {
                            withAnimation(.easeInOut(duration: 0.35)) { artworkPalette = [] }
                            return
                        }
                        let colors = ArtworkPalette.colors(from: image)
                        withAnimation(.easeInOut(duration: 0.45)) { artworkPalette = colors }
                    }
                    .frame(width: 2, height: 2)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.35), value: lyricPhotoMode)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onChanged { value in
                guard activeSheet == nil, !showSleepSheet, !showKaraokeSheet else { return }
                guard !showLyrics || value.startLocation.y < 100 else { return }
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                guard vertical > 0, vertical > horizontal * 1.25 else { return }
                dragOffset = min(vertical * 0.88, 280)
            }
            .onEnded { value in
                guard activeSheet == nil, !showSleepSheet, !showKaraokeSheet else { return }
                guard !showLyrics || value.startLocation.y < 100 else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { dragOffset = 0 }
                    return
                }
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                let predicted = value.predictedEndTranslation.height
                if vertical > 110, vertical > horizontal, predicted > 120 {
                    closePlayer()
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
                closePlayer()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(playerPrimary.opacity(0.82))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel("关闭播放页")

            Spacer()

            Text("正在播放")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(playerSecondary)

            Spacer()

            moreMenu
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    private var lyricsTopBar: some View {
        HStack(spacing: 10) {
            Button {
                closePlayer()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(playerPrimary.opacity(0.84))
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .accessibilityLabel("关闭播放页")

            CoverImage(url: player.current?.coverURL, size: 44, radius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(player.current?.SongName ?? "未在播放")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(playerPrimary)
                    .lineLimit(1)
                Text(player.current?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(playerSecondary)
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

            Button {
                showSleepSheet = true
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
                .foregroundColor(playerPrimary.opacity(0.82))
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
            .foregroundColor(playerPrimary)
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
                        .fill(playerPrimary.opacity(colorScheme == .dark ? 0.16 : 0.12))
                        .frame(height: 2.5)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent.opacity(0.42), Theme.accent.opacity(0.72)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * ratio, height: 2.5)
                    Circle()
                        .fill(Theme.accent.opacity(0.62))
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(playerPrimary.opacity(0.28), lineWidth: 0.6))
                        .offset(x: width * ratio - 4.5)

                    if isScrubbing {
                        Text(format(displayedTime))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(playerAccentForeground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.accent.opacity(0.78))
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
                        .foregroundColor(playerSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(playerSecondary)

            if !player.currentQuality.isEmpty {
                Text(qualityLabel)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(
                        playerTertiary.opacity(colorScheme == .dark ? 0.72 : 0.68)
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
                    .foregroundColor(playerPrimary.opacity(0.94))
                    .frame(width: 56, height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())

            Button { player.toggle() } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: playerPrimary))
                            .frame(width: 56, height: 56)
                            .transition(.opacity.combined(with: .scale(scale: 0.86)))
                    } else {
                        ZStack {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 52, weight: .semibold))
                                .foregroundColor(playerPrimary)
                                .opacity(player.isPlaying ? 1 : 0)
                                .scaleEffect(player.isPlaying ? 1 : 0.86)
                            Image(systemName: "play.fill")
                                .font(.system(size: 52, weight: .semibold))
                                .foregroundColor(playerPrimary)
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
                    .foregroundColor(playerPrimary.opacity(0.94))
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
            bottomAction(title: "分离", icon: "music.mic", active: player.karaokeEnabled,
                         disabled: player.current == nil) {
                showKaraokeSheet = true
            }
            Spacer(minLength: 0)
            bottomAction(title: "评论", icon: "text.bubble", disabled: player.current == nil) {
                guard let song = player.current else { return }
                activeSheet = .comments(song)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private func bottomAction(title: String, icon: String, active: Bool = false,
                              disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(active ? playerAccent : (disabled ? playerTertiary : playerSecondary))
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
                            .foregroundColor(playerSecondary)
                        if player.errorMessage != nil && !player.isLoading {
                            Button {
                                player.retryCurrent()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("重试")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(playerAccentForeground)
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
                                .foregroundColor(playerSecondary)
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
                                        .foregroundColor(playerSecondary.opacity(colorScheme == .dark ? 0.68 : 0.78))
                                        .lineSpacing(2)
                                }

                                if showRomanization, let romanization = line.romanization,
                                   !romanization.isEmpty {
                                    Text(romanization)
                                        .font(.system(size: lyricSize.fontSize - 3, weight: .regular))
                                        .foregroundColor(playerTertiary.opacity(colorScheme == .dark ? 0.72 : 0.82))
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
                ? playerPrimary
                : playerSecondary.opacity(colorScheme == .dark ? 0.72 : 0.78)
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
        let p = min(max(progress, 0), 1)
        return Theme.text.opacity(0.46 + 0.54 * p)
    }

    private func closePlayer() {
        if let onClose = onClose {
            onClose()
        } else {
            dismiss()
        }
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


struct KaraokeSheet: View {
    @EnvironmentObject private var player: PlayerEngine
    var onClose: () -> Void

    private var modeTitle: String {
        switch player.karaokeMode {
        case .dualTrack: return "官方双轨"
        case .centerChannel: return "立体声兼容分离"
        case .aiModel: return "AI 本地分离"
        case .unavailable: return player.karaokeEnabled ? "正在准备分离资源" : "未开启"
        }
    }

    private var modeDetail: String {
        switch player.karaokeMode {
        case .dualTrack:
            return "已取到官方人声/伴奏双轨，可独立调节两条音轨音量。"
        case .centerChannel:
            return "官方双轨和 AI 都不可用，临时使用立体声中置声道估计分离。"
        case .aiModel:
            return "官方没有双轨，已自动切到本地 MSS 模型；4.9MB，完全离线，约 0.1 秒延迟。"
        case .unavailable:
            return player.karaokeEnabled
                ? "正在请求官方双轨；取不到时会自动尝试 AI 本地分离。"
                : "伴唱已在设置里关闭；开启后优先官方双轨，没有双轨才用 AI。"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    modeCard

                    VStack(alignment: .leading, spacing: 18) {
                        volumeRow(title: "人声", value: player.karaokeVocalVolume) { value in
                            player.setKaraokeVolumes(vocal: value,
                                                     accompaniment: player.karaokeAccompanimentVolume)
                        }
                        volumeRow(title: "伴奏", value: player.karaokeAccompanimentVolume) { value in
                            player.setKaraokeVolumes(vocal: player.karaokeVocalVolume,
                                                     accompaniment: value)
                        }
                    }
                    .padding(16)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    HStack(spacing: 10) {
                        presetButton("纯伴奏") {
                            player.setKaraokeVolumes(vocal: 0, accompaniment: 1)
                        }
                        presetButton("纯人声") {
                            player.setKaraokeVolumes(vocal: 1, accompaniment: 0)
                        }
                        presetButton("还原") {
                            player.setKaraokeVolumes(vocal: 1, accompaniment: 1)
                        }
                    }

                    Text(player.karaokeEnabled
                         ? "人声/伴奏音量只影响当前播放，不会改变歌曲本身的音质。"
                         : "到「我的 → 设置 → 伴唱」打开开关。")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())

            Spacer()

            Text("伴唱 / 分离")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.text)

            Spacer()

            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle()
                    .fill(player.karaokeEnabled ? Theme.accent : Theme.tertiaryText)
                    .frame(width: 6, height: 6)
                Text(modeTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
            }
            Text(modeDetail)
                .font(.system(size: 11))
                .foregroundColor(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func volumeRow(title: String, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.text)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
                .tint(Theme.accent)
                .disabled(!player.karaokeEnabled)
        }
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.chip)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(GlassPressButtonStyle())
        .disabled(!player.karaokeEnabled)
    }
}
