import Foundation

struct Song: Identifiable, Equatable {
    let FileHash: String
    let SongName: String
    let SingerName: String
    let AlbumID: Int?
    let AlbumName: String?
    let Duration: Int?
    let Image: String?
    let Privilege: Int?
    let PayType: Int?
    let MixSongID: Int?
    let Audioid: Int?
    let AuthorID: Int?

    init?(json: [String: Any]) {
        guard let hash = json["FileHash"] as? String, !hash.isEmpty,
              let name = json["SongName"] as? String, !name.isEmpty else { return nil }
        FileHash = hash
        SongName = name
        SingerName = (json["SingerName"] as? String) ?? ""
        AlbumID = Song.intValue(json["AlbumID"])
        AlbumName = json["AlbumName"] as? String
        Duration = Song.seconds(json["Duration"])
        Image = json["Image"] as? String
        Privilege = Song.intValue(json["Privilege"])
        PayType = Song.intValue(json["PayType"])
        MixSongID = Song.intValue(json["MixSongID"])
        Audioid = Song.intValue(json["Audioid"])
        AuthorID = Song.intValue(json["AuthorID"])
            ?? (json["SingerId"] as? [Any])?.first.flatMap { Song.intValue($0) }
    }

    static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    /// 不同接口的时长单位不统一：搜索给秒，榜单给毫秒。
    static func seconds(_ raw: Any?) -> Int? {
        guard let value = intValue(raw) else { return nil }
        return value > 10000 ? value / 1000 : value
    }

    var id: String { FileHash }
    var artist: String { SingerName.replacingOccurrences(of: "、", with: " / ") }

    var coverURL: URL? {
        guard var raw = Image, !raw.isEmpty else { return nil }
        raw = raw.replacingOccurrences(of: "{size}", with: "240")
        if raw.hasPrefix("http://") { raw = "https://" + raw.dropFirst(7) }
        return URL(string: raw)
    }

    func withImage(_ raw: String) -> Song {
        var value = dict
        value["image"] = raw
        return Song(dict: value) ?? self
    }

    /// 需要会员或付费的曲目：仅作标记，播放时由酷狗接口决定实际能否出流。
    var needsPurchase: Bool {
        (Privilege ?? 0) > 0 && (PayType ?? 0) > 0
    }
}

struct CloudPlaylist: Identifiable, Equatable {
    let id: String
    let name: String
    let count: Int
    let cover: String?
    let listid: String?
    let type: Int
    let creatorID: String?

    init(id: String, name: String, count: Int, cover: String?,
         listid: String? = nil, type: Int = 0, creatorID: String? = nil) {
        self.id = id
        self.name = name
        self.count = count
        self.cover = cover
        self.listid = listid
        self.type = type
        self.creatorID = creatorID
    }

    var isCollected: Bool { type == 1 }

    var globalID: String? {
        if let listid = listid, id != listid, !id.isEmpty { return id }
        if id.hasPrefix("collection_") { return id }
        return nil
    }
}

struct RankItem: Identifiable, Equatable {
    let id: Int
    let name: String
    let cover: String?
    let intro: String
}

struct PlayInfoEnvelope {
    let url: String?
    let backups: [String]
    let error: String?
}

struct LyricSearchEnvelope: Decodable {
    let candidates: [LyricCandidate]?
}

struct LyricCandidate: Decodable {
    let id: String
    let accesskey: String
}

struct LyricDownloadEnvelope: Decodable {
    let content: String?
    let fmt: String?
}
