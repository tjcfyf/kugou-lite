import Foundation

enum KGService {
    private static var qualityMap: [String: String] = [:]

    static func quality(for hash: String) -> String? { qualityMap[hash.lowercased()] }
    private static func remember(_ quality: String, for hash: String) { qualityMap[hash.lowercased()] = quality }
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

    /// 每日推荐，登录后可用。
    static func recommend() async throws -> [Song] {
        let data = try await KGApi.shared.post(
            path: "/everyday_song_recommend",
            params: ["platform": "ios"],
            router: "everydayrec.service.kugou.com",
            lite: true
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any] else {
            throw KGError.server("推荐解析失败")
        }
        let list = (payload["song_list"] as? [[String: Any]])
            ?? (payload["list"] as? [[String: Any]])
            ?? []
        let songs = list.compactMap { item -> Song? in
            var json: [String: Any] = [:]
            if let hash = item["hash"] as? String ?? item["FileHash"] as? String { json["FileHash"] = hash }
            if let name = item["songname"] as? String ?? item["SongName"] as? String { json["SongName"] = name }
            if let singer = item["author_name"] as? String ?? item["SingerName"] as? String { json["SingerName"] = singer }
            if let album = item["album_id"] as? String ?? item["AlbumID"] as? String { json["AlbumID"] = album }
            if let pay = item["pay_type"] { json["PayType"] = pay }
            if let mix = item["mixsongid"] ?? item["MixSongID"] { json["MixSongID"] = mix }
            if let audio = item["album_audio_id"] ?? item["Audioid"] { json["Audioid"] = audio }
            if let image = findImage(in: item) { json["Image"] = image }
            if let duration = item["duration"] ?? item["timelength"] { json["Duration"] = duration }
            if let albumName = item["album_name"] as? String { json["AlbumName"] = albumName }
            return Song(json: json)
        }
        return songs
    }

    /// 推荐接口的封面字段名不稳定，递归找一圈。
    private static func findImage(in value: Any) -> String? {
        let keys = ["album_image", "albumimg", "album_img", "img", "image", "cover", "union_cover", "pic"]
        if let dict = value as? [String: Any] {
            for key in keys {
                if let raw = dict[key] as? String, raw.lowercased().hasPrefix("http") {
                    return raw.replacingOccurrences(of: "{size}", with: "240")
                }
            }
            for child in dict.values {
                if let found = findImage(in: child) { return found }
            }
        } else if let list = value as? [Any] {
            for child in list {
                if let found = findImage(in: child) { return found }
            }
        }
        return nil
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
        if KGApi.shared.token != nil, KGApi.shared.userid != 0 {
            _ = await KGDevice.registerIfNeeded()
            KGApi.shared.lastMixSongID = song.MixSongID ?? 0
            let audioID = song.MixSongID ?? song.Audioid
            for quality in Preferences.quality.fallbacks {
                if let url = try? await liteURL(hash: song.FileHash,
                                                albumID: song.AlbumID,
                                                albumAudioID: audioID,
                                                quality: quality.rawValue) {
                    remember(quality.short, for: song.FileHash)
                    return url
                }
                if let url = try? await authorizedURL(hash: song.FileHash,
                                                      albumID: song.AlbumID,
                                                      albumAudioID: audioID,
                                                      quality: quality.rawValue) {
                    remember(quality.short, for: song.FileHash)
                    return url
                }
            }
        }

        // 拿不到完整流时，再要一次试听片段（概念版免费用户也能听 30~60 秒）。
        if let url = try? await trialURL(hash: song.FileHash, albumID: song.AlbumID) {
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
    static func liteURL(hash: String, albumID: Int?, albumAudioID: Int? = nil, quality: String = Preferences.quality.rawValue) async throws -> URL? {
        let appid = 3116
        let key = KGSign.playKey(
            hash: hash,
            mid: KGApi.shared.mid,
            userid: KGApi.shared.userid,
            appid: appid,
            lite: true
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
                "quality": quality,
                "album_audio_id": "\(albumAudioID ?? 0)",
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
    /// 会员取流：先拿播放授权（auth），再用授权换 /v5/url。概念版会员必须走这一步。
    static func authorizedURL(hash: String, albumID: Int?, albumAudioID: Int?, quality: String = Preferences.quality.rawValue) async throws -> URL? {
        guard let auth = try await authorization(hash: hash, albumAudioID: albumAudioID) else { return nil }
        let key = KGSign.playKey(hash: hash, mid: KGApi.shared.mid, userid: KGApi.shared.userid, appid: 3116, lite: true)
        let data = try await KGApi.shared.get(
            path: "/v5/url",
            params: [
                "album_id": "\(albumID ?? 0)",
                "area_code": "1",
                "hash": hash.lowercased(),
                "ssa_flag": "is_fromtrack",
                "version": "11430",
                "open_time": "\(auth.openTime)",
                "page_id": "967177915",
                "quality": quality,
                "album_audio_id": "\(albumAudioID ?? 0)",
                "behavior": "play",
                "pid": "411",
                "module_id": "51",
                "cmd": "26",
                "mtype": "0",
                "ptype": "0",
                "need_ogg": "1",
                "auth": auth.value,
                "ppage_id": "356753938,823673182,967485191",
                "clientver": "11561",
                "pidversion": "3001",
                "cdnBackup": "1",
                "dfid": KGApi.shared.dfid,
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

    /// 授权链路自检，供诊断面板输出。
    static func authProbe(hash: String, albumAudioID: Int?) async -> String {
        do {
            let device = try await verifyAuth()
            let auth = try await authorization(hash: hash, albumAudioID: albumAudioID)
            let openTime = auth?.openTime ?? 0
            return "verify=\(device.count)字 authorization=\(auth == nil ? "无" : "有") open_time=\(openTime)"
        } catch {
            return "授权失败：\((error as? LocalizedError)?.errorDescription ?? "未知")"
        }
    }

    /// 权益查询（/v2/get_res_privilege/lite），诊断面板用来确认真实能不能播。
    static func privilegeProbe(hash: String) async -> String {
        let body: [String: Any] = [
            "appid": 3116,
            "area_code": 1,
            "behavior": "play",
            "clientver": 11440,
            "need_hash_offset": 1,
            "relate": 1,
            "support_verify": 1,
            "resource": [["type": "audio", "page_id": 0, "hash": hash.lowercased(), "album_id": 0]],
            "qualities": ["128", "320", "flac", "high"],
        ]
        guard let data = try? await KGApi.shared.post(
            path: "/v2/get_res_privilege/lite",
            params: [:],
            body: body,
            router: "media.store.kugou.com",
            lite: true
        ), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "权益查询失败"
        }
        guard let list = root["data"] as? [[String: Any]], let first = list.first else {
            return "权益无数据：\(String(data: data.prefix(120), encoding: .utf8) ?? "")"
        }
        let privilege = Song.intValue(first["privilege"]) ?? -1
        let status = Song.intValue(first["status"]) ?? -1
        let payType = Song.intValue(first["pay_type"]) ?? -1
        var qualities: [String] = []
        if let goods = first["relate_goods"] as? [[String: Any]] {
            for item in goods {
                let q = Song.intValue(item["quality"]) ?? 0
                let exists = Song.intValue(item["exists"]) ?? 0
                qualities.append("\(q)@\(exists)")
            }
        }
        return "privilege=\(privilege) status=\(status) pay_type=\(payType) goods=\(qualities.prefix(6).joined(separator: ","))"
    }

    /// 带授权的取流结果，把服务端返回码摊开。
    static func streamProbe(hash: String, albumAudioID: Int?) async -> String {
        guard let auth = try? await authorization(hash: hash, albumAudioID: albumAudioID) else {
            return "授权失败"
        }
        let key = KGSign.playKey(hash: hash, mid: KGApi.shared.mid, userid: KGApi.shared.userid, appid: 3116, lite: true)
        let params: [String: String] = [
            "album_id": "0", "area_code": "1", "hash": hash.lowercased(), "ssa_flag": "is_fromtrack",
            "version": "11430", "open_time": "\(auth.openTime)", "page_id": "967177915",
            "quality": "128", "album_audio_id": "\(albumAudioID ?? 0)", "behavior": "play",
            "pid": "411", "module_id": "51", "cmd": "26", "mtype": "0", "ptype": "0",
            "need_ogg": "1", "auth": auth.value, "ppage_id": "356753938,823673182,967485191",
            "clientver": "11561", "pidversion": "3001", "cdnBackup": "1",
            "dfid": KGApi.shared.dfid, "key": key,
        ]
        guard let data = try? await KGApi.shared.get(
            path: "/v5/url", params: params, router: "trackercdn.kugou.com", lite: true
        ), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "取流无响应"
        }
        let status = Song.intValue(root["status"]) ?? -1
        let errcode = Song.intValue(root["errcode"]) ?? 0
        let error = (root["error"] as? String) ?? ""
        let urlCount = (root["url"] as? [String])?.count ?? 0
        return "status=\(status) errcode=\(errcode) url=\(urlCount) error=\(error) dfid=\(KGApi.shared.dfid.prefix(6))"
    }

    private struct PlayAuth {
        let value: String
        let openTime: Int
    }

    private static var cachedAuth: String?
    private static var cachedAuthTime: TimeInterval = 0

    /// /v1/user_verify 拿设备级播放授权，缓存一小时。
    private static func verifyAuth() async throws -> String {
        if let cachedAuth = cachedAuth, Date().timeIntervalSince1970 - cachedAuthTime < 3600 {
            return cachedAuth
        }
        let data = try await KGApi.shared.get(
            path: "/v1/user_verify",
            params: ["module_id": "51"],
            router: "trackercdngz.kugou.com",
            lite: true
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let auth = payload["auth"] as? String, !auth.isEmpty else {
            throw KGError.server("没有拿到播放授权")
        }
        cachedAuth = auth
        cachedAuthTime = Date().timeIntervalSince1970
        return auth
    }

    /// 单曲授权：把设备授权换成这首歌的 auth + open_time。
    private static func authorization(hash: String, albumAudioID: Int?) async throws -> PlayAuth? {
        let device = try await verifyAuth()
        let data = try await KGApi.shared.get(
            path: "/v1/authorization",
            params: [
                "authorization": device,
                "module_id": "51",
                "album_audio_id": "\(albumAudioID ?? 0)",
                "clientver": "11561",
                "hash": hash.lowercased(),
            ],
            router: "trackercdngz.kugou.com",
            lite: true
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let payload = (root["data"] as? [String: Any]) ?? root
        var value = (payload["auth"] as? String) ?? ""
        if value.isEmpty, let inner = payload["data"] as? [String: Any], let auth = inner["auth"] as? String {
            value = auth
        }
        if value.isEmpty { value = device }
        let openTime = Song.intValue(payload["open_time"]) ?? 0
        return PlayAuth(value: value, openTime: openTime)
    }

    /// 试听流：IsFreePart=1，VIP 歌也能拿到一段可播的片段。
    static func trialURL(hash: String, albumID: Int?) async throws -> URL? {
        let appid = 3116
        let key = KGSign.playKey(
            hash: hash,
            mid: KGApi.shared.mid,
            userid: KGApi.shared.userid,
            appid: appid,
            lite: true
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
                "IsFreePart": "1",
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
