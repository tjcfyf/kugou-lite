import Foundation

/// 外部平台歌单导入后保存在本地。曲目已经匹配成酷狗可播放的 Song，
/// 所以断网时也能看到列表，播放仍然走酷狗现有播放链路。
struct ImportedPlaylist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let source: String
    let coverURL: URL?
    var songs: [Song]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, source: String, coverURL: URL?, songs: [Song], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.source = source
        self.coverURL = coverURL
        self.songs = songs
        self.createdAt = createdAt
    }
}

final class ImportedPlaylistStore: ObservableObject {
    static let shared = ImportedPlaylistStore()

    @Published private(set) var playlists: [ImportedPlaylist] = []
    private let storageKey = "kg.imported.playlists.v1"

    private init() {
        load()
    }

    func add(_ playlist: ImportedPlaylist) {
        playlists.insert(playlist, at: 0)
        persist()
    }

    func remove(_ playlist: ImportedPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        persist()
    }

    func rename(_ playlist: ImportedPlaylist, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].name = name
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ImportedPlaylist].self, from: data) else {
            playlists = []
            return
        }
        playlists = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
