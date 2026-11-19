import Foundation

/// 音质设置。概念版会员越高，能拿到的档位越高；失败会自动往下降。
enum AudioQuality: String, CaseIterable, Identifiable {
    case standard = "128"
    case high = "320"
    case lossless = "flac"
    case hires = "high"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "标准 128K"
        case .high: return "高品 320K"
        case .lossless: return "无损 FLAC"
        case .hires: return "Hi-Res"
        }
    }

    var short: String {
        switch self {
        case .standard: return "128"
        case .high: return "320"
        case .lossless: return "FLAC"
        case .hires: return "Hi-Res"
        }
    }

    /// 取流失败时依次尝试的顺序。
    var fallbacks: [AudioQuality] {
        switch self {
        case .standard: return [.standard]
        case .high: return [.high, .standard]
        case .lossless: return [.lossless, .high, .standard]
        case .hires: return [.hires, .lossless, .high, .standard]
        }
    }
}

enum Preferences {
    private static let qualityKey = "kg.quality"
    private static let historyKey = "kg.search.history"
    private static let recentKey = "kg.recent.songs"
    private static let favoriteKey = "kg.favorite.songs"

    static var quality: AudioQuality {
        get { AudioQuality(rawValue: UserDefaults.standard.string(forKey: qualityKey) ?? "") ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: qualityKey) }
    }

    static var searchHistory: [String] {
        get { UserDefaults.standard.stringArray(forKey: historyKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(12)), forKey: historyKey) }
    }

    static func addSearch(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = searchHistory
        list.removeAll { $0 == trimmed }
        list.insert(trimmed, at: 0)
        searchHistory = list
    }

    static var recentSongs: [Song] {
        get {
            guard let raw = UserDefaults.standard.array(forKey: recentKey) as? [[String: Any]] else { return [] }
            return raw.compactMap { Song(dict: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.prefix(50).map { $0.dict }, forKey: recentKey)
        }
    }

    static var favorites: [Song] {
        get {
            guard let raw = UserDefaults.standard.array(forKey: favoriteKey) as? [[String: Any]] else { return [] }
            return raw.compactMap { Song(dict: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.prefix(200).map { $0.dict }, forKey: favoriteKey)
        }
    }

    static func isFavorite(_ song: Song) -> Bool {
        favorites.contains { $0.FileHash == song.FileHash }
    }

    @discardableResult
    static func toggleFavorite(_ song: Song) -> Bool {
        var list = favorites
        if let index = list.firstIndex(where: { $0.FileHash == song.FileHash }) {
            list.remove(at: index)
            favorites = list
            return false
        }
        list.insert(song, at: 0)
        favorites = list
        return true
    }

    static func addRecent(_ song: Song) {
        var list = recentSongs
        list.removeAll { $0.FileHash == song.FileHash }
        list.insert(song, at: 0)
        recentSongs = list
        NotificationCenter.default.post(name: .kgRecentChanged, object: nil)
    }
}

extension Notification.Name {
    static let kgRecentChanged = Notification.Name("kg.recent.changed")
}

extension Song {
    init?(dict: [String: Any]) {
        var json: [String: Any] = [
            "FileHash": dict["hash"] ?? "",
            "SongName": dict["name"] ?? "",
            "SingerName": dict["singer"] ?? "",
        ]
        if let v = dict["albumID"] { json["AlbumID"] = v }
        if let v = dict["album"] { json["AlbumName"] = v }
        if let v = dict["duration"] { json["Duration"] = v }
        if let v = dict["image"] { json["Image"] = v }
        if let v = dict["privilege"] { json["Privilege"] = v }
        if let v = dict["payType"] { json["PayType"] = v }
        if let v = dict["mixSongID"] { json["MixSongID"] = v }
        if let v = dict["audioID"] { json["Audioid"] = v }
        self.init(json: json)
    }

    var dict: [String: Any] {
        var value: [String: Any] = [
            "hash": FileHash,
            "name": SongName,
            "singer": SingerName,
        ]
        if let v = AlbumID { value["albumID"] = v }
        if let v = AlbumName { value["album"] = v }
        if let v = Duration { value["duration"] = v }
        if let v = Image { value["image"] = v }
        if let v = Privilege { value["privilege"] = v }
        if let v = PayType { value["payType"] = v }
        if let v = MixSongID { value["mixSongID"] = v }
        if let v = Audioid { value["audioID"] = v }
        return value
    }
}
