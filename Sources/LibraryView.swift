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
    @EnvironmentObject private var player: PlayerEngine
    let onSelect: (Song, [Song]) -> Void
    let onOpenPlayer: () -> Void

    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var auth = AuthStore.shared
    @State private var playlists: [CloudPlaylist] = []
    @State private var playlistsLoading = false
    @State private var playlistsMessage = ""
    @State private var ranks: [RankItem] = []
    @State private var sheetTarget: DiscoverSheet?

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
            playlists = try await KGService.playlists()
            if playlists.isEmpty { playlistsMessage = "官方账号里没有读到歌单" }
        } catch {
            playlistsMessage = (error as? LocalizedError)?.errorDescription ?? "歌单同步失败"
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
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

                if auth.isLoggedIn {
                    SectionTitle(title: "我的歌单",
                                 subtitle: playlistsLoading ? "同步中…" : "\(playlists.count) 个",
                                 actionTitle: "同步") {
                        Task { await loadPlaylists() }
                    }
                    if playlistsLoading && playlists.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                            Text("正在同步官方歌单…")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.secondaryText)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    } else if playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(playlistsMessage.isEmpty ? "还没有读取到歌单" : playlistsMessage)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.secondaryText)
                            Button("重新同步") { Task { await loadPlaylists() } }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(playlists) { playlist in
                                    Button { sheetTarget = .playlist(playlist) } label: {
                                        PlaylistCard(playlist: playlist)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)
                        }
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
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                    }
                }

                if !model.songs.isEmpty {
                    SectionTitle(title: "每日推荐", subtitle: "\(model.songs.count) 首")
                    ForEach(model.songs, id: \.recommendRowID) { song in
                        Button {
                            onSelect(song, model.songs)
                        } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }

                if !library.favorites.isEmpty {
                    SectionTitle(title: "我的收藏", subtitle: "\(library.favorites.count) 首", actionTitle: "查看全部") {
                        sheetTarget = .library(.favorites)
                    }
                    ForEach(library.favorites, id: \.favoriteRowID) { song in
                        Button {
                            onSelect(song, library.favorites)
                        } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }

                if !library.recent.isEmpty {
                    SectionTitle(title: "最近播放", subtitle: "\(library.recent.count) 首", actionTitle: "查看全部") {
                        sheetTarget = .library(.recent)
                    }
                    ForEach(library.recent, id: \.recentRowID) { song in
                        Button {
                            onSelect(song, library.recent)
                        } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let song = player.current {
                MiniPlayer(song: song, onOpen: onOpenPlayer)
            }
        }
        .refreshable {
            await model.load(force: true)
            await library.enrichMissingCovers()
            ranks = (try? await KGService.ranks()) ?? ranks
            await loadPlaylists()
        }
        .onAppear {
            library.refresh()
        }
        .task {
            await library.enrichMissingCovers()
            if ranks.isEmpty { ranks = (try? await KGService.ranks()) ?? [] }
            await loadPlaylists()
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
            case .library(let kind):
                LibrarySongsView(kind: kind)
                    .environmentObject(player)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("发现")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Theme.text)
                Text("今天想听点什么 🎧")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.10))
                    .clipShape(Capsule())
                Spacer()
                Button {
                    Task { await model.load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.text.opacity(0.7))
                        .frame(width: 34, height: 34)
                        .background(Theme.chip)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("每天一组，按你的口味来")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
                if let first = model.songs.first {
                    Button {
                        onSelect(first, model.songs)
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

enum LibraryKind: String, Identifiable {
    case favorites
    case recent

    var id: String { rawValue }
    var title: String { self == .favorites ? "我的收藏" : "最近播放" }
}

enum DiscoverSheet: Identifiable {
    case playlist(CloudPlaylist)
    case rank(RankItem)
    case library(LibraryKind)

    var id: String {
        switch self {
        case .playlist(let playlist): return "playlist-\(playlist.id)"
        case .rank(let rank): return "rank-\(rank.id)"
        case .library(let kind): return "library-\(kind.id)"
        }
    }
}

struct RankCard: View {
    let rank: RankItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.card)
                if let url = rank.cover.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .frame(width: 108, height: 108)
            Text(rank.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .frame(width: 108, alignment: .leading)
            Text("榜单")
                .font(.system(size: 10))
                .foregroundColor(Theme.secondaryText)
        }
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

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if loading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).padding(.top, 30)
                    } else if !message.isEmpty {
                        Text(message).font(.system(size: 13)).foregroundColor(Theme.secondaryText).padding(.top, 24)
                    }
                    ForEach(songs) { song in
                        Button {
                            dismiss()
                            onSelect(song, songs)
                        } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                    if !loading && !songs.isEmpty && hasMore {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            Text(loadingMore ? "加载中…" : "加载更多")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.accent)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle(rank.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !songs.isEmpty {
                        Button {
                            dismiss()
                            onSelect(songs[0], songs)
                        } label: { Label("播放全部", systemImage: "play.fill") }
                    }
                }
            }
        }
        .task { await loadMore() }
    }

    private func loadMore() async {
        guard !loadingMore else { return }
        loadingMore = true
        do {
            let newSongs = try await KGService.rankSongs(rankid: rank.id, page: page, pageSize: 30)
            let existing = Set(songs.map { $0.FileHash })
            songs.append(contentsOf: newSongs.filter { !existing.contains($0.FileHash) })
            hasMore = newSongs.count >= 30
            page += 1
            loading = false
            if songs.isEmpty { message = "榜单暂时没有内容" }
        } catch {
            loading = false
            message = (error as? LocalizedError)?.errorDescription ?? "榜单加载失败"
        }
        loadingMore = false
    }
}

struct PlaylistCard: View {
    let playlist: CloudPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.card)
                if let url = playlist.cover.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .frame(width: 108, height: 108)
            Text(playlist.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.text)
                .lineLimit(1)
                .frame(width: 108, alignment: .leading)
            Text(playlist.isCollected ? "收藏 · \(playlist.count) 首" : "\(playlist.count) 首")
                .font(.system(size: 10))
                .foregroundColor(Theme.secondaryText)
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

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if loading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).padding(.top, 30)
                    } else if !message.isEmpty && songs.isEmpty {
                        Text(message).font(.system(size: 13)).foregroundColor(Theme.secondaryText).padding(.top, 24)
                    } else if !songs.isEmpty {
                        Text(playlist.isCollected ? "收藏歌单 · \(playlist.count) 首" : "歌单 · \(playlist.count) 首")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                    }
                    ForEach(songs) { song in
                        Button {
                            dismiss()
                            onSelect(song, songs)
                        } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
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
                        .buttonStyle(.plain)
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
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle(playlist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !songs.isEmpty {
                        Button {
                            dismiss()
                            onSelect(songs[0], songs)
                        } label: { Label("播放全部", systemImage: "play.fill") }
                    }
                }
            }
        }
        .task { await loadMore() }
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

struct SectionTitle: View {
    let title: String
    let subtitle: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.text)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerEngine
    @State private var quality: AudioQuality = Preferences.quality
    @State private var showLogin = false
    @State private var showSettings = false
    @State private var showDiagnostics = false
    @State private var toast = ""
    @State private var sleepText = ""
    @State private var customMinutes = 45
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                accountCard

                Button { showSettings = true } label: {
                    row(title: "设置", icon: "gearshape")
                }
                .buttonStyle(.plain)
                .background(Theme.card)
                .cornerRadius(14)

                toolsCard
                Text("KugouLite · iOS 15 精简版")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(AppBackground())
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(player).environmentObject(auth)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(player)
        }
        .overlay(alignment: .top) {
            if !toast.isEmpty { ToastView(text: toast) }
        }
    }

    private var accountCard: some View {
        VStack(spacing: 10) {
            Image(systemName: auth.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.system(size: 40))
                .foregroundColor(Theme.accent)
            Text(auth.isLoggedIn ? "已登录" : "未登录")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.text)
            if auth.isLoggedIn {
                Text("UID \(auth.userid)")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
            Button {
                showLogin = true
            } label: {
                Text(auth.isLoggedIn ? "查看账号 / 会员状态" : "扫码登录酷狗概念版")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Theme.accent)
                    .cornerRadius(18)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.card)
        .cornerRadius(16)
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
                .buttonStyle(.plain)
            }
            Text("取不到高音质时会自动降到下一档")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .cornerRadius(14)
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
                    .buttonStyle(.plain)
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
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.accent)
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .cornerRadius(14)
        .onReceive(timer) { _ in
            guard let deadline = player.sleepDeadline else { sleepText = ""; return }
            let remain = Int(deadline.timeIntervalSinceNow)
            if remain <= 0 { sleepText = ""; return }
            sleepText = String(format: "剩余 %02d:%02d", remain / 60, remain % 60)
        }
    }

    private var toolsCard: some View {
        VStack(spacing: 0) {
            Button {
                LibraryStore.shared.clear()
                toast = "已清空搜索与最近播放"
                Task { try? await Task.sleep(nanoseconds: 1_400_000_000); toast = "" }
            } label: {
                row(title: "清空本地记录", icon: "trash")
            }
            .buttonStyle(.plain)
            Divider().background(Theme.separator)
            Button {
                showDiagnostics = true
            } label: {
                row(title: "会员领取诊断", icon: "stethoscope")
            }
            .buttonStyle(.plain)
            Divider().background(Theme.separator)
            Button {
                if auth.isLoggedIn {
                    auth.signOut()
                    toast = "已退出登录"
                    Task { try? await Task.sleep(nanoseconds: 1_200_000_000); toast = "" }
                }
            } label: {
                row(title: auth.isLoggedIn ? "退出登录" : "未登录", icon: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.plain)
        }
        .background(Theme.card)
        .cornerRadius(14)
    }

    private func row(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Theme.text)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
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
    @EnvironmentObject private var player: PlayerEngine
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

    var body: some View {
        NavigationView {
            List {
                if songs.isEmpty {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? (kind == .favorites ? "还没有收藏，长按歌曲就能收藏" : "还没有播放记录")
                         : "没有匹配的歌曲")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .listRowBackground(Theme.card)
                } else {
                    ForEach(songs, id: \.rowIdentity) { song in
                        SongRow(song: song)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.play(song, in: songs)
                            }
                            .listRowBackground(Theme.card)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                if kind == .favorites {
                                    library.toggleFavorite(song)
                                } else {
                                    library.removeRecent(song)
                                }
                            } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            }
            .listStyle(.plain)
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
                    Button("清空") { showClearConfirm = true }
                        .disabled(songs.isEmpty)
                    Button("关闭") { dismiss() }
                }
            }
            .confirmationDialog("确定清空\(kind.title)？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    if kind == .favorites { library.clearFavorites() } else { library.clearRecent() }
                }
                Button("取消", role: .cancel) {}
            }
        }
        .navigationViewStyle(.stack)
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
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Theme.card)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            player.removeFromQueue(at: index)
                        } label: { Label("移除", systemImage: "trash") }
                    }
                }
                .onMove { source, destination in
                    player.moveQueue(from: source, to: destination)
                }
            }
            .environment(\.editMode, $editMode)
            .listStyle(.plain)
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
            Button("清空并停止播放", role: .destructive) { player.clearQueue() }
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
