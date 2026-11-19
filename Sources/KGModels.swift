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

    init?(json: [String: Any]) {
        guard let hash = json["FileHash"] as? String, !hash.isEmpty,
              let name = json["SongName"] as? String, !name.isEmpty else { return nil }
        FileHash = hash
        SongName = name
        SingerName = (json["SingerName"] as? String) ?? ""
        AlbumID = Song.intValue(json["AlbumID"])
        AlbumName = json["AlbumName"] as? String
        Duration = Song.intValue(json["Duration"])
        Image = json["Image"] as? String
        Privilege = Song.intValue(json["Privilege"])
        PayType = Song.intValue(json["PayType"])
        MixSongID = Song.intValue(json["MixSongID"])
        Audioid = Song.intValue(json["Audioid"])
    }

    static func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }

    var id: String { FileHash }
    var artist: String { SingerName.replacingOccurrences(of: "、", with: " / ") }

    var coverURL: URL? {
        guard var raw = Image, !raw.isEmpty else { return nil }
        raw = raw.replacingOccurrences(of: "{size}", with: "240")
        if raw.hasPrefix("http://") { raw = "https://" + raw.dropFirst(7) }
        return URL(string: raw)
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
