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

    func clear() {
        Preferences.recentSongs = []
        Preferences.searchHistory = []
        recent = []
        favorites = Preferences.favorites
    }
}
