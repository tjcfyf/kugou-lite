import SwiftUI
import UIKit

/// PlayerPanelFrame 为了做窗口形变会 ignoresSafeArea，所以播放页内部必须
/// 自己补回状态栏和 Home Indicator 的安全区，否则顶部按钮会压到系统状态栏。
private enum PlayerWindowInsets {
    static var top: CGFloat {
        guard let window = keyWindow else { return 20 }
        return max(window.safeAreaInsets.top, 20)
    }

    static var bottom: CGFloat {
        guard let window = keyWindow else { return 0 }
        return window.safeAreaInsets.bottom
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}

struct PlayerCoverFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

/// 播放页大封面在窗口坐标系里的位置；Root 用它裁“只缩专辑图”的收起快照。
struct PlayerArtworkGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Binding var panelProgress: CGFloat
    var panelOrigin: CGRect = .zero
    var onClose: (() -> Void)? = nil
    var onInteractiveDismissBegan: (() -> Bool)? = nil
    var onInteractiveDismissChanged: ((CGFloat) -> Void)? = nil
    var onInteractiveDismissEnded: ((Bool) -> Void)? = nil
    @ObservedObject private var library = LibraryStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.playerPanelProgress) private var visualProgress
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
    @State private var isClosing = false
    @State private var interactiveDismiss = false
    @State private var didCrossDismissThreshold = false
    @State private var artworkPalette: [Color] = []
    @State private var artworkImage: UIImage?
    @State private var coverFrame: CGRect = .zero

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

    /// 面板形变期间（展开/拖动/收回）关闭最贵的全屏磨砂与逐行模糊，
    /// 只保留静态渐变和文字；这些效果在 260ms 的收起动画里几乎看不出来，
    /// 但会让每一帧都做一次离屏合成，是「一卡一卡」的主要来源。
    private var isPanelMoving: Bool {
        visualProgress < 0.995
    }

    private var artworkSize: CGFloat {
        min(UIScreen.main.bounds.width - 48, 340)
    }

    /// 页面内容在面板展开前 20% 行程内淡入；与 MD3Music 的
    /// `playerPanelOpacity` 同式。面板底色由 PlayerPanelFrame 独立处理。
    private var pageContentOpacity: Double {
        let h = max(UIScreen.main.bounds.height, 1)
        let originTop = min(max(panelOrigin.minY, 0), h)
        let p = min(max(visualProgress, 0), 1)
        let span = 0.2 * h
        let travel = min(originTop, span)
        guard travel > 0 else { return 1 }
        return Double(min(1, p * originTop / travel))
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
            pageContent
                .opacity(pageContentOpacity)

            coverMorphOverlay
        }
        .coordinateSpace(name: "playerPage")
        .animation(.easeInOut(duration: 0.22), value: showLyrics)
        .animation(.easeOut(duration: 0.22), value: player.toast)
        .onPreferenceChange(PlayerCoverFramePreferenceKey.self) { coverFrame = $0 }
        .onChange(of: visualProgress) { value in
            // 播放页现在会常驻视图树，收起结束时把页内状态复位，
            // 下次打开不会还停留在歌词页或半开的 sheet。
            guard value <= 0.001 else { return }
            showLyrics = false
            showSleepSheet = false
            showKaraokeSheet = false
            activeSheet = nil
        }
        .onChange(of: player.current?.FileHash) { _ in
            withAnimation(.easeInOut(duration: 0.28)) {
                artworkPalette = []
                artworkImage = nil
            }
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

    private var pageContent: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                // 固定内容区，不把 topBar / 歌词 / 封面控件直接塞进同一个
                // 会随 showLyrics 重排的 VStack。这样底部操作栏不会跟着
                // 歌词切换上下跳，收回歌词时也不会整页重新 layout。
                ZStack {
                    if showLyrics {
                        lyricsContent
                            .transition(.opacity)
                    } else {
                        playerContent
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomActions
            }
            .padding(.top, PlayerWindowInsets.top)
            .padding(.bottom, PlayerWindowInsets.bottom)
            .contentShape(Rectangle())
            .simultaneousGesture(dismissGesture)
            .allowsHitTesting(!isClosing)

            GlassHalfSheet(isPresented: $showSleepSheet, heightRatio: 0.50) {
                SleepTimerSheet(onClose: { showSleepSheet = false }).environmentObject(player)
            }
            .zIndex(20)

            GlassHalfSheet(isPresented: $showKaraokeSheet, heightRatio: 0.60) {
                KaraokeSheet().environmentObject(player)
            }
            .zIndex(21)

            if let toast = player.toast {
                VStack {
                    ToastView(text: toast)
                    Spacer()
                }
                .zIndex(30)
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var playerContent: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(playerPrimary.opacity(0.28))
                .frame(width: 36, height: 5)
                .padding(.top, 4)
                .padding(.bottom, 2)

            topBar

            Spacer(minLength: 10)

            artwork

            Spacer(minLength: 14)

            titleBlock
            progress
                .padding(.horizontal, 28)
                .padding(.top, 14)

            controls
                .padding(.top, 12)

            Spacer(minLength: 4)
        }
    }

    private var lyricsContent: some View {
        VStack(spacing: 0) {
            lyricsTopBar
            lyricView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 封面飞行层：从底栏圆盘里的 44pt 封面飞到自己 318pt 的封面槽位。
    /// 这一段对应 MD3Music 的 PlayerCoverMorph；原播放页封面在 pageContent
    /// 里同步淡入，二者在 p=1 时逐像素重合后本层移除。
    private var isCoverMorphing: Bool {
        visualProgress < 0.999
            && !showLyrics
            && panelOrigin.width > 1
            && coverFrame.width > 1
            && player.current?.coverURL != nil
    }

    @ViewBuilder
    private var coverMorphOverlay: some View {
        if isCoverMorphing, let url = player.current?.coverURL {
            let p = min(max(visualProgress, 0), 1)
            let startSide = max(panelOrigin.width - 12, 20)
            let start = CGRect(
                x: (panelOrigin.width - startSide) / 2,
                y: (panelOrigin.height - startSide) / 2,
                width: startSide,
                height: startSide
            )
            let rect = CGRect(
                x: start.minX + (coverFrame.minX - start.minX) * p,
                y: start.minY + (coverFrame.minY - start.minY) * p,
                width: start.width + (coverFrame.width - start.width) * p,
                height: start.height + (coverFrame.height - start.height) * p
            )
            let radius = 22 + (16 - 22) * p

            CoverImage(
                url: url,
                size: max(rect.width, 1),
                radius: max(radius, 0),
                showsBorder: false
            )
            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 10)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
        }
    }

    private var background: some View {
        GeometryReader { geo in
            ZStack {
                // 底层兜底：封面还没下载完时先用取色渐变，避免黑屏。
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

                // 背景主体：当前专辑图放大到铺满整页；不是取色块，也不是模糊缩略图。
                if let image = artworkImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.20)
                        .clipped()
                        .transition(.opacity)
                }

                // Apple Music 式的原生磨砂：深色下用深色 ultra thin material，
                // 保留专辑图色相；浅色下用浅色 material。加一层极轻的压暗，
                // 保证白色标题/控制按钮在亮色封面上也能读。
                if !isPanelMoving {
                    NativeFrostedGlass(style: colorScheme == .dark ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
                        .frame(width: geo.size.width, height: geo.size.height)
                    Color.black
                        .opacity(colorScheme == .dark ? 0.22 : 0.05)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                }

                if showLyrics && lyricPhotoMode, let url = player.current?.coverURL {
                    CoverImage(url: url, size: max(geo.size.width, geo.size.height), radius: 0, showsBorder: false)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.02)
                }

                // 只负责下载封面、缓存 UIImage 并提取三色，本身不显示。
                if let url = player.current?.coverURL {
                    CoverImage(url: url, size: 2, radius: 0, showsBorder: false) { _, image in
                        guard let image else {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                artworkPalette = []
                                artworkImage = nil
                            }
                            return
                        }
                        withAnimation(.easeInOut(duration: 0.35)) { artworkImage = image }
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
                guard activeSheet == nil, !showSleepSheet, !showKaraokeSheet, !isClosing else { return }
                guard !showLyrics || value.startLocation.y < 100 else { return }
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                guard vertical > 0, vertical > horizontal * 1.25 else { return }
                let collapseDistance = max(UIScreen.main.bounds.height * 0.2, 1)
                let rawProgress = 1 - vertical / collapseDistance
                let progress = max(0, min(1, rawProgress))
                var snapshotDriven = interactiveDismiss

                // 第一次达到有效竖向拖动时，切到静态快照跟手。
                // 失败则保留原来的实时面板路径，功能不会丢。
                if !snapshotDriven, let begin = onInteractiveDismissBegan, begin() {
                    interactiveDismiss = true
                    snapshotDriven = true
                }

                if snapshotDriven {
                    // 传入未夹紧的 progress：拖过 20% 屏幕后整页还能继续跟手。
                    onInteractiveDismissChanged?(rawProgress)
                } else {
                    panelProgress = progress
                }

                if vertical > 110, !didCrossDismissThreshold {
                    didCrossDismissThreshold = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else if vertical < 88 {
                    didCrossDismissThreshold = false
                }
            }
            .onEnded { value in
                guard activeSheet == nil, !showSleepSheet, !showKaraokeSheet, !isClosing else { return }
                didCrossDismissThreshold = false
                guard !showLyrics || value.startLocation.y < 100 else {
                    withAnimation(M3Motion.panelSettle) { panelProgress = 1 }
                    return
                }
                let vertical = value.translation.height
                let horizontal = abs(value.translation.width)
                let predicted = value.predictedEndTranslation.height
                let collapseDistance = max(UIScreen.main.bounds.height * 0.2, 1)
                let progress = max(0, min(1, 1 - vertical / collapseDistance))
                let shouldClose = progress < 0.55
                    || (vertical > 110 && vertical > horizontal && predicted > 120)

                if interactiveDismiss {
                    // 快照已经接管画面；通知 Root 继续把它送到全屏或迷你播放器。
                    isClosing = true
                    onInteractiveDismissEnded?(shouldClose)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                        isClosing = false
                        interactiveDismiss = false
                    }
                    return
                }

                if shouldClose {
                    closePlayer()
                } else {
                    withAnimation(M3Motion.panelSettle) {
                        panelProgress = 1
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

            moreMenu
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
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
        .frame(height: 52)
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
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: PlayerCoverFramePreferenceKey.self,
                            value: proxy.frame(in: .named("playerPage"))
                        )
                        .preference(
                            key: PlayerArtworkGlobalFrameKey.self,
                            value: proxy.frame(in: .global)
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.10),
                    radius: 16, x: 0, y: 8)
            .padding(.horizontal, 24)
            .opacity(isCoverMorphing ? 0 : 1)
            // 封面不再接收切歌/双击手势，让播放页的系统的下拉收出手势覆盖整张封面。
            .allowsHitTesting(false)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(player.current?.SongName ?? "未在播放")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(playerPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let artist = player.current?.artist, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(playerSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Capsule()
                        .fill(playerPrimary.opacity(colorScheme == .dark ? 0.22 : 0.16))
                        .frame(height: 2.5)
                    Capsule()
                        .fill(playerPrimary.opacity(0.92))
                        .frame(width: width * ratio, height: 2.5)
                    Circle()
                        .fill(playerPrimary)
                        .frame(width: 9, height: 9)
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

        }
        // 进度本身 0.25 秒刷新一次；再叠一层 0.25 秒动画会让播放页持续重绘。
        .animation(nil, value: displayedTime)
    }

    private var controls: some View {
        HStack(spacing: 44) {
            Spacer(minLength: 0)

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26, weight: .semibold))
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
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundColor(playerPrimary)
                                .opacity(player.isPlaying ? 1 : 0)
                                .scaleEffect(player.isPlaying ? 1 : 0.86)
                            Image(systemName: "play.fill")
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundColor(playerPrimary)
                                .opacity(player.isPlaying ? 0 : 1)
                                .scaleEffect(player.isPlaying ? 0.86 : 1)
                        }
                        .frame(width: 56, height: 56)
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
                    .font(.system(size: 26, weight: .semibold))
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
                showLyrics.toggle()
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
        .padding(.horizontal, 28)
        .padding(.top, 4)
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
                            let active = index == player.lyricIndex
                            VStack(alignment: .leading, spacing: 5) {
                                Group {
                                    if active, !line.words.isEmpty, player.isPlaying, !isPanelMoving {
                                        TimelineView(.periodic(from: .now, by: 0.08)) { context in
                                            lyricText(line, active: true, timeOverride: lyricClock(context.date))
                                        }
                                    } else {
                                        lyricText(line, active: active)
                                    }
                                }
                                // 活动行不再放大字号：字号一变整段歌词会重排，视觉上就是“突然跳一下”。
                                // 用固定字号 + 轻微字重/透明度过渡，滚动只由 ScrollViewReader 负责。
                                .transition(.identity)
                                .font(.system(size: lyricSize.fontSize, weight: active ? .semibold : .medium))
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
                            // 非当前行整行做模糊；活动行保持完全清晰。
                            // 这里不能给 active 加 opacity 动画：旧行淡出 + 新行淡入
                            // 会在滚动动画期间同时留下两份半透明歌词，看起来就是“虚影”。
                            .compositingGroup()
                            .blur(radius: (active || isPanelMoving) ? 0 : 2.0)
                            .opacity(active ? 1 : (isPanelMoving ? 0.72 : 0.58))
                            .animation(nil, value: active)
                            .animation(nil, value: isPanelMoving)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.seek(to: max(0, line.time - Double(player.lyricOffsetMs) / 1000))
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 26)
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
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onChange(of: lyricAutoFollow) { enabled in
                guard enabled else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
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
        guard !isClosing else { return }
        isClosing = true

        // Root 持有 PlayerPanelFrame：收起动画 = progress 1→0，
        // 窗口缩回底栏圆盘、封面飞回，播放页自身不再做整页下滑。
        if let onClose = onClose {
            onClose()
            return
        }

        withAnimation(M3Motion.panelCollapse) {
            panelProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
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

    private var modeTitle: String {
        switch player.karaokeMode {
        case .dualTrack: return "官方双轨"
        case .centerChannel: return "兼容模式（非 AI）"
        case .aiModel: return "AI 本地分离"
        case .unavailable: return player.karaokeEnabled ? "正在准备分离资源" : "未开启"
        }
    }

    private var modeDetail: String {
        switch player.karaokeMode {
        case .dualTrack:
            return "已取到官方人声/伴奏双轨，可独立调节两条音轨音量。"
        case .centerChannel:
            return "没有走 AI：官方双轨和本地模型都不可用，实际用立体声中置声道估计；鼓点和居中低频会明显保留。"
        case .aiModel:
            return "本地 4.9MB MSS 模型，完全离线；轻量模型做不到 Demucs 级，纯人声偶尔会残留少量鼓点/齿音。"
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
        HStack {
            Spacer()
            Text("伴唱 / 分离")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.text)
            Spacer()
        }
        .frame(height: 44)
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
            if player.karaokeMode == .aiModel {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text("AI 运行状态：\(AudioEnhancer.shared.aiStatusText())")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
