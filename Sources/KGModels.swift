import Foundation

struct Song: Identifiable, Equatable, Decodable {
    let FileHash: String
    let SongName: String
    let SingerName: String
    let AlbumID: Int?
    let AlbumName: String?
    let Duration: Int?
    let Image: String?
    let Privilege: Int?
    let PayType: Int?

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

struct SearchEnvelope: Decodable {
    let status: Int?
    let error_code: Int?
    let errcode: Int?
    let error: String?
    let data: SearchData?

    struct SearchData: Decodable {
        let total: Int?
        let lists: [Song]?
    }
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
