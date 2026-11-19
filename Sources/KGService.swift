import Foundation

enum KGService {
    static func search(_ keyword: String, page: Int = 1, pageSize: Int = 30) async throws -> [Song] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let data = try await KGApi.shared.get(
            path: "/v2/search/song",
            params: [
                "keyword": trimmed,
                "page": "\(page)",
                "pagesize": "\(pageSize)",
                "platform": "AndroidFilter",
                "iscorrection": "1",
                "privilegefilter": "0",
                "area_code": "1",
                "dopicfull": "1",
            ],
            router: "complexsearch.kugou.com"
        )

        // 酷狗对字段类型并不总是稳定（数字偶尔是字符串），所以这里手工解析，
        // 避免一整条记录因类型不符而整批解码失败。
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("返回格式异常")
        }
        if let code = Song.intValue(root["errcode"]), code != 0 {
            throw KGError.server("搜索被限制（\(code)）")
        }
        if let message = root["error_msg"] as? String, !message.isEmpty, Song.intValue(root["status"]) != 1 {
            throw KGError.server(message)
        }
        guard let dataDict = root["data"] as? [String: Any],
              let lists = dataDict["lists"] as? [[String: Any]] else {
            let snippet = String(data: data.prefix(240), encoding: .utf8) ?? ""
            throw KGError.server("返回异常：\(snippet)")
        }
        let songs = lists.compactMap { Song(json: $0) }
        if songs.isEmpty, let total = Song.intValue(dataDict["total"]), total > 0 {
            throw KGError.server("解析失败（\(total) 条）")
        }
        return songs
    }

    static func playInfo(hash: String, albumID: Int?) async throws -> PlayInfoEnvelope {
        var components = URLComponents(string: "https://m.kugou.com/app/i/getSongInfo.php")!
        var items = [
            URLQueryItem(name: "cmd", value: "playInfo"),
            URLQueryItem(name: "hash", value: hash),
        ]
        if let albumID = albumID, albumID > 0 {
            items.append(URLQueryItem(name: "album_id", value: "\(albumID)"))
        }
        components.queryItems = items
        guard let url = components.url else { throw KGError.network }

        let data = try await KGApi.shared.plain(url, cookie: true)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("播放地址解析失败")
        }
        let urlString = (object["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let backups = (object["backup_url"] as? [String]) ?? []
        let message = object["error"] as? String
        return PlayInfoEnvelope(
            url: (urlString?.isEmpty ?? true) ? nil : urlString,
            backups: backups.filter { !$0.isEmpty },
            error: message
        )
    }

    static func playURL(hash: String, albumID: Int?) async throws -> URL {
        let info = try await playInfo(hash: hash, albumID: albumID)
        if let raw = info.url, let url = URL(string: raw) { return url }
        for raw in info.backups {
            if let url = URL(string: raw) { return url }
        }
        throw KGError.server(info.error ?? "这首歌暂时拿不到播放地址")
    }

    /// 登录后优先走概念版（lite）的签名取流；未登录或失败再回落到移动端接口。
    static func playURL(for song: Song) async throws -> URL {
        if KGApi.shared.token != nil,
           let url = try? await liteURL(hash: song.FileHash, albumID: song.AlbumID) {
            return url
        }

        let info = try? await playInfo(hash: song.FileHash, albumID: song.AlbumID)
        if let raw = info?.url, let url = URL(string: raw) { return url }
        if let raw = info?.backups.first, let url = URL(string: raw) { return url }

        if song.needsPurchase && KGApi.shared.token == nil {
            throw KGError.server("这首歌需要酷狗会员，登录后就能听")
        }
        throw KGError.server(info?.error ?? "这首歌暂时拿不到播放地址")
    }

    /// 概念版（lite）取流。畅听/概念会员只在 lite 的 appid 下被识别，
    /// 用标准版 appid 请求会被当成免费用户。
    static func liteURL(hash: String, albumID: Int?) async throws -> URL? {
        let appid = 3116
        let key = KGSign.playKey(
            hash: hash,
            mid: KGApi.shared.mid,
            userid: KGApi.shared.userid,
            appid: appid
        )
        let data = try await KGApi.shared.get(
            path: "/v5/url",
            params: [
                "album_id": "\(albumID ?? 0)",
                "area_code": "1",
                "hash": hash.lowercased(),
                "ssa_flag": "is_fromtrack",
                "version": "11430",
                "page_id": "967177915",
                "quality": "128",
                "album_audio_id": "0",
                "behavior": "play",
                "pid": "411",
                "cmd": "26",
                "pidversion": "3001",
                "IsFreePart": "0",
                "ppage_id": "356753938,823673182,967485191",
                "cdnBackup": "1",
                "module": "",
                "clientver": "11430",
                "key": key,
            ],
            router: "trackercdn.kugou.com",
            lite: true
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let list = root["url"] as? [String], let first = list.first, let url = URL(string: first) {
            return url
        }
        if let single = root["url"] as? String, let url = URL(string: single) {
            return url
        }
        return nil
    }

    static func lyric(hash: String, title: String) async throws -> [LyricLine] {
        var searchComponents = URLComponents(string: "https://krcs.kugou.com/search")!
        searchComponents.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "mobi"),
            URLQueryItem(name: "keyword", value: title),
            URLQueryItem(name: "hash", value: hash),
        ]
        guard let searchURL = searchComponents.url else { return [] }

        let searchData = try await KGApi.shared.plain(searchURL)
        guard let envelope = try? JSONDecoder().decode(LyricSearchEnvelope.self, from: searchData),
              let candidate = envelope.candidates?.first else { return [] }

        var downloadComponents = URLComponents(string: "https://lyrics.kugou.com/download")!
        downloadComponents.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "id", value: candidate.id),
            URLQueryItem(name: "accesskey", value: candidate.accesskey),
            URLQueryItem(name: "fmt", value: "lrc"),
            URLQueryItem(name: "charset", value: "utf8"),
        ]
        guard let downloadURL = downloadComponents.url else { return [] }

        let downloadData = try await KGApi.shared.plain(downloadURL)
        guard let envelope = try? JSONDecoder().decode(LyricDownloadEnvelope.self, from: downloadData),
              let content = envelope.content,
              let bytes = Data(base64Encoded: content),
              let text = String(data: bytes, encoding: .utf8) else { return [] }
        return LyricParser.parse(text)
    }
}
