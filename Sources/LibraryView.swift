import SwiftUI

@MainActor
final class RecommendModel: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    func load(force: Bool = false) async {
        if !force, !songs.isEmpty { return }
        isLoading = true
        message = nil
        do {
            let list = try await KGService.recommend()
            songs = list
            isLoading = false
            if list.isEmpty { message = "今天还没有推荐，登录后再试" }
        } catch {
            isLoading = false
            if songs.isEmpty {
                message = (error as? LocalizedError)?.errorDescription ?? "推荐加载失败"
            }
        }
    }
}

struct RecommendView: View {
    @ObservedObject var model: RecommendModel
    @ObservedObject var searchModel: SearchModel
    @ObservedObject private var library = LibraryStore.shared
    @Binding var isSearching: Bool
    let onSelect: (Song, [Song]) -> Void
    let onSelectSearch: (Song) -> Void
    let onOpenPlayer: () -> Void

    @State private var ranks: [RankItem] = []
    @State private var sheetTarget: DiscoverSheet?
    @FocusState private var searchFocused: Bool
    @State private var historyWords: [String] = Preferences.searchHistory
    @State private var hotKeywords: [String] = []

    private static let todayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private var todayLabel: String {
        // DateFormatter 创建成本很高；之前每次 body 重算都 new 一个，
        // 搜索输入/收藏变化时首页会跟着卡。这里复用同一个 formatter。
        Self.todayFormatter.string(from: Date())
    }

    /// 从每日推荐歌曲里提取真实专辑：按 AlbumID 去重，只保留有专辑名的条目。
    private var recommendedAlbums: [AlbumRecommendation] {
        var seen = Set<Int>()
        var albums: [AlbumRecommendation] = []
        for song in model.songs {
            guard let albumID = song.AlbumID, albumID > 0 else { continue }
            let name = (song.AlbumName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(albumID) else { continue }
            seen.insert(albumID)
            albums.append(AlbumRecommendation(id: albumID,
                                              name: name,
                                              artist: song.artist,
                                              coverURL: song.coverURL))
        }
        return Array(albums.prefix(7))
    }

    /// 本地最近播放去重成专辑，做首页「最近播放」横向卡片。
    private var recentAlbums: [AlbumRecommendation] {
        var seen = Set<Int>()
        var albums: [AlbumRecommendation] = []
        for song in library.recent {
            guard let albumID = song.AlbumID, albumID > 0 else { continue }
            let name = (song.AlbumName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(albumID) else { continue }
            seen.insert(albumID)
            albums.append(AlbumRecommendation(id: albumID,
                                              name: name,
                                              artist: song.artist,
                                              coverURL: song.coverURL))
        }
        return Array(albums.prefix(6))
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                searchBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
                searchBody
                    .transition(.opacity)
            } else {
                discoverBody
                    .transition(.opacity)
            }
        }
        .background(AppBackground())
        .gradientNavigationBlur()
        .animation(Motion.standard, value: isSearching)
        .task {
            historyWords = Preferences.searchHistory
            if hotKeywords.isEmpty {
                hotKeywords = (try? await KGService.hotSearch()) ?? []
            }
            await LibraryStore.shared.enrichMissingCovers()
            if ranks.isEmpty { ranks = (try? await KGService.ranks()) ?? [] }
        }
        .onChange(of: searchModel.query) { _ in
            searchModel.schedule()
        }
        .onChange(of: isSearching) { value in
            if value {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    searchFocused = true
                }
            } else {
                searchFocused = false
            }
        }
        .fullScreenCover(item: $sheetTarget) { target in
            switch target {
            case .playlist(let playlist):
                PlaylistDetailSheet(playlist: playlist) { song, list in
                    sheetTarget = nil
                    onSelect(song, list)
                    onOpenPlayer()
                }
            case .rank(let rank):
                RankDetailSheet(rank: rank) { song, list in
                    sheetTarget = nil
                    onSelect(song, list)
                    onOpenPlayer()
                }
            case .album(let album):
                AlbumDetailSheet(target: album)
                    .environmentObject(PlayerEngine.shared)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                TextField("搜索歌曲、歌手", text: $searchModel.query)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchModel.submit() }
                if !searchModel.query.isEmpty {
                    Button {
                        searchModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .appSearchField(cornerRadius: 10)

            if searchFocused {
                Button {
                    searchFocused = false
                    searchModel.query = ""
                    historyWords = Preferences.searchHistory
                } label: {
                    Text("取消")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .frame(height: 38)
                }
                .buttonStyle(GlassPressButtonStyle())
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .animation(Motion.quick, value: searchFocused)
    }

    private var discoverBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                if let message = model.message, model.songs.isEmpty {
                    Text(message)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, IOS27.pagePadding)
                        .padding(.top, 24)
                }

                if !recommendedAlbums.isEmpty {
                    IOS27SectionHeader(title: "为你精选", subtitle: "Made for You")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(Array(recommendedAlbums.enumerated()), id: \.offset) { index, album in
                                AppleMusicAlbumCard(album: album, featured: index == 0) {
                                    sheetTarget = .album(AlbumTarget(id: album.id,
                                                                     name: album.name,
                                                                     cover: album.coverURL,
                                                                     artist: album.artist))
                                }
                            }
                        }
                        .padding(.horizontal, IOS27.pagePadding)
                        .padding(.bottom, 4)
                    }
                }

                if !recentAlbums.isEmpty {
                    IOS27SectionHeader(title: "最近播放", subtitle: "Recently Played", showsChevron: true)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(recentAlbums) { album in
                                RecentAlbumCard(album: album) {
                                    sheetTarget = .album(AlbumTarget(id: album.id,
                                                                     name: album.name,
                                                                     cover: album.coverURL,
                                                                     artist: album.artist))
                                }
                            }
                        }
                        .padding(.horizontal, IOS27.pagePadding)
                        .padding(.bottom, 4)
                    }
                }

                if !ranks.isEmpty {
                    IOS27SectionHeader(title: "排行榜", subtitle: nil)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ranks.prefix(8)) { rank in
                                Button { sheetTarget = .rank(rank) } label: {
                                    RankCard(rank: rank)
                                }
                                .buttonStyle(IOS27PressStyle(pressedOpacity: 0.62, pressedScale: 0.97))
                            }
                        }
                        .padding(.horizontal, IOS27.pagePadding)
                        .padding(.bottom, 4)
                    }
                }

                if !model.songs.isEmpty {
                    dailyRecommendations
                }
            }
            .padding(.bottom, 170)
            .chromeScrollTracking()
            .animation(Motion.standard, value: model.songs.count)
            .animation(Motion.standard, value: ranks.count)
        }
        .coordinateSpace(name: ChromeScrollSpace.name)
        .refreshable {
            await model.load(force: true)
            await LibraryStore.shared.enrichMissingCovers()
            ranks = (try? await KGService.ranks()) ?? ranks
        }
    }

    private var dailyRecommendations: some View {
        VStack(alignment: .leading, spacing: 0) {
            IOS27SectionHeader(
                title: "每日推荐",
                subtitle: "\(model.songs.count) 首",
                actionTitle: "播放全部"
            ) {
                guard let first = model.songs.first else { return }
                onSelect(first, model.songs)
            }

            VStack(spacing: 0) {
                ForEach(Array(model.songs.enumerated()), id: \.element.recommendRowID) { index, song in
                    SongRowWithMenu(song: song) {
                        onSelect(song, model.songs)
                    }
                    .padding(.horizontal, IOS27.pagePadding)

                    if index < model.songs.count - 1 {
                        IOS27RowDivider()
                            .padding(.trailing, IOS27.pagePadding)
                    }
                }
            }
        }
    }

    private var dailyHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("每日推荐")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)

            Text("\(model.songs.count) 首")
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)

            Spacer(minLength: 8)

            if let first = model.songs.first {
                Button {
                    onSelect(first, model.songs)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("播放全部")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(Theme.accent)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    private var searchBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchHistory
                }

                if searchModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                }

                if let message = searchModel.message {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                }

                if !searchModel.songs.isEmpty {
                    Text("歌曲")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 2)
                }

                ForEach(searchModel.songs) { song in
                    SongRowWithMenu(song: song) {
                        searchFocused = false
                        onSelectSearch(song)
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if searchModel.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else if searchModel.hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { searchModel.loadMore() }
                }
            }
            .padding(.bottom, 178)
            .chromeScrollTracking()
            .animation(Motion.standard, value: searchModel.songs.count)
        }
        .coordinateSpace(name: ChromeScrollSpace.name)
    }

    private var searchHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("最近搜索")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    if !historyWords.isEmpty {
                        Button {
                            Preferences.searchHistory = []
                            historyWords = []
                            searchModel.query = ""
                        } label: {
                            Text("清除")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.accent)
                                .frame(height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(GlassPressButtonStyle())
                    }
                }

                if historyWords.isEmpty {
                    Text("搜歌手、歌名或专辑，点一首就能听")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .appSurface(cornerRadius: 18)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(historyWords.enumerated()), id: \.element) { index, word in
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .font(.system(size: 14))
                                    .foregroundColor(Theme.tertiaryText)
                                    .frame(width: 18)

                                Button {
                                    searchModel.submit(word)
                                } label: {
                                    Text(word)
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(GlassPressButtonStyle())

                                Button {
                                    Preferences.removeSearch(word)
                                    historyWords = Preferences.searchHistory
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Theme.tertiaryText)
                                        .frame(width: 30, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(GlassPressButtonStyle())
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)

                            if index < historyWords.count - 1 {
                                Divider()
                                    .background(Theme.separator)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                    .appSurface(cornerRadius: 18)
                }
            }

            if !hotKeywords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("热门搜索")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.text)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        alignment: .leading,
                        spacing: 0
                    ) {
                        ForEach(Array(hotKeywords.prefix(10).enumerated()), id: \.element) { index, word in
                            Button {
                                searchModel.submit(word)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundColor(index < 3 ? Theme.accent : Theme.tertiaryText)
                                        .frame(width: 16, alignment: .leading)
                                    Text(word)
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: 40)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(GlassPressButtonStyle())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                    .appSurface(cornerRadius: 18)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

}

enum LibraryKind: String, Identifiable {
    case favorites
    case recent

    var id: String { rawValue }
    var title: String { self == .favorites ? "我喜欢" : "最近播放" }
}

enum DiscoverSheet: Identifiable {
    case playlist(CloudPlaylist)
    case rank(RankItem)
    case album(AlbumTarget)

    var id: String {
        switch self {
        case .playlist(let playlist): return "playlist-\(playlist.id)"
        case .rank(let rank): return "rank-\(rank.id)"
        case .album(let album): return "album-\(album.id)"
        }
    }
}

struct RankCard: View {
    let rank: RankItem

    private let side: CGFloat = 158

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.chip)
                if let url = rank.cover.flatMap(URL.init(string:)) {
                    CoverImage(url: url, size: side, radius: 8, showsBorder: false,
                               placeholderSymbol: "chart.bar.fill")
                        .frame(width: side, height: side)
                        .clipped()
                } else {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: side, height: side)
                }

                Text("TOP")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .padding(7)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.text.opacity(0.08), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(rank.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text("酷狗排行榜")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: side, alignment: .leading)
        }
    }
}

/// 歌单/排行榜共用的全幅头图：上方清晰封面，向下逐渐变成模糊封面，
/// 最后过渡到当前主题的底色（深色为黑、浅色为白），不再叠黑色蒙层。
struct CollectionHero: View {
    let coverURL: URL?
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack {
                CoverImage(url: coverURL, size: max(width, height), radius: 0, showsBorder: false)
                    .frame(width: width, height: height)
                    .scaleEffect(1.12)
                    .blur(radius: 18)
                    .clipped()

                CoverImage(url: coverURL, size: max(width, height), radius: 0, showsBorder: false)
                    .frame(width: width, height: height)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: 0.38),
                                .init(color: .clear, location: 0.84)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipped()

                // 只在标题区域下面压一层很薄的底色保证文字可读，图片仍然铺到歌曲列表上沿。
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.46),
                        .init(color: Theme.background.opacity(0.10), location: 0.62),
                        .init(color: Theme.background.opacity(0.42), location: 0.80),
                        .init(color: Theme.background.opacity(0.72), location: 0.94),
                        .init(color: Theme.background, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: width, height: height)
            .clipped()
            .compositingGroup()
            // 头图是静态的，把双层封面 + blur 一次性栅格化，
            // 列表滚动时不再逐帧重算离屏模糊。
            .drawingGroup()
        }
        .frame(height: height)
    }
}

struct RankDetailSheet: View {
    let rank: RankItem
    let onSelect: (Song, [Song]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var hasMore = true
    @State private var page = 1
    @State private var message = ""

    private var coverURL: URL? {
        rank.cover.flatMap(URL.init(string:))
    }

    private var headerHeight: CGFloat {
        min(max(UIScreen.main.bounds.height * 0.49, 370), 440)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    CollectionHero(coverURL: coverURL, height: headerHeight)
                    info
                }
                .frame(height: headerHeight)

                Rectangle()
                    .fill(Theme.separator.opacity(0.62))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)

                if loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        .padding(.top, 26)
                } else if !message.isEmpty && songs.isEmpty {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.top, 24)
                } else if !songs.isEmpty {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                Button {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                        onSelect(song, songs)
                                    }
                                } label: {
                                    SongRow(song: song, showsMore: false)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(AppleMusicListRowButtonStyle())
                                SongMoreMenu(song: song)
                            }
                            .padding(.horizontal, 14)

                            if index < songs.count - 1 {
                                Rectangle()
                                    .fill(Theme.separator.opacity(0.42))
                                    .frame(height: 0.5)
                                    .padding(.leading, 76)
                                    .padding(.trailing, 14)
                            }
                        }
                    }

                    if hasMore {
                        HStack(spacing: 6) {
                            if loadingMore {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                            }
                            Text(loadingMore ? "正在加载…" : "继续上滑自动加载")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .onAppear {
                            guard !loadingMore else { return }
                            Task { await loadMore() }
                        }
                    } else if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .liquidGlass(cornerRadius: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel("关闭排行榜")
        }
        .task { await loadMore() }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(rank.name)
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            if !rank.intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(rank.intro)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }

            HStack(spacing: 6) {
                Text("酷狗排行榜")
                if !songs.isEmpty {
                    Text("·")
                    Text("\(songs.count) 首")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.secondaryText)

            HStack(spacing: 10) {
                Button {
                    guard let first = songs.first else { return }
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        onSelect(first, songs)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text("播放")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
                    .frame(width: 132, height: 44)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(songs.isEmpty)
                .opacity(songs.isEmpty ? 0.48 : 1)

                Button {
                    guard !songs.isEmpty else { return }
                    let shuffled = songs.shuffled()
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        if let first = shuffled.first { onSelect(first, shuffled) }
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .frame(width: 48, height: 44)
                        .liquidGlass(cornerRadius: 22)
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(songs.isEmpty)
                .opacity(songs.isEmpty ? 0.48 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    private func loadMore() async {
        guard !loadingMore else { return }
        loadingMore = true
        if page == 1 { message = "" }
        do {
            let newSongs = try await KGService.rankSongs(rankid: rank.id, page: page, pageSize: 30)
            if page == 1 {
                songs = newSongs
            } else {
                let existing = Set(songs.map { $0.FileHash })
                songs.append(contentsOf: newSongs.filter { !existing.contains($0.FileHash) })
            }
            hasMore = newSongs.count >= 30
            page += 1
            loading = false
            loadingMore = false
            if songs.isEmpty { message = "榜单暂时没有内容" }
        } catch {
            loading = false
            loadingMore = false
            if songs.isEmpty {
                message = (error as? LocalizedError)?.errorDescription ?? "榜单加载失败"
            }
        }
    }
}

struct PlaylistCard: View {
    let playlist: CloudPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chip)
                if let url = playlist.cover.flatMap(URL.init(string:)) {
                    CoverImage(url: url, size: 148, radius: 9, showsBorder: false,
                               placeholderSymbol: "music.note.list")
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .frame(width: 148, height: 148)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )

            Text(playlist.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .frame(width: 148, alignment: .leading)
            Text(playlist.isCollected ? "收藏 · \(playlist.count) 首" : "\(playlist.count) 首")
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 148, alignment: .leading)
        }
    }
}

struct PlaylistDetailSheet: View {
    let playlist: CloudPlaylist
    let onSelect: (Song, [Song]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var message = ""
    @State private var page = 1
    @State private var hasMore = true
    @State private var isSelecting = false
    @State private var selectedHashes = Set<String>()
    @State private var showTargetPicker = false
    @State private var adding = false
    @State private var toast = ""
    @State private var actionSong: Song?
    @State private var showActionMenu = false

    private var selectedSongs: [Song] {
        songs.filter { selectedHashes.contains($0.id) }
    }

    private var coverURL: URL? {
        playlist.cover.flatMap(URL.init(string:))
    }

    private var headerHeight: CGFloat {
        min(max(UIScreen.main.bounds.height * 0.49, 370), 440)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    CollectionHero(coverURL: coverURL, height: headerHeight)
                    info
                }
                .frame(height: headerHeight)

                Rectangle()
                    .fill(Theme.separator.opacity(0.62))
                    .frame(height: 0.5)
                    .padding(.horizontal, 16)

                if loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        .padding(.top, 26)
                } else if !message.isEmpty && songs.isEmpty {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.top, 24)
                } else if !songs.isEmpty {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        VStack(spacing: 0) {
                            HStack(spacing: 8) {
                                if isSelecting {
                                    Button {
                                        toggle(song)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: selectedHashes.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(selectedHashes.contains(song.id) ? Theme.accent : Theme.secondaryText)
                                                .frame(width: 22)
                                            SongRow(song: song, showsMore: false)
                                        }
                                    }
                                    .buttonStyle(AppleMusicListRowButtonStyle())
                                } else {
                                    Button {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                            onSelect(song, songs)
                                        }
                                    } label: {
                                        SongRow(song: song, showsMore: false)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(AppleMusicListRowButtonStyle())
                                    Button {
                                        actionSong = song
                                        showActionMenu = true
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(Theme.tertiaryText)
                                            .frame(width: 34, height: 34)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(AppleMusicPressStyle())
                                    .accessibilityLabel("歌曲操作")
                                }
                            }
                            .padding(.horizontal, 14)

                            if index < songs.count - 1 {
                                Rectangle()
                                    .fill(Theme.separator.opacity(0.42))
                                    .frame(height: 0.5)
                                    .padding(.leading, 76)
                                    .padding(.trailing, 14)
                            }
                        }
                    }

                    if !loading && !songs.isEmpty && hasMore {
                        HStack(spacing: 6) {
                            if loadingMore {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                            }
                            Text(loadingMore ? "正在加载…" : "继续上滑自动加载")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .id("playlist-more-\(songs.count)")
                        .onAppear {
                            guard !loadingMore else { return }
                            Task { await loadMore() }
                        }
                    } else if !loading && !message.isEmpty && !songs.isEmpty {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
            .padding(.bottom, isSelecting ? 12 : 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting {
                batchBar
            }
        }
        .background(AppBackground())
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .liquidGlass(cornerRadius: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel("关闭歌单")
        }
        .task { await loadMore() }
        .sheet(isPresented: $showTargetPicker) {
            PlaylistTargetPicker { target in
                Task { await addSelected(to: target) }
            }
        }
        .confirmationDialog("歌曲操作", isPresented: $showActionMenu, titleVisibility: .hidden) {
            if let song = actionSong {
                Button("下一首播放") {
                    PlayerEngine.shared.playNext(song)
                }
                Button("加入播放列表末尾") {
                    PlayerEngine.shared.appendToQueue(song)
                }
                Button(LibraryStore.shared.isFavorite(song) ? "取消我喜欢" : "我喜欢") {
                    Task {
                        let added = await LibraryStore.shared.toggleFavorite(song)
                        if let added = added {
                            PlayerEngine.shared.showToast(added ? "已加入我喜欢" : "已从我喜欢移除")
                        } else {
                            PlayerEngine.shared.showToast(LibraryStore.shared.favoritesMessage)
                        }
                    }
                }
                Button("复制歌名和歌手") {
                    UIPasteboard.general.string = "\(song.SongName) - \(song.artist)"
                    PlayerEngine.shared.showToast("已复制歌曲信息")
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(playlist.name)
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(playlist.isCollected ? "收藏歌单" : "歌单")
                Text("·")
                Text("\(playlist.count) 首")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.secondaryText)

            HStack(spacing: 10) {
                Button {
                    guard let first = songs.first else { return }
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        onSelect(first, songs)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text("播放")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
                    .frame(width: 132, height: 44)
                    .background(Theme.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(songs.isEmpty)
                .opacity(songs.isEmpty ? 0.48 : 1)

                Button {
                    guard !songs.isEmpty else { return }
                    let shuffled = songs.shuffled()
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                        if let first = shuffled.first { onSelect(first, shuffled) }
                    }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .frame(width: 48, height: 44)
                        .liquidGlass(cornerRadius: 22)
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(songs.isEmpty)
                .opacity(songs.isEmpty ? 0.48 : 1)

                Button {
                    withAnimation(Motion.quick) {
                        isSelecting.toggle()
                        selectedHashes.removeAll()
                    }
                } label: {
                    Text(isSelecting ? "取消批量" : "批量加入")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelecting ? Theme.accent : Theme.text)
                        .frame(width: 96, height: 44)
                        .liquidGlass(cornerRadius: 22)
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(songs.isEmpty)
                .opacity(songs.isEmpty ? 0.48 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }
    private var batchBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(selectedSongs.count) 首")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.text)
            Spacer()
            Button {
                showTargetPicker = true
            } label: {
                HStack(spacing: 4) {
                    if adding { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.onAccent)) }
                    Text(adding ? "加入中…" : "加入歌单")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Theme.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(selectedHashes.isEmpty ? Theme.secondaryText.opacity(0.35) : Theme.accent)
                .cornerRadius(12)
            }
            .buttonStyle(GlassPressButtonStyle())
            .disabled(selectedHashes.isEmpty || adding)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.card)
        .overlay(Rectangle().fill(Theme.separator.opacity(0.72)).frame(height: 0.5), alignment: .top)
    }

    private func toggle(_ song: Song) {
        if selectedHashes.contains(song.id) {
            selectedHashes.remove(song.id)
        } else {
            selectedHashes.insert(song.id)
        }
    }

    private func addSelected(to target: CloudPlaylist) async {
        let picked = selectedSongs
        guard !picked.isEmpty else { return }
        adding = true
        do {
            try await KGService.addSongs(picked, to: target)
            toast = "已加入「\(target.name)」"
            isSelecting = false
            selectedHashes.removeAll()
            Task {
                try? await Task.sleep(nanoseconds: 1600000000)
                if toast == "已加入「\(target.name)」" { toast = "" }
            }
        } catch {
            toast = (error as? LocalizedError)?.errorDescription ?? "加入歌单失败"
        }
        adding = false
    }

    private func loadMore() async {
        guard !loadingMore else { return }
        loadingMore = true
        if page == 1 { message = "" }
        do {
            let previousCount = songs.count
            // 云歌单接口单页最多 300 首。大多数歌单一次就能取完，
            // 用户不用滚到底等第二页；超过 300 首才继续自动翻页。
            let newSongs = try await KGService.playlistSongsNewestFirst(playlist: playlist, page: page, pageSize: 300)
            if page == 1 {
                songs = newSongs
            } else {
                let existing = Set(songs.map { $0.id })
                songs.append(contentsOf: newSongs.filter { !existing.contains($0.id) })
            }
            // 接口总数不准或翻页重复时，只要这一页没有新增就立刻停下，
            // 避免底部自动加载陷入死循环。
            if newSongs.isEmpty || songs.count == previousCount {
                hasMore = false
            } else if playlist.count > 0 {
                hasMore = songs.count < playlist.count
            } else {
                hasMore = newSongs.count >= 300
            }
            page += 1
            loading = false
            loadingMore = false
            if songs.isEmpty { message = "这个歌单是空的，或者没有读取权限" }
        } catch {
            loading = false
            loadingMore = false
            if songs.isEmpty {
                message = (error as? LocalizedError)?.errorDescription ?? "歌单加载失败"
            }
        }
    }
}

struct PlaylistTargetPicker: View {
    let onPick: (CloudPlaylist) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var playlists: [CloudPlaylist] = []
    @State private var loading = true
    @State private var message = ""

    var body: some View {
        NavigationView {
            List {
                if loading {
                    HStack(spacing: 8) {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        Text("读取歌单…").font(.system(size: 13)).foregroundColor(Theme.secondaryText)
                    }
                    .listRowBackground(Color.clear)
                } else if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .listRowBackground(Color.clear)
                } else if playlists.isEmpty {
                    Text("没有可写入的自建歌单，先在酷狗创建或取消收藏后再试")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(playlists) { playlist in
                        Button {
                            dismiss()
                            onPick(playlist)
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: playlist.cover.flatMap(URL.init(string:)), size: 52, radius: 9)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    Text("\(playlist.count) 首")
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.tertiaryText)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(AppleMusicListRowButtonStyle())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .background(AppBackground())
            .navigationTitle("选择播放列表")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } }
            }
            .task { await load() }
        }
        .navigationViewStyle(.stack)
    }

    private func load() async {
        loading = true
        message = ""
        do {
            let all = try await KGService.playlists()
            playlists = all.filter { !$0.isCollected && $0.listid != nil }
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? "歌单读取失败"
        }
        loading = false
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .frame(height: 32)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 10)
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var importedStore = ImportedPlaylistStore.shared
    @ObservedObject private var userProfile = UserProfileStore.shared
    private var player: PlayerEngine { PlayerEngine.shared }
    var onOpenPlayer: () -> Void = {}
    @State private var quality: AudioQuality = Preferences.quality
    @State private var showLogin = false
    @State private var showSettings = false
    @State private var showArtists = false
    @State private var vipText = ""
    @State private var playlists: [CloudPlaylist] = []
    @State private var playlistsLoading = false
    @State private var playlistsMessage = ""
    @State private var selectedPlaylist: CloudPlaylist?
    @State private var selectedImported: ImportedPlaylist?
    @State private var libraryTarget: LibraryKind?
    @State private var libraryScrollTarget: String?
    @State private var albumTarget: AlbumTarget?
    @State private var showImport = false
    @State private var toast = ""
    @State private var sleepText = ""
    @State private var customMinutes = 45
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !auth.isLoggedIn {
                        loginBanner
                    }

                    libraryAlbumSection
                        .id("library-albums")

                    libraryIndexRows

                    playlistsSection
                        .id("library-playlists")
                }
                .padding(.bottom, 176)
                .chromeScrollTracking()
            }
            .coordinateSpace(name: ChromeScrollSpace.name)
            .onChange(of: libraryScrollTarget) { target in
                guard let target else { return }
                withAnimation(Motion.standard) {
                    proxy.scrollTo(target, anchor: .top)
                }
                libraryScrollTarget = nil
            }
        }
        .background(AppBackground())
        .gradientNavigationBlur()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    UserAvatarView(url: userProfile.profile.flatMap { $0.avatarURL }.flatMap(URL.init(string:)),
                                   size: 30,
                                   borderWidth: 0.6)
                        .overlay(alignment: .bottomTrailing) {
                            if !auth.isLoggedIn {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(IOS27.accent)
                                    .background(Circle().fill(Theme.background).frame(width: 10, height: 10))
                            }
                        }
                }
                .buttonStyle(IOS27PressStyle(pressedOpacity: 0.55, pressedScale: 0.95))
                .accessibilityLabel("账户与设置")
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(player).environmentObject(auth)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(player)
                .environmentObject(auth)
        }
        .sheet(isPresented: $showImport) {
            PlaylistImportView()
        }
        .fullScreenCover(isPresented: $showArtists) {
            LibraryArtistsView()
        }
        .fullScreenCover(item: $libraryTarget) { kind in
            LibrarySongsView(kind: kind)
        }
        .fullScreenCover(item: $albumTarget) { album in
            AlbumDetailSheet(target: album)
                .environmentObject(player)
        }
        .fullScreenCover(item: $selectedPlaylist) { playlist in
            PlaylistDetailSheet(playlist: playlist) { song, list in
                selectedPlaylist = nil
                player.play(song, in: list)
                onOpenPlayer()
            }
        }
        .fullScreenCover(item: $selectedImported) { playlist in
            ImportedPlaylistDetailSheet(playlist: playlist) { song, list in
                selectedImported = nil
                player.play(song, in: list)
                onOpenPlayer()
            }
        }
        .overlay(alignment: .top) {
            if !toast.isEmpty { ToastView(text: toast) }
        }
        .task {
            await loadProfile()
            await loadPlaylists()
        }
        .onChange(of: auth.isLoggedIn) { _ in
            Task {
                await loadProfile()
                await loadPlaylists()
            }
        }
    }

    private func loadPlaylists() async {
        guard auth.isLoggedIn else {
            playlists = []
            playlistsMessage = ""
            return
        }
        guard !playlistsLoading else { return }
        playlistsLoading = true
        playlistsMessage = ""
        defer { playlistsLoading = false }
        do {
            let loaded = try await KGService.playlists()
            // 资料库不再展示「我喜欢」入口，云歌单里同名的旧收藏项也一并过滤，
            // 避免删了行之后下面又出现一个「我喜欢」卡片。
            playlists = loaded.filter { $0.name != "我喜欢" }
            if playlists.isEmpty { playlistsMessage = "官方账号里没有读到歌单" }
        } catch {
            playlistsMessage = (error as? LocalizedError)?.errorDescription ?? "歌单同步失败"
        }
    }

    private var libraryAlbums: [AlbumTarget] {
        var seen = Set<Int>()
        var albums: [AlbumTarget] = []
        for song in library.recent + library.favorites {
            guard let id = song.AlbumID, id > 0 else { continue }
            let name = (song.AlbumName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(id).inserted else { continue }
            albums.append(AlbumTarget(id: id,
                                      name: name,
                                      cover: song.coverURL,
                                      artist: song.artist))
        }
        return Array(albums.prefix(6))
    }

    private var artistGroups: [LibraryArtistGroup] {
        var groups: [String: LibraryArtistGroup] = [:]
        for song in library.favorites + library.recent {
            let name = song.artist
            guard !name.isEmpty else { continue }
            if var existing = groups[name] {
                existing.count += 1
                if existing.cover == nil { existing.cover = song.coverURL }
                groups[name] = existing
            } else {
                groups[name] = LibraryArtistGroup(name: name,
                                                  count: 1,
                                                  cover: song.coverURL,
                                                  authorID: song.AuthorID)
            }
        }
        return groups.values.sorted { $0.count > $1.count }
    }

    private var libraryIndexRows: some View {
        IOS27PlainGroup {
            libraryIndexRow(icon: "music.note.list",
                            title: "播放列表",
                            count: playlists.count + importedStore.playlists.count) {
                libraryScrollTarget = "library-playlists"
            }
            IOS27RowDivider(leading: 46)
            libraryIndexRow(icon: "music.mic",
                            title: "歌手",
                            count: artistGroups.count) {
                showArtists = true
            }
            IOS27RowDivider(leading: 46)
            libraryIndexRow(icon: "square.stack",
                            title: "专辑",
                            count: libraryAlbums.count) {
                libraryScrollTarget = "library-albums"
            }
            IOS27RowDivider(leading: 46)
            libraryIndexRow(icon: "music.note",
                            title: "歌曲",
                            count: library.favorites.count) {
                libraryTarget = .favorites
            }
            IOS27RowDivider(leading: 46)
            libraryIndexRow(icon: "arrow.down.circle",
                            title: "下载",
                            count: importedStore.playlists.count) {
                libraryScrollTarget = "library-playlists"
            }
        }
    }

    private func libraryIndexRow(icon: String,
                                 title: String,
                                 count: Int,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IOS27IndexIcon(systemName: icon, size: 19)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Theme.secondaryText)
                IOS27Chevron()
            }
            .padding(.horizontal, IOS27.pagePadding)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(IOS27RowButtonStyle())
    }

    @ViewBuilder
    private var libraryAlbumSection: some View {
        if !libraryAlbums.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                IOS27SectionHeader(title: "置顶收藏", subtitle: "专辑")

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(libraryAlbums) { album in
                        Button {
                            albumTarget = album
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.chip)
                                CoverImage(url: album.cover, size: 140, radius: 7, showsBorder: false)
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Theme.text.opacity(0.08), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(IOS27PressStyle(pressedOpacity: 0.62, pressedScale: 0.97))
                        .accessibilityLabel(album.name)
                    }
                }
                .padding(.horizontal, IOS27.pagePadding)
                .padding(.bottom, 18)
            }
        }
    }

    private var loginBanner: some View {
        Button { showLogin = true } label: {
            HStack(spacing: 13) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(Theme.text)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("登录酷狗账号")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("同步云歌单、头像与会员状态")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                IOS27Chevron()
            }
            .padding(.horizontal, IOS27.pagePadding)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(IOS27RowButtonStyle())
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("播放列表")
                    .font(IOS27.sectionTitle)
                    .tracking(IOS27.sectionTracking)
                    .foregroundColor(Theme.text)
                Text("\(playlists.count + importedStore.playlists.count)")
                    .font(IOS27.caption)
                    .foregroundColor(Theme.secondaryText)
                Spacer()
                Menu {
                    Button { showImport = true } label: {
                        Label("导入外部歌单", systemImage: "square.and.arrow.down")
                    }
                    if auth.isLoggedIn {
                        Button { Task { await loadPlaylists() } } label: {
                            Label(playlistsLoading ? "正在同步…" : "同步云歌单", systemImage: "arrow.clockwise")
                        }
                        .disabled(playlistsLoading)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(Theme.text)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IOS27PressStyle(pressedOpacity: 0.45, pressedScale: 0.95))
            }
            .padding(.horizontal, IOS27.pagePadding)
            .padding(.top, IOS27.sectionSpacing)
            .padding(.bottom, 8)

            if playlistsLoading && playlists.isEmpty && importedStore.playlists.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                    Text("正在读取官方歌单…")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(.horizontal, IOS27.pagePadding)
                .padding(.vertical, 18)
            } else if playlists.isEmpty && importedStore.playlists.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(playlistsMessage.isEmpty ? "还没有播放列表，可以从右上角导入网易云、QQ 音乐、酷狗或汽水歌单。" : playlistsMessage)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if auth.isLoggedIn {
                        Button("重新同步") { Task { await loadPlaylists() } }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(IOS27.accent)
                    }
                }
                .padding(.horizontal, IOS27.pagePadding)
                .padding(.vertical, 14)
            } else {
                IOS27PlainGroup {
                    ForEach(importedStore.playlists) { playlist in
                        importedRow(playlist)
                        if playlist.id != importedStore.playlists.last?.id || !playlists.isEmpty {
                            IOS27RowDivider(leading: 76)
                        }
                    }
                    ForEach(Array(playlists.enumerated()), id: \.element.id) { index, playlist in
                        cloudRow(playlist)
                        if index < playlists.count - 1 {
                            IOS27RowDivider(leading: 76)
                        }
                    }
                }
            }
        }
    }

    private var divider: some View {
        IOS27RowDivider(leading: 76)
    }

    private func importedRow(_ playlist: ImportedPlaylist) -> some View {
        Button {
            selectedImported = playlist
        } label: {
            HStack(spacing: 12) {
                artworkView(url: playlist.coverURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(playlist.source)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.secondaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Theme.chip)
                            )
                        Text("\(playlist.songs.count) 首")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                IOS27Chevron()
            }
            .padding(.horizontal, IOS27.pagePadding)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppleMusicListRowButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                importedStore.remove(playlist)
            } label: {
                Label("删除导入歌单", systemImage: "trash")
            }
        }
    }

    private func cloudRow(_ playlist: CloudPlaylist) -> some View {
        Button {
            selectedPlaylist = playlist
        } label: {
            HStack(spacing: 12) {
                artworkView(url: playlist.cover.flatMap(URL.init(string:)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text("\(playlist.count) 首 · 酷狗云歌单")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                IOS27Chevron()
            }
            .padding(.horizontal, IOS27.pagePadding)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(AppleMusicListRowButtonStyle())
    }

    private func artworkView(url: URL?) -> some View {
        CoverImage(url: url, size: 52, radius: 7, showsBorder: false)
            .frame(width: 52, height: 52)
    }

    private func loadProfile() async {
        guard auth.isLoggedIn else {
            vipText = ""
            return
        }
        await userProfile.refresh()
        vipText = await KGUser.vipText() ?? ""
    }

    private var accountCard: some View {
        HStack(spacing: 14) {
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                if !vipText.isEmpty {
                    Text(vipText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .lineLimit(1)
                } else if let signature = userProfile.profile?.signature, !signature.isEmpty {
                    Text(signature)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                } else {
                    Text(auth.isLoggedIn ? "已连接酷狗账号" : "登录后同步歌单与收藏")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !auth.isLoggedIn {
                Button {
                    showLogin = true
                } label: {
                    Text("登录")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 36)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
    }

    private var displayName: String {
        if let nickname = userProfile.profile?.nickname, !nickname.isEmpty { return nickname }
        return auth.isLoggedIn ? "酷狗用户" : "未登录"
    }

    private var avatarView: some View {
        UserAvatarView(url: userProfile.profile.flatMap { $0.avatarURL }.flatMap(URL.init(string:)),
                       size: 64,
                       borderWidth: 0.8)
    }

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放音质")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
            ForEach(AudioQuality.allCases) { item in
                Button {
                    quality = item
                    Preferences.quality = item
                    player.clearURLCache()
                    if player.current != nil {
                        player.reloadCurrentAfterQualityChange()
                        toast = "已切换为\(item.title)，正在重载当前歌曲"
                    } else {
                        toast = "已切换为\(item.title)"
                    }
                    Task { try? await Task.sleep(nanoseconds: 1_200_000_000); toast = "" }
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.text)
                        Spacer()
                        if quality == item {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            Text("取不到高音质时会自动降到下一档")
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appSurface(cornerRadius: 20)
    }

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("睡眠定时")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                if sleepText.isEmpty {
                    Text("未开启")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            if !sleepText.isEmpty {
                Text(sleepText)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.accent)
                Text("到点自动暂停，每秒刷新")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
            }
            HStack(spacing: 8) {
                ForEach([0, 5, 15, 30, 60], id: \.self) { minutes in
                    Button {
                        player.setSleepTimer(minutes: minutes == 0 ? nil : minutes)
                        sleepText = minutes == 0 ? "" : String(format: "剩余 %02d:00", minutes)
                        toast = minutes == 0 ? "已关闭睡眠定时" : "\(minutes) 分钟后自动暂停"
                        Task { try? await Task.sleep(nanoseconds: 1_400_000_000); toast = "" }
                    } label: {
                        Text(minutes == 0 ? "关闭" : "\(minutes) 分")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.chip)
                            .cornerRadius(12)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
            HStack(spacing: 10) {
                Stepper(value: $customMinutes, in: 1...180) {
                    Text("自定义 \(customMinutes) 分钟")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text.opacity(0.85))
                }
                Button {
                    player.setSleepTimer(minutes: customMinutes)
                    sleepText = String(format: "剩余 %02d:00", customMinutes)
                    toast = "\(customMinutes) 分钟后自动暂停"
                    Task { try? await Task.sleep(nanoseconds: 1_400_000_000); toast = "" }
                } label: {
                    Text("开始")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.accentGradient)
                        .cornerRadius(12)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appSurface(cornerRadius: 20)
        .onReceive(timer) { _ in
            guard let deadline = player.sleepDeadline else { sleepText = ""; return }
            let remain = Int(deadline.timeIntervalSinceNow)
            if remain <= 0 { sleepText = ""; return }
            sleepText = String(format: "剩余 %02d:%02d", remain / 60, remain % 60)
        }
    }
}


private struct LibraryArtistGroup: Identifiable {
    var id: String { name }
    var name: String
    var count: Int
    var cover: URL?
    var authorID: Int?
}

/// 资料库「歌手」二级页。按收藏与最近播放聚合并列；点进歌手沿用
/// iOS 27 的全幅歌手页，而不是另外维护一套列表详情。
struct LibraryArtistsView: View {
    @ObservedObject private var library = LibraryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedArtist: ArtistTarget?

    private var groups: [LibraryArtistGroup] {
        var map: [String: LibraryArtistGroup] = [:]
        for song in library.favorites + library.recent {
            let name = song.artist
            guard !name.isEmpty else { continue }
            if var existing = map[name] {
                existing = LibraryArtistGroup(name: existing.name,
                                              count: existing.count + 1,
                                              cover: existing.cover ?? song.coverURL,
                                              authorID: existing.authorID ?? song.AuthorID)
                map[name] = existing
            } else {
                map[name] = LibraryArtistGroup(name: name,
                                               count: 1,
                                               cover: song.coverURL,
                                               authorID: song.AuthorID)
            }
        }
        return map.values.sorted {
            if $0.count == $1.count { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.count > $1.count
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if groups.isEmpty {
                    Text("收藏或播放歌曲后，这里会按歌手聚合。")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                                Button {
                                    selectedArtist = ArtistTarget(name: group.name,
                                                                  authorID: group.authorID,
                                                                  cover: group.cover)
                                } label: {
                                    HStack(spacing: 13) {
                                        CoverImage(url: group.cover, size: 50, radius: 25, showsBorder: false)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(group.name)
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundColor(Theme.text)
                                                .lineLimit(1)
                                            Text("\(group.count) 首作品")
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundColor(Theme.secondaryText)
                                        }
                                        Spacer(minLength: 8)
                                        IOS27Chevron()
                                    }
                                    .padding(.horizontal, IOS27.pagePadding)
                                    .frame(height: 68)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(IOS27RowButtonStyle())

                                if index < groups.count - 1 {
                                    IOS27RowDivider(leading: 82)
                                        .padding(.trailing, IOS27.pagePadding)
                                }
                            }
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .background(AppBackground())
            .gradientNavigationBlur()
            .navigationTitle("歌手")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(IOS27.accent)
                }
            }
        }
        .navigationViewStyle(.stack)
        .fullScreenCover(item: $selectedArtist) { artist in
            ArtistDetailSheet(target: artist)
        }
    }
}

private enum LibrarySongSort: String, CaseIterable, Identifiable {
    case recent
    case title
    case artist

    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: return "默认顺序"
        case .title: return "按歌名"
        case .artist: return "按歌手"
        }
    }
}

struct LibrarySongsView: View {
    let kind: LibraryKind
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var importedStore = ImportedPlaylistStore.shared
    private var player: PlayerEngine { PlayerEngine.shared }
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false
    @State private var sort: LibrarySongSort = .recent
    @State private var searchText = ""

    private var allSongs: [Song] {
        let base = kind == .favorites ? library.favorites : library.recent
        switch sort {
        case .recent:
            return base
        case .title:
            return base.sorted { $0.SongName.localizedStandardCompare($1.SongName) == .orderedAscending }
        case .artist:
            return base.sorted {
                let artistOrder = $0.artist.localizedStandardCompare($1.artist)
                if artistOrder == .orderedSame {
                    return $0.SongName.localizedStandardCompare($1.SongName) == .orderedAscending
                }
                return artistOrder == .orderedAscending
            }
        }
    }

    private var songs: [Song] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return allSongs }
        return allSongs.filter {
            $0.SongName.localizedCaseInsensitiveContains(keyword)
                || $0.SingerName.localizedCaseInsensitiveContains(keyword)
        }
    }

    private func deleteSongs(at offsets: IndexSet) {
        for index in offsets {
            guard songs.indices.contains(index) else { continue }
            let song = songs[index]
            if kind == .favorites {
                Task {
                    let result = await library.toggleFavorite(song)
                    if result == nil { player.showToast(library.favoritesMessage) }
                }
            } else {
                library.removeRecent(song)
            }
        }
    }

    var body: some View {
        NavigationView {
            List {
                if !songs.isEmpty {
                    HStack(spacing: 10) {
                        Text("\(songs.count) 首")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.secondaryText)

                        Spacer(minLength: 0)

                        Button {
                            if let first = songs.first { player.play(first, in: songs) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                Text("播放")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.onAccent)
                            .frame(width: 98, height: 38)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(AppleMusicPressStyle())

                        Button {
                            guard !songs.isEmpty else { return }
                            let shuffled = songs.shuffled()
                            if let first = shuffled.first { player.play(first, in: shuffled) }
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.text)
                                .frame(width: 40, height: 38)
                                .liquidGlass(cornerRadius: 19)
                        }
                        .buttonStyle(AppleMusicPressStyle())
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 6, trailing: 18))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if kind == .favorites && library.favoritesLoading && songs.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        Text("正在同步官方「我喜欢」…")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .listRowBackground(Color.clear)
                } else if songs.isEmpty {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? (kind == .favorites
                            ? (library.favoritesMessage.isEmpty ? "官方「我喜欢」里还没有歌曲" : library.favoritesMessage)
                            : "还没有播放记录")
                         : "没有匹配的歌曲")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(songs, id: \.rowIdentity) { song in
                        HStack(spacing: 4) {
                            Button {
                                player.play(song, in: songs)
                            } label: {
                                SongRow(song: song, showsMore: false)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(AppleMusicListRowButtonStyle())

                            SongMoreMenu(song: song)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 10))
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.separator.opacity(0.42))
                    }
                    .onDelete(perform: deleteSongs)
                }
            }
            .listStyle(.plain)
            .background(AppBackground())
            .gradientNavigationBlur()
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索\(kind.title)")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(LibrarySongSort.allCases) { option in
                            Button {
                                sort = option
                            } label: {
                                Text((sort == option ? "✓ " : "") + option.title)
                            }
                        }
                        if kind != .favorites {
                            Divider()
                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Label("清空记录", systemImage: "trash")
                            }
                            .disabled(songs.isEmpty)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .disabled(songs.isEmpty)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .liquidGlass(cornerRadius: 16)
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .confirmationDialog("确定清空\(kind.title)？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    library.clearRecent()
                }
                Button("取消", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
        .task {
            if kind == .favorites {
                await library.refreshFavorites(force: true)
            }
        }
    }
}

struct QueueView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .inactive
    @State private var showClearConfirm = false
    @State private var songs: [Song] = []
    @State private var currentIndexValue = 0

    private var totalSeconds: Int {
        songs.reduce(0) { $0 + ($1.Duration ?? 0) }
    }

    private func durationText(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func refreshQueue() {
        songs = PlayerEngine.shared.queueSongs
        currentIndexValue = PlayerEngine.shared.currentIndex
    }

    var body: some View {
        NavigationView {
            List {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("\(songs.count) 首")
                        if totalSeconds > 0 {
                            Text("·")
                            Text("总时长 \(durationText(totalSeconds))")
                        }
                        if currentIndexValue < songs.count {
                            Text("·")
                            Text("正在播放第 \(currentIndexValue + 1) 首")
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
                .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 8, trailing: 18))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 4) {
                        Button {
                            PlayerEngine.shared.jump(to: index)
                            refreshQueue()
                        } label: {
                            HStack(spacing: 8) {
                                ZStack {
                                    if currentIndexValue == index {
                                        Capsule()
                                            .fill(Theme.accent)
                                            .frame(width: 3, height: 26)
                                    }
                                }
                                .frame(width: 4)

                                SongRow(song: song, showsMore: false)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AppleMusicListRowButtonStyle())

                        SongMoreMenu(song: song)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 10))
                    .listRowBackground(currentIndexValue == index ? Theme.accent.opacity(0.07) : Color.clear)
                    .listRowSeparatorTint(Theme.separator.opacity(0.42))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(Motion.standard) {
                                PlayerEngine.shared.removeFromQueue(at: index)
                            }
                            refreshQueue()
                        } label: { Label("移除", systemImage: "trash") }
                    }
                }
                .onMove { source, destination in
                    withAnimation(Motion.standard) {
                        PlayerEngine.shared.moveQueue(from: source, to: destination)
                    }
                    refreshQueue()
                }
            }
            .environment(\.editMode, $editMode)
            .listStyle(.plain)
            .background(AppBackground())
            .gradientNavigationBlur()
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(editMode == .active ? "完成" : "编辑") {
                        withAnimation(Motion.quick) {
                            editMode = editMode == .active ? .inactive : .active
                        }
                    }
                    .foregroundColor(Theme.accent)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            PlayerEngine.shared.shuffleUpcomingQueue()
                            refreshQueue()
                        } label: {
                            Label("随机播放接下来的歌曲", systemImage: "shuffle")
                        }
                        .disabled(songs.count <= currentIndexValue + 1)
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("清空播放队列", systemImage: "trash")
                        }
                        .disabled(songs.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .frame(width: 32, height: 32)
                            .liquidGlass(cornerRadius: 16)
                    }
                    .accessibilityLabel("关闭播放队列")
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { refreshQueue() }
        .onReceive(PlayerEngine.shared.$queueRevision) { _ in refreshQueue() }
        .onReceive(PlayerEngine.shared.$current) { _ in refreshQueue() }
        .confirmationDialog("确定清空播放列表？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空并停止播放", role: .destructive) {
                withAnimation(Motion.standard) {
                    PlayerEngine.shared.clearQueue()
                }
                refreshQueue()
            }
            Button("取消", role: .cancel) {}
        }
    }
}



private extension Song {
    var recommendRowID: String { "rec-\(FileHash)" }
    var favoriteRowID: String { "fav-\(FileHash)" }
    var recentRowID: String { "recent-\(FileHash)" }
    var rowIdentity: String { FileHash }
}

/// 外部歌单导入后的详情页。没有远端分页，歌曲已经在导入时全部匹配好。
struct ImportedPlaylistDetailSheet: View {
    let playlist: ImportedPlaylist
    let onSelect: (Song, [Song]) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        CollectionHero(coverURL: playlist.coverURL ?? playlist.songs.first?.coverURL, height: 300)
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.22), Color.black.opacity(0.58)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text("导入歌单 · \(playlist.source)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.70))
                                .textCase(.uppercase)
                            Text(playlist.name)
                                .font(.system(size: 27, weight: .bold))
                                .tracking(-0.4)
                                .foregroundColor(.white)
                                .lineLimit(3)
                            Text("\(playlist.songs.count) 首")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.white.opacity(0.64))
                        }
                        .padding(.horizontal, IOS27.pagePadding)
                        .padding(.bottom, 16)
                    }
                    .frame(height: 300)

                    HStack(spacing: 10) {
                        Button {
                            guard let first = playlist.songs.first else { return }
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                onSelect(first, playlist.songs)
                            }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "play.fill")
                                Text("播放")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.onAccent)
                            .frame(width: 132, height: 44)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(GlassPressButtonStyle())
                        .disabled(playlist.songs.isEmpty)

                        Button {
                            if let first = playlist.songs.first {
                                let shuffled = playlist.songs.shuffled()
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                    onSelect(shuffled.first ?? first, shuffled)
                                }
                            }
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.text)
                                .frame(width: 48, height: 44)
                                .liquidGlass(cornerRadius: 22)
                        }
                        .buttonStyle(GlassPressButtonStyle())
                        .disabled(playlist.songs.isEmpty)
                        .opacity(playlist.songs.isEmpty ? 0.48 : 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 14)

                    Divider()
                        .background(Theme.separator.opacity(0.55))
                        .padding(.horizontal, 16)

                    ForEach(Array(playlist.songs.enumerated()), id: \.element.id) { index, song in
                        VStack(spacing: 0) {
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                    onSelect(song, playlist.songs)
                                }
                            } label: {
                                SongRow(song: song, showsMore: false)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .padding(.horizontal, 14)
                            }
                            .buttonStyle(AppleMusicListRowButtonStyle())

                            if index < playlist.songs.count - 1 {
                                Divider()
                                    .background(Theme.separator.opacity(0.42))
                                    .padding(.leading, 76)
                                    .padding(.trailing, 14)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.text)
                            .frame(width: 32, height: 32)
                            .liquidGlass(cornerRadius: 16)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
