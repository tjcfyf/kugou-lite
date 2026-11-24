import Foundation

struct Song: Identifiable, Equatable, Codable {
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
    let FileID: Int?
    let AuthorID: Int?

    init?(json: [String: Any]) {
        guard let hash = json["FileHash"] as? String, !hash.isEmpty,
              let name = json["SongName"] as? String, !name.isEmpty else { return nil }
        FileHash = hash
        SongName = Song.cleanTitle(name)
        SingerName = (json["SingerName"] as? String) ?? ""
        AlbumID = Song.intValue(json["AlbumID"])
        AlbumName = json["AlbumName"] as? String
        Duration = Song.seconds(json["Duration"])
        Image = json["Image"] as? String
        Privilege = Song.intValue(json["Privilege"])
        PayType = Song.intValue(json["PayType"])
        MixSongID = Song.intValue(json["MixSongID"])
        Audioid = Song.intValue(json["Audioid"])
        FileID = Song.intValue(json["FileID"]) ?? Song.intValue(json["fileid"])
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

    /// 歌单接口偶尔把文件名直接当歌名，去掉音频扩展名后再显示。
    static func cleanTitle(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let extensions = [".mp3", ".flac", ".m4a", ".aac", ".wav", ".ogg", ".ape", ".wma"]
        let lower = name.lowercased()
        for ext in extensions where lower.hasSuffix(ext) {
            return String(name.dropLast(ext.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name
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

/// 酷狗歌曲评论。只保留界面真正需要的字段，避免接口字段变化时整页解析失败。
struct SongComment: Identifiable, Equatable {
    let id: String
    /// 酷狗评论接口里的原始评论 id；回复列表要用它作为 `tid`。
    let rawID: Int
    /// 评论所属楼层的 childrenid（cmtlist 根部返回，回复接口必须带上）。
    let childrenID: String?
    let userName: String
    let content: String
    let timeText: String
    let avatarURL: URL?
    let replyCount: Int

    var canOpenReplies: Bool { rawID > 0 && replyCount > 0 }

    init?(json: [String: Any], fallbackID: String, childrenID: String? = nil) {
        guard let content = json["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let rawID = Song.intValue(json["id"]) ?? 0
        self.rawID = rawID
        let itemChildren = (json["special_child_id"] as? String)
            ?? Song.intValue(json["special_child_id"]).map(String.init)
        self.childrenID = (itemChildren?.isEmpty == false ? itemChildren : nil) ?? childrenID
        id = "\(rawID)-\(fallbackID)"
        userName = (json["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "酷狗用户"
        self.content = content
        let rawTime = (json["addtime"] as? String) ?? ""
        timeText = rawTime.count >= 10 ? String(rawTime.prefix(10)) : rawTime
        let rawAvatar = json["user_pic"] as? String
        if var avatar = rawAvatar, !avatar.isEmpty {
            if avatar.hasPrefix("http://") { avatar = "https://" + avatar.dropFirst(7) }
            avatarURL = URL(string: avatar)
        } else {
            avatarURL = nil
        }
        replyCount = Song.intValue(json["reply_num"]) ?? 0
    }
}

struct CommentPage {
    let comments: [SongComment]
    let total: Int
    let hasMore: Bool
    /// cmtlist 根部的 childrenid；回复接口必须原样带回，否则会报“歌曲不存在”。
    let childrenID: String?
}

struct CommentReply: Identifiable, Equatable {
    let id: String
    let userName: String
    let content: String
    let timeText: String
    let avatarURL: URL?
    /// 回复的回复数量；目前只展示，不继续向下钻取。
    let replyCount: Int

    init?(json: [String: Any], fallbackID: String) {
        guard let content = json["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let rawID = Song.intValue(json["id"]) ?? 0
        id = "\(rawID)-\(fallbackID)"
        userName = (json["user_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "酷狗用户"
        self.content = content
        let rawTime = (json["addtime"] as? String) ?? ""
        timeText = rawTime.count >= 10 ? String(rawTime.prefix(10)) : rawTime
        if var avatar = json["user_pic"] as? String, !avatar.isEmpty {
            if avatar.hasPrefix("http://") { avatar = "https://" + avatar.dropFirst(7) }
            avatarURL = URL(string: avatar)
        } else {
            avatarURL = nil
        }
        replyCount = Song.intValue(json["comments_num"])
            ?? Song.intValue(json["reply_num"])
            ?? 0
    }
}

struct CommentReplyPage {
    let replies: [CommentReply]
    let total: Int
    let hasMore: Bool
}

struct CloudPlaylist: Identifiable, Equatable {
    let id: String
    let name: String
    let count: Int
    let cover: String?
    let listid: String?
    let type: Int
    let creatorID: String?
    /// 云歌单的创建/收藏/最后更新时间（秒）。接口字段名在不同账号上不稳定，
    /// 解析时兼容多种写法；拿不到时为 nil，排序保持接口原顺序。
    let createdAt: Int?

    init(id: String, name: String, count: Int, cover: String?,
         listid: String? = nil, type: Int = 0, creatorID: String? = nil,
         createdAt: Int? = nil) {
        self.id = id
        self.name = name
        self.count = count
        self.cover = cover
        self.listid = listid
        self.type = type
        self.creatorID = creatorID
        self.createdAt = createdAt
    }

    var isCollected: Bool { type == 1 }

    var globalID: String? {
        if let listid = listid, id != listid, !id.isEmpty { return id }
        if id.hasPrefix("collection_") { return id }
        return nil
    }
}

/// 云歌单排序：接口默认按创建/收藏顺序返回，资料库需要把最新加入的放最上面。
/// 有时间的排前面并按时间倒序；完全拿不到时间时保持接口原顺序，避免乱跳。
enum CloudPlaylistOrdering {
    static func newestFirst(_ list: [CloudPlaylist]) -> [CloudPlaylist] {
        guard list.contains(where: { $0.createdAt != nil }) else { return list }
        return list.enumerated().sorted { lhs, rhs in
            switch (lhs.element.createdAt, rhs.element.createdAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return lhs.offset < rhs.offset
            }
        }.map { $0.element }
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

struct LyricCandidate: Decodable, Identifiable, Equatable {
    let id: String
    let accesskey: String
    let song: String?
    let singer: String?
    let duration: Int?
    let krctype: Int?
    let language: String?

    var title: String {
        let value = song?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未命名歌词" : value
    }

    var subtitle: String {
        var pieces: [String] = []
        if let singer = singer, !singer.isEmpty { pieces.append(singer) }
        if let duration = duration, duration > 0 {
            let seconds = duration / 1000
            pieces.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        if krctype == 1 || krctype == 2 { pieces.append("逐字") }
        return pieces.joined(separator: " · ")
    }
}

struct LyricDownloadEnvelope: Decodable {
    let content: String?
    let fmt: String?
}
