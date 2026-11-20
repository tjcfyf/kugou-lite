import Foundation
import Combine

/// 最近播放留在本地；「我喜欢」以官方云歌单为准，本地只做内存缓存。
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var recent: [Song] = Preferences.recentSongs
    @Published private(set) var favorites: [Song] = []
    @Published private(set) var favoritePlaylist: CloudPlaylist?
    @Published private(set) var favoritesLoading = false
    @Published private(set) var favoritesLoaded = false
    @Published private(set) var favoritesMessage = ""

    private var favoriteHashes = Set<String>()

    private init() {}

    func refresh() {
        recent = Preferences.recentSongs
    }

    func addRecent(_ song: Song) {
        Preferences.addRecent(song)
        recent = Preferences.recentSongs
    }

    func isFavorite(_ song: Song) -> Bool {
        favoriteHashes.contains(song.FileHash.lowercased())
    }

    @MainActor
    func refreshFavorites(force: Bool = false) async {
        guard KGApi.shared.token != nil, KGApi.shared.userid != 0 else {
            resetFavorites()
            return
        }
        if favoritesLoading { return }
        if favoritesLoaded && !force { return }

        favoritesLoading = true
        favoritesMessage = ""
        defer { favoritesLoading = false }

        do {
            guard let playlist = try await KGService.favoritePlaylist() else {
                throw KGError.server("官方账号里没有找到「我喜欢」歌单")
            }
            favoritePlaylist = playlist

            var all: [Song] = []
            var seen = Set<String>()
            var page = 1
            while page <= 20 {
                let batch = try await KGService.playlistSongs(playlist: playlist, page: page, pageSize: 30)
                if batch.isEmpty { break }
                for song in batch {
                    let key = song.FileHash.lowercased()
                    if seen.insert(key).inserted { all.append(song) }
                }
                if batch.count < 30 { break }
                if playlist.count > 0, all.count >= playlist.count { break }
                page += 1
            }

            favorites = all
            favoriteHashes = Set(all.map { $0.FileHash.lowercased() })
            favoritesLoaded = true
            favoritesMessage = ""
            // 旧版本的本地收藏不再作为数据源，读到官方歌单后顺手清掉。
            Preferences.favorites = []
        } catch {
            favoritesLoaded = false
            favoritesMessage = (error as? LocalizedError)?.errorDescription ?? "官方「我喜欢」同步失败"
        }
    }

    /// 返回 true=已加入，false=已移除，nil=失败（错误文案在 favoritesMessage）。
    @MainActor
    @discardableResult
    func toggleFavorite(_ song: Song) async -> Bool? {
        guard KGApi.shared.token != nil, KGApi.shared.userid != 0 else {
            favoritesMessage = "请先登录酷狗账号"
            return nil
        }
        if !favoritesLoaded {
            await refreshFavorites()
        }
        guard let playlist = favoritePlaylist else {
            if favoritesMessage.isEmpty { favoritesMessage = "官方「我喜欢」尚未同步" }
            return nil
        }

        let wasFavorite = isFavorite(song)
        do {
            if wasFavorite {
                try await KGService.removeFavorite(song, from: playlist)
                favorites.removeAll { $0.FileHash.lowercased() == song.FileHash.lowercased() }
                favoriteHashes.remove(song.FileHash.lowercased())
            } else {
                try await KGService.addSongs([song], to: playlist, typeOverride: 0)
                favorites.insert(song, at: 0)
                favoriteHashes.insert(song.FileHash.lowercased())
            }
            favoritesMessage = ""
            return !wasFavorite
        } catch {
            favoritesMessage = (error as? LocalizedError)?.errorDescription ?? "官方「我喜欢」操作失败"
            return nil
        }
    }

    @MainActor
    func resetFavorites() {
        favorites = []
        favoriteHashes.removeAll()
        favoritePlaylist = nil
        favoritesLoaded = false
        favoritesMessage = ""
    }

    private var isEnriching = false

    /// 老版本存下来的最近播放可能没有封面，按 hash 回查一次并写回本地。
    @MainActor
    func enrichMissingCovers() async {
        guard !isEnriching else { return }
        isEnriching = true
        defer { isEnriching = false }

        var recentList = Preferences.recentSongs
        for index in recentList.indices where (recentList[index].Image ?? "").isEmpty {
            if let cover = await KGService.songCover(hash: recentList[index].FileHash) {
                recentList[index] = recentList[index].withImage(cover)
            }
        }
        if recentList != recent {
            Preferences.recentSongs = recentList
            recent = Preferences.recentSongs
        }
    }

    func removeRecent(_ song: Song) {
        var list = Preferences.recentSongs
        list.removeAll { $0.FileHash == song.FileHash }
        Preferences.recentSongs = list
        recent = Preferences.recentSongs
    }

    func clearRecent() {
        Preferences.recentSongs = []
        recent = []
    }

    func clear() {
        Preferences.recentSongs = []
        Preferences.searchHistory = []
        recent = []
    }
}
