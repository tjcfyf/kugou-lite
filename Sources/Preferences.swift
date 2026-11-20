import Foundation
import CoreGraphics
import SwiftUI

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

enum PlayMode: String, CaseIterable, Identifiable {
    case sequential
    case loop
    case single
    case shuffle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: return "顺序播放"
        case .loop: return "列表循环"
        case .single: return "单曲循环"
        case .shuffle: return "随机播放"
        }
    }

    var icon: String {
        switch self {
        case .sequential: return "arrow.right"
        case .loop: return "repeat"
        case .single: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }

    var next: PlayMode {
        switch self {
        case .sequential: return .loop
        case .loop: return .single
        case .single: return .shuffle
        case .shuffle: return .sequential
        }
    }
}

enum PlaybackSpeed: Float, CaseIterable, Identifiable {
    case x075 = 0.75
    case x100 = 1.0
    case x125 = 1.25
    case x150 = 1.5
    case x200 = 2.0

    var id: Float { rawValue }

    var title: String {
        switch self {
        case .x075: return "0.75x"
        case .x100: return "1.0x"
        case .x125: return "1.25x"
        case .x150: return "1.5x"
        case .x200: return "2.0x"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .dark: return "深色"
        case .light: return "浅色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

enum LyricTextSize: Int, CaseIterable, Identifiable {
    case small = 0
    case normal = 1
    case large = 2

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .small: return "小"
        case .normal: return "标准"
        case .large: return "大"
        }
    }
    var fontSize: CGFloat {
        switch self {
        case .small: return 13
        case .normal: return 15
        case .large: return 18
        }
    }
    var next: LyricTextSize { LyricTextSize(rawValue: (rawValue + 1) % 3) ?? .normal }
}

enum Preferences {
    private static let qualityKey = "kg.quality"
    private static let historyKey = "kg.search.history"
    private static let recentKey = "kg.recent.songs"
    private static let favoriteKey = "kg.favorite.songs"
    private static let playModeKey = "kg.play.mode"
    private static let lyricSizeKey = "kg.lyric.size"
    private static let playbackRateKey = "kg.playback.rate"
    static let sleepWaitKey = "kg.sleep.waitforend"
    static let lyricOffsetKey = "kg.lyric.offset"
    static let lyricFollowKey = "kg.lyric.follow"
    static let lyricTranslationKey = "kg.lyric.translation"
    static let lyricRomanizationKey = "kg.lyric.romanization"
    static let lyricPhotoModeKey = "kg.lyric.photo"
    static let lyricFilterKey = "kg.lyric.filter"
    static let audioEQEnabledKey = "kg.audio.eq.enabled"
    static let audioEQGainsKey = "kg.audio.eq.gains"

    static var lyricOffsetMs: Int {
        get { UserDefaults.standard.integer(forKey: lyricOffsetKey) }
        set { UserDefaults.standard.set(newValue, forKey: lyricOffsetKey) }
    }

    static var lyricFilter: String {
        get { UserDefaults.standard.string(forKey: lyricFilterKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: lyricFilterKey) }
    }
    static let themeModeKey = "kg.theme.mode"

    static var quality: AudioQuality {
        get { AudioQuality(rawValue: UserDefaults.standard.string(forKey: qualityKey) ?? "") ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: qualityKey) }
    }

    static var themeMode: AppTheme {
        get { AppTheme(rawValue: UserDefaults.standard.string(forKey: themeModeKey) ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: themeModeKey) }
    }

    static var lyricSize: LyricTextSize {
        get {
            guard let raw = UserDefaults.standard.object(forKey: lyricSizeKey) as? Int,
                  let value = LyricTextSize(rawValue: raw) else { return .normal }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lyricSizeKey) }
    }

    static var playMode: PlayMode {
        get { PlayMode(rawValue: UserDefaults.standard.string(forKey: playModeKey) ?? "") ?? .loop }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: playModeKey) }
    }

    static var playbackRate: Float {
        get {
            let value = UserDefaults.standard.double(forKey: playbackRateKey)
            guard value > 0, value >= 0.5, value <= 2.0 else { return 1.0 }
            return Float(value)
        }
        set {
            let clamped = min(max(newValue, 0.5), 2.0)
            UserDefaults.standard.set(Double(clamped), forKey: playbackRateKey)
        }
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

    static func removeSearch(_ keyword: String) {
        var list = searchHistory
        list.removeAll { $0 == keyword }
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
            NotificationCenter.default.post(name: .kgFavoritesChanged, object: nil)
            return false
        }
        list.insert(song, at: 0)
        favorites = list
        NotificationCenter.default.post(name: .kgFavoritesChanged, object: nil)
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
    static let kgFavoritesChanged = Notification.Name("kg.favorites.changed")
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
        if let v = dict["fileID"] { json["FileID"] = v }
        if let v = dict["authorID"] { json["AuthorID"] = v }
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
        if let v = FileID { value["fileID"] = v }
        if let v = AuthorID { value["authorID"] = v }
        return value
    }
}
