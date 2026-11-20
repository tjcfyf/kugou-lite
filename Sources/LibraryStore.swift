import Foundation
import Combine

/// 收藏与最近播放的单一数据源，改动后界面立刻刷新。
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var recent: [Song] = Preferences.recentSongs
    @Published private(set) var favorites: [Song] = Preferences.favorites

    private init() {}

    func refresh() {
        recent = Preferences.recentSongs
        favorites = Preferences.favorites
    }

    func addRecent(_ song: Song) {
        Preferences.addRecent(song)
        recent = Preferences.recentSongs
    }

    @discardableResult
    func toggleFavorite(_ song: Song) -> Bool {
        let added = Preferences.toggleFavorite(song)
        favorites = Preferences.favorites
        return added
    }

    private var isEnriching = false

    /// 老版本存下来的收藏/最近播放可能没有封面，按 hash 回查一次并写回本地。
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

        var favoriteList = Preferences.favorites
        for index in favoriteList.indices where (favoriteList[index].Image ?? "").isEmpty {
            if let cover = await KGService.songCover(hash: favoriteList[index].FileHash) {
                favoriteList[index] = favoriteList[index].withImage(cover)
            }
        }
        if favoriteList != favorites {
            Preferences.favorites = favoriteList
            favorites = Preferences.favorites
        }
    }

    func clear() {
        Preferences.recentSongs = []
        Preferences.searchHistory = []
        recent = []
        favorites = Preferences.favorites
    }
}
