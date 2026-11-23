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
    @Binding var isSearching: Bool
    let onSelect: (Song, [Song]) -> Void
    let onSelectSearch: (Song) -> Void
    let onOpenPlayer: () -> Void

    @ObservedObject private var library = LibraryStore.shared
    @State private var ranks: [RankItem] = []
    @State private var sheetTarget: DiscoverSheet?
    @FocusState private var searchFocused: Bool
    @State private var historyWords: [String] = Preferences.searchHistory
    @State private var hotKeywords: [String] = []

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: Date())
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
        .animation(Motion.standard, value: isSearching)
        .task {
            historyWords = Preferences.searchHistory
            if hotKeywords.isEmpty {
                hotKeywords = (try? await KGService.hotSearch()) ?? []
            }
            await library.enrichMissingCovers()
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
        .sheet(item: $sheetTarget) { target in
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
                    .font(.system(size: 13, weight: .medium))
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
                Text(todayLabel + " · 为你推荐")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }

                if let message = model.message, model.songs.isEmpty {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                }

                if !recommendedAlbums.isEmpty {
                    SectionTitle(title: "为你推荐", subtitle: "专辑")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(recommendedAlbums) { album in
                                AppleMusicAlbumCard(album: album) {
                                    sheetTarget = .album(AlbumTarget(id: album.id,
                                                                     name: album.name,
                                                                     cover: album.coverURL,
                                                                     artist: album.artist))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }
                }

                if !ranks.isEmpty {
                    SectionTitle(title: "排行榜", subtitle: nil)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ranks.prefix(8)) { rank in
                                Button { sheetTarget = .rank(rank) } label: {
                                    RankCard(rank: rank)
                                }
                                .buttonStyle(GlassPressButtonStyle())
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                    }
                }

                if !model.songs.isEmpty {
                    dailyHeader
                    ForEach(model.songs, id: \.recommendRowID) { song in
                        SongRowWithMenu(song: song) {
                            onSelect(song, model.songs)
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .padding(.bottom, 132)
            .animation(Motion.standard, value: model.songs.count)
            .animation(Motion.standard, value: ranks.count)
        }
        .refreshable {
            await model.load(force: true)
            await library.enrichMissingCovers()
            ranks = (try? await KGService.ranks()) ?? ranks
        }
    }

    private var dailyHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("每日推荐")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)

            Text("\(model.songs.count) 首")
                .font(.system(size: 12))
                .foregroundColor(Theme.secondaryText)

            Spacer(minLength: 8)

            if let first = model.songs.first {
                Button {
                    onSelect(first, model.songs)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("播放全部")
                            .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                }

                if !searchModel.songs.isEmpty {
                    Text("歌曲")
                        .font(.system(size: 13, weight: .semibold))
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
            .padding(.bottom, 132)
            .animation(Motion.standard, value: searchModel.songs.count)
        }
    }

    private var searchHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("最近搜索")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                    Spacer()
                    if !historyWords.isEmpty {
                        Button {
                            Preferences.searchHistory = []
                            historyWords = []
                            searchModel.query = ""
                        } label: {
                            Text("清除")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.accent)
                                .frame(height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(GlassPressButtonStyle())
                    }
                }

                if historyWords.isEmpty {
                    Text("搜歌手、歌名或专辑，点一首就能听")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .appSurface(cornerRadius: 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(historyWords.enumerated()), id: \.element) { index, word in
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .font(.system(size: 13))
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
                                        .font(.system(size: 11, weight: .semibold))
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
                    .appSurface(cornerRadius: 10)
                }
            }

            if !hotKeywords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("热门搜索")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)

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
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(index < 3 ? Theme.accent : Theme.tertiaryText)
                                        .frame(width: 16, alignment: .leading)
                                    Text(word)
                                        .font(.system(size: 13))
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
                    .appSurface(cornerRadius: 10)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.chip)
                if let url = rank.cover.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .frame(width: 148, height: 148)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.border, lineWidth: 0.5)
            )

            Text(rank.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .frame(width: 148, alignment: .leading)
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
                    .blur(radius: 24)
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
            VStack(spacing: 0) {
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
                        .font(.system(size: 13))
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
                                }
                                .buttonStyle(GlassPressButtonStyle())
                                SongMoreMenu(song: song)
                            }
                            .padding(.horizontal, 16)

                            if index < songs.count - 1 {
                                Rectangle()
                                    .fill(Theme.separator.opacity(0.55))
                                    .frame(height: 0.5)
                                    .padding(.leading, 64)
                                    .padding(.trailing, 16)
                            }
                        }
                    }

                    if hasMore {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            HStack(spacing: 6) {
                                if loadingMore {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.text))
                                }
                                Text(loadingMore ? "加载中…" : "加载更多")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(GlassPressButtonStyle())
                        .disabled(loadingMore)
                    } else if !message.isEmpty {
                        Text(message)
                            .font(.system(size: 11))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.28))
                    .clipShape(Circle())
            }
            .buttonStyle(GlassPressButtonStyle())
            .padding(.top, 12)
            .padding(.trailing, 16)
            .accessibilityLabel("关闭排行榜")
        }
        .task { await loadMore() }
    }

    private var info: some View {
        VStack(spacing: 12) {
            Text(rank.name)
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 24)

            if !rank.intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(rank.intro)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 6) {
                Text("酷狗排行榜")
                if !songs.isEmpty {
                    Text("·")
                    Text("\(songs.count) 首")
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.secondaryText)

            Button {
                guard let first = songs.first else { return }
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                    onSelect(first, songs)
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                    Text("播放全部")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(GlassPressButtonStyle())
            .disabled(songs.isEmpty)
            .opacity(songs.isEmpty ? 0.48 : 1)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
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
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .frame(width: 148, height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                .font(.system(size: 11))
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
            VStack(spacing: 0) {
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
                        .font(.system(size: 13))
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
                                    .buttonStyle(GlassPressButtonStyle())
                                } else {
                                    Button {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                            onSelect(song, songs)
                                        }
                                    } label: {
                                        SongRow(song: song, showsMore: false)
                                    }
                                    .buttonStyle(GlassPressButtonStyle())
                                    SongMoreMenu(song: song)
                                }
                            }
                            .padding(.horizontal, 16)

                            if index < songs.count - 1 {
                                Rectangle()
                                    .fill(Theme.separator.opacity(0.55))
                                    .frame(height: 0.5)
                                    .padding(.leading, 64)
                                    .padding(.trailing, 16)
                            }
                        }
                    }

                    if !loading && !songs.isEmpty && hasMore {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            HStack(spacing: 6) {
                                if loadingMore { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.text)) }
                                Text(loadingMore ? "加载中…" : "加载更多")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(GlassPressButtonStyle())
                        .disabled(loadingMore)
                        .id("playlist-more-\(songs.count)")
                    } else if !loading && !message.isEmpty && !songs.isEmpty {
                        Text(message)
                            .font(.system(size: 11))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.28))
                    .clipShape(Circle())
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
    }

    private var info: some View {
        VStack(spacing: 12) {
            Text(playlist.name)
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 24)

            HStack(spacing: 6) {
                Text(playlist.isCollected ? "收藏歌单" : "歌单")
                Text("·")
                Text("\(playlist.count) 首")
            }
            .font(.system(size: 11, weight: .medium))
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
                        Text("播放全部")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(songs.isEmpty)
                .opacity(songs.isEmpty ? 0.48 : 1)

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isSelecting.toggle()
                        selectedHashes.removeAll()
                    }
                } label: {
                    Text(isSelecting ? "取消批量" : "批量加入")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelecting ? Theme.accent : Theme.text)
                        .frame(width: 104)
                        .frame(height: 44)
                        .background(Theme.chip)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(songs.isEmpty)
                .opacity(songs.isEmpty ? 0.48 : 1)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }
    private var batchBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(selectedSongs.count) 首")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.text)
            Spacer()
            Button {
                showTargetPicker = true
            } label: {
                HStack(spacing: 4) {
                    if adding { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.onAccent)) }
                    Text(adding ? "加入中…" : "加入歌单")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(Theme.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(selectedHashes.isEmpty ? Theme.secondaryText.opacity(0.35) : Theme.accent)
                .cornerRadius(10)
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
            let newSongs = try await KGService.playlistSongs(playlist: playlist, page: page, pageSize: 30)
            if page == 1 {
                songs = newSongs
            } else {
                let existing = Set(songs.map { $0.id })
                songs.append(contentsOf: newSongs.filter { !existing.contains($0.id) })
            }
            if newSongs.isEmpty || newSongs.count < 30 || (page == 1 && newSongs.count > 30) {
                hasMore = false
            } else if playlist.count > 0, songs.count >= playlist.count {
                hasMore = false
            } else {
                hasMore = true
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
                        Text("读取歌单…").font(.system(size: 12)).foregroundColor(Theme.secondaryText)
                    }
                    .listRowBackground(Theme.card)
                } else if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                        .listRowBackground(Theme.card)
                } else if playlists.isEmpty {
                    Text("没有可写入的自建歌单，先在酷狗创建或取消收藏后再试")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                        .listRowBackground(Theme.card)
                } else {
                    ForEach(playlists) { playlist in
                        Button {
                            dismiss()
                            onPick(playlist)
                        } label: {
                            HStack(spacing: 10) {
                                CoverImage(url: playlist.cover.flatMap(URL.init(string:)), size: 44, radius: 8)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    Text("\(playlist.count) 首")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Theme.tertiaryText)
                            }
                        }
                        .buttonStyle(GlassPressButtonStyle())
                        .listRowBackground(Theme.card)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(AppBackground())
            .navigationTitle("选择歌单")
            .navigationBarTitleDisplayMode(.inline)
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
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .frame(height: 32)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var importedStore = ImportedPlaylistStore.shared
    private var player: PlayerEngine { PlayerEngine.shared }
    var onOpenPlayer: () -> Void = {}
    @State private var quality: AudioQuality = Preferences.quality
    @State private var showLogin = false
    @State private var profile: KugouProfile?
    @State private var vipText = ""
    @State private var playlists: [CloudPlaylist] = []
    @State private var playlistsLoading = false
    @State private var playlistsMessage = ""
    @State private var selectedPlaylist: CloudPlaylist?
    @State private var selectedImported: ImportedPlaylist?
    @State private var showImport = false
    @State private var toast = ""
    @State private var sleepText = ""
    @State private var customMinutes = 45
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                accountCard
                playlistsSection

            }
            .padding(16)
            .padding(.bottom, 136)
        }
        .background(AppBackground())
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(player).environmentObject(auth)
        }
        .sheet(isPresented: $showImport) {
            PlaylistImportView()
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailSheet(playlist: playlist) { song, list in
                selectedPlaylist = nil
                player.play(song, in: list)
                onOpenPlayer()
            }
        }
        .sheet(item: $selectedImported) { playlist in
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

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("我的歌单")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("\(playlists.count + importedStore.playlists.count) 个")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
                Button { showImport = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("导入")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Theme.accent)
                    .frame(height: 32)
                }
                .buttonStyle(GlassPressButtonStyle())

                if auth.isLoggedIn {
                    Button { Task { await loadPlaylists() } } label: {
                        Text(playlistsLoading ? "同步中…" : "同步")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.accent)
                            .frame(height: 32)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                    .disabled(playlistsLoading)
                }
            }

            if !auth.isLoggedIn {
                Button { showLogin = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 15))
                            .foregroundColor(Theme.accent)
                        Text("登录后同步酷狗云歌单")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.tertiaryText)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .appSurface(cornerRadius: 10)
                }
                .buttonStyle(GlassPressButtonStyle())
            }

            if playlistsLoading && playlists.isEmpty && importedStore.playlists.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                    Text("正在读取官方歌单…")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(.vertical, 8)
            } else if playlists.isEmpty && importedStore.playlists.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(playlistsMessage.isEmpty ? "还没有歌单，点右上角「导入」从网易云、QQ 音乐、酷狗或汽水搬一个过来。" : playlistsMessage)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if auth.isLoggedIn {
                        Button("重新同步") { Task { await loadPlaylists() } }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.accent)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appSurface(cornerRadius: 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(importedStore.playlists) { playlist in
                        importedRow(playlist)
                        if playlist.id != importedStore.playlists.last?.id || !playlists.isEmpty {
                            divider
                        }
                    }
                    ForEach(playlists) { playlist in
                        cloudRow(playlist)
                        if playlist.id != playlists.last?.id {
                            divider
                        }
                    }
                }
                .appSurface(cornerRadius: 12)
            }
        }
        .padding(.top, 2)
    }

    private var divider: some View {
        Divider()
            .background(Theme.separator.opacity(0.55))
            .padding(.leading, 78)
    }

    private func importedRow(_ playlist: ImportedPlaylist) -> some View {
        Button {
            selectedImported = playlist
        } label: {
            HStack(spacing: 12) {
                artworkView(url: playlist.coverURL)
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(playlist.source)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Theme.accent.opacity(0.12))
                            )
                        Text("\(playlist.songs.count) 首")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
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
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playlist.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Text("\(playlist.count) 首 · 酷狗云歌单")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
    }

    private func artworkView(url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    artworkPlaceholder
                }
            } else {
                artworkPlaceholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Theme.card
            Image(systemName: "music.note")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Theme.secondaryText)
        }
    }

    private func loadProfile() async {
        guard auth.isLoggedIn else {
            profile = nil
            vipText = ""
            return
        }
        profile = await KGUser.profile()
        vipText = await KGUser.vipText() ?? ""
    }

    private var accountCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                avatarView
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    if !vipText.isEmpty {
                        Text(vipText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.accent)
                            .lineLimit(2)
                    }
                    if let signature = profile?.signature, !signature.isEmpty {
                        Text(signature)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            if !auth.isLoggedIn {
                Button {
                    showLogin = true
                } label: {
                    Text("扫码登录酷狗概念版")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.accent)
                        )
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appSurface(cornerRadius: 12)
    }

    private var displayName: String {
        if let nickname = profile?.nickname, !nickname.isEmpty { return nickname }
        return auth.isLoggedIn ? "酷狗用户" : "未登录"
    }

    private var avatarView: some View {
        Group {
            if let raw = profile?.avatarURL, let url = URL(string: raw) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
            } else {
                avatarPlaceholder
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.separator, lineWidth: 0.6))
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(Theme.chip)
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 30))
                .foregroundColor(Theme.accent)
        }
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
                            .font(.system(size: 13))
                            .foregroundColor(Theme.text)
                        Spacer()
                        if quality == item {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            Text("取不到高音质时会自动降到下一档")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appSurface(cornerRadius: 12)
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
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            if !sleepText.isEmpty {
                Text(sleepText)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.accent)
                Text("到点自动暂停，每秒刷新")
                    .font(.system(size: 11))
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
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.chip)
                            .cornerRadius(9)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
            HStack(spacing: 10) {
                Stepper(value: $customMinutes, in: 1...180) {
                    Text("自定义 \(customMinutes) 分钟")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text.opacity(0.85))
                }
                Button {
                    player.setSleepTimer(minutes: customMinutes)
                    sleepText = String(format: "剩余 %02d:00", customMinutes)
                    toast = "\(customMinutes) 分钟后自动暂停"
                    Task { try? await Task.sleep(nanoseconds: 1_400_000_000); toast = "" }
                } label: {
                    Text("开始")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.accentGradient)
                        .cornerRadius(9)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appSurface(cornerRadius: 12)
        .onReceive(timer) { _ in
            guard let deadline = player.sleepDeadline else { sleepText = ""; return }
            let remain = Int(deadline.timeIntervalSinceNow)
            if remain <= 0 { sleepText = ""; return }
            sleepText = String(format: "剩余 %02d:%02d", remain / 60, remain % 60)
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
                if kind == .favorites && library.favoritesLoading && songs.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        Text("正在同步官方「我喜欢」…")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .listRowBackground(Theme.card)
                } else if songs.isEmpty {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? (kind == .favorites
                            ? (library.favoritesMessage.isEmpty ? "官方「我喜欢」里还没有歌曲" : library.favoritesMessage)
                            : "还没有播放记录")
                         : "没有匹配的歌曲")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .listRowBackground(Theme.card)
                } else {
                    ForEach(songs, id: \.rowIdentity) { song in
                        HStack(spacing: 8) {
                            SongRow(song: song, showsMore: false)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    player.play(song, in: songs)
                                }
                            SongMoreMenu(song: song)
                        }
                        .listRowBackground(Theme.card)
                    }
                    .onDelete(perform: deleteSongs)
                }
            }
            .listStyle(.insetGrouped)
            .background(AppBackground())
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索\(kind.title)")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if let first = songs.first { player.play(first, in: songs) }
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    .disabled(songs.isEmpty)
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(LibrarySongSort.allCases) { option in
                            Button {
                                sort = option
                            } label: {
                                Text((sort == option ? "✓ " : "") + option.title)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .disabled(songs.isEmpty)
                    if kind != .favorites {
                        Button("清空") { showClearConfirm = true }
                            .disabled(songs.isEmpty)
                    }
                    Button("关闭") { dismiss() }
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
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .inactive
    @State private var showClearConfirm = false

    private var totalSeconds: Int {
        player.queueSongs.reduce(0) { $0 + ($1.Duration ?? 0) }
    }

    private var remainingSeconds: Int {
        var result = 0
        for (index, song) in player.queueSongs.enumerated() {
            let duration = song.Duration ?? 0
            if index < player.currentIndex { continue }
            if index == player.currentIndex {
                result += max(0, duration - Int(player.currentTime))
            } else {
                result += duration
            }
        }
        return result
    }

    private func durationText(_ seconds: Int) -> String {
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        NavigationView {
            List {
                if !player.queueSongs.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("共 \(player.queueSongs.count) 首")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.text)
                            Spacer()
                            Text("正在播放第 \(player.currentIndex + 1) 首")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.accent)
                        }
                        if totalSeconds > 0 {
                            Text("总时长 \(durationText(totalSeconds)) · 剩余 \(durationText(remainingSeconds))")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Theme.card)
                }

                ForEach(Array(player.queueSongs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        player.jump(to: index)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.secondaryText)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.SongName)
                                    .font(.system(size: 14, weight: player.currentIndex == index ? .semibold : .regular))
                                    .foregroundColor(player.currentIndex == index ? Theme.accent : Theme.text)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassPressButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Theme.card)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                player.removeFromQueue(at: index)
                            }
                        } label: { Label("移除", systemImage: "trash") }
                    }
                }
                .onMove { source, destination in
                    withAnimation(.easeInOut(duration: 0.24)) {
                        player.moveQueue(from: source, to: destination)
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .listStyle(.insetGrouped)
            .background(AppBackground())
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button(editMode == .active ? "完成" : "排序") {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    }
                    Button {
                        player.shuffleUpcomingQueue()
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .disabled(player.queueSongs.count <= player.currentIndex + 1)
                    Button("清空") { showClearConfirm = true }
                        .disabled(player.queueSongs.isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
        .confirmationDialog("确定清空播放列表？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空并停止播放", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.24)) {
                    player.clearQueue()
                }
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
                        CollectionHero(coverURL: playlist.coverURL ?? playlist.songs.first?.coverURL, height: 280)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(playlist.source.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.accent)
                            Text(playlist.name)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(Theme.text)
                                .lineLimit(3)
                            Text("\(playlist.songs.count) 首 · 导入歌单")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.secondaryText)
                        }
                        .padding(16)
                    }
                    .frame(height: 280)

                    HStack(spacing: 12) {
                        Button {
                            guard let first = playlist.songs.first else { return }
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                onSelect(first, playlist.songs)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text("播放")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(Theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Theme.accent)
                            )
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
                                .foregroundColor(Theme.accent)
                                .frame(width: 48, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Theme.card.opacity(0.9))
                                )
                        }
                        .buttonStyle(GlassPressButtonStyle())
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 14)

                    Divider()
                        .background(Theme.separator.opacity(0.55))
                        .padding(.horizontal, 16)

                    ForEach(playlist.songs) { song in
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                                onSelect(song, playlist.songs)
                            }
                        } label: {
                            SongRow(song: song, showsMore: false)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(GlassPressButtonStyle())
                    }
                }
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
