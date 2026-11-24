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
            body: [
                "platform": "ios",
                "userid": KGApi.shared.userid
            ],
            router: "everydayrec.service.kugou.com",
            lite: true
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("推荐解析失败")
        }
        var list: [[String: Any]] = []
        func append(_ value: Any?) {
            if let items = value as? [[String: Any]] { list.append(contentsOf: items) }
        }
        if let payload = root["data"] as? [String: Any] {
            append(payload["song_list"])
            append(payload["songs"])
            append(payload["list"])
            if let info = payload["info"] as? [String: Any] {
                append(info["song_list"])
                append(info["songs"])
                append(info["list"])
            }
        }
        append(root["data"])
        append(root["song_list"])
        append(root["list"])
        if list.isEmpty { throw KGError.server("今天暂时没有推荐歌曲") }
        let songs = list.compactMap { item -> Song? in
            var json: [String: Any] = [:]
            if let hash = item["hash"] as? String ?? item["FileHash"] as? String { json["FileHash"] = hash }
            if let name = item["songname"] as? String ?? item["SongName"] as? String { json["SongName"] = name }
            if let singer = item["author_name"] as? String ?? item["SingerName"] as? String { json["SingerName"] = singer }
            if let album = Song.intValue(item["album_id"] ?? item["AlbumID"]) { json["AlbumID"] = album }
            if let pay = item["pay_type"] { json["PayType"] = pay }
            if let mix = item["mixsongid"] ?? item["MixSongID"] { json["MixSongID"] = mix }
            if let audio = item["album_audio_id"] ?? item["Audioid"] { json["Audioid"] = audio }
            if let image = findImage(in: item) { json["Image"] = image }
            if let duration = item["time_length"] ?? item["duration"] ?? item["timelength"] { json["Duration"] = duration }
            if let albumName = item["album_name"] as? String { json["AlbumName"] = albumName }
            if let author = item["author_id"] { json["AuthorID"] = author }
            return Song(json: json)
        }
        return songs
    }

    // MARK: - 歌曲评论

    /// 酷狗歌曲评论列表。评论池无需登录即可读取，只做展示，不发送评论。
    static func comments(for song: Song, page: Int = 1, pageSize: Int = 20) async throws -> CommentPage {
        let mixSongID = [song.MixSongID, song.Audioid]
            .compactMap { $0 }
            .first(where: { $0 > 0 })
        guard let mixSongID = mixSongID else {
            throw KGError.server("当前歌曲缺少评论 ID")
        }
        let data = try await KGApi.shared.post(
            path: "/mcomment/v1/cmtlist",
            params: [
                "ver": "6",
                "mixsongid": "\(mixSongID)",
                "need_show_image": "1",
                "p": "\(page)",
                "pagesize": "\(pageSize)",
                "show_classify": "0",
                "show_hotword_list": "0",
                "extdata": "0",
                "code": "fc4be23b4e972707f36b8a828a93ba8a"
            ]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("评论返回格式异常")
        }
        if let code = Song.intValue(root["err_code"]), code != 0 {
            let message = (root["msg"] as? String) ?? (root["message"] as? String) ?? "评论加载失败"
            throw KGError.server(message)
        }
        if let status = Song.intValue(root["status"]), status != 1 {
            let message = (root["msg"] as? String) ?? (root["message"] as? String) ?? "评论加载失败"
            throw KGError.server(message)
        }

        let list = (root["list"] as? [[String: Any]]) ?? []
        let childrenID = (root["childrenid"] as? String)
            ?? Song.intValue(root["childrenid"]).map(String.init)
        let comments = list.enumerated().compactMap { index, item in
            SongComment(json: item, fallbackID: "\(page)-\(index)", childrenID: childrenID)
        }
        let total = Song.intValue(root["combine_count"]) ?? Song.intValue(root["count"]) ?? comments.count
        let maxPage = Song.intValue(root["maxPage"]) ?? 0
        let hasMore: Bool
        if comments.isEmpty {
            hasMore = false
        } else if maxPage > 0 {
            hasMore = page < maxPage
        } else {
            hasMore = list.count >= pageSize
        }
        return CommentPage(comments: comments, total: total, hasMore: hasMore,
                           childrenID: childrenID)
    }

    /// 楼中楼回复列表。酷狗的 `replylist` 只给 6 条热门回复，完整列表必须用
    /// `hot_replylist`，并同时带 `childrenid`（楼层 id）和 `tid`（主评论原始 id）。
    /// 这个接口对签名很敏感：POST 不能带 body，否则会返回 err signature。
    static func replies(for song: Song,
                        comment: SongComment,
                        page: Int = 1,
                        pageSize: Int = 30) async throws -> CommentReplyPage {
        guard let childrenID = comment.childrenID, !childrenID.isEmpty else {
            throw KGError.server("这条评论缺少回复楼层 ID")
        }
        let mixSongID = [song.MixSongID, song.Audioid]
            .compactMap { $0 }
            .first(where: { $0 > 0 })
        guard let mixSongID = mixSongID else {
            throw KGError.server("当前歌曲缺少评论 ID")
        }
        let data = try await KGApi.shared.post(
            path: "/mcomment/v1/hot_replylist",
            params: [
                "childrenid": childrenID,
                "tid": "\(comment.rawID)",
                "mixsongid": "\(mixSongID)",
                "p": "\(page)",
                "pagesize": "\(pageSize)",
                "show_classify": "1",
                "show_hotword_list": "1",
                "code": "fc4be23b4e972707f36b8a828a93ba8a"
            ]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("回复返回格式异常")
        }
        if let code = Song.intValue(root["err_code"]), code != 0 {
            let message = (root["msg"] as? String) ?? (root["message"] as? String) ?? "回复加载失败"
            throw KGError.server(message)
        }
        if let status = Song.intValue(root["status"]), status != 1 {
            let message = (root["msg"] as? String) ?? (root["message"] as? String) ?? "回复加载失败"
            throw KGError.server(message)
        }
        let list = (root["list"] as? [[String: Any]]) ?? []
        let replies = list.enumerated().compactMap { index, item in
            CommentReply(json: item, fallbackID: "\(page)-\(index)")
        }
        let total = Song.intValue(root["comments_num"])
            ?? Song.intValue(root["count"])
            ?? replies.count
        let hasMore: Bool
        if replies.isEmpty {
            hasMore = false
        } else {
            hasMore = page * pageSize < total || list.count >= pageSize
        }
        return CommentReplyPage(replies: replies, total: total, hasMore: hasMore)
    }

    // MARK: - 热门搜索

    static func hotSearch() async throws -> [String] {
        let data = try await KGApi.shared.get(
            path: "/api/v3/search/hot_tab",
            params: ["navid": "1", "plat": "2"],
            router: "msearch.kugou.com"
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = (root["data"] as? [String: Any])?["list"] as? [[String: Any]] else { return [] }
        var result: [String] = []
        for section in sections {
            for item in (section["keywords"] as? [[String: Any]] ?? []) {
                if let word = item["keyword"] as? String, !word.isEmpty, !result.contains(word) {
                    result.append(word)
                }
            }
        }
        return Array(result.prefix(18))
    }

    // MARK: - 排行榜

    static func ranks() async throws -> [RankItem] {
        let data = try await KGApi.shared.get(
            path: "/ocean/v6/rank/list",
            params: ["plat": "2", "withsong": "0", "parentid": "0"]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let raw = (root["data"] as? [String: Any])?["info"] as? [[String: Any]]
            ?? (root["data"] as? [String: Any])?["list"] as? [[String: Any]]
            ?? []
        return raw.compactMap { item in
            guard let rankid = Song.intValue(item["rankid"]) ?? Song.intValue(item["id"]) else { return nil }
            let name = (item["rankname"] as? String) ?? (item["name"] as? String) ?? "榜单"
            let cover = findImage(in: item) ?? (item["imgurl"] as? String)?.replacingOccurrences(of: "{size}", with: "240")
            let intro = (item["intro"] as? String) ?? ""
            return RankItem(id: rankid, name: name, cover: cover, intro: intro)
        }
    }

    static func rankSongs(rankid: Int, page: Int = 1, pageSize: Int = 30) async throws -> [Song] {
        let data = try await KGApi.shared.post(
            path: "/openapi/kmr/v2/rank/audio",
            params: [:],
            body: [
                "show_portrait_mv": 1,
                "show_type_total": 1,
                "filter_original_remarks": 1,
                "area_code": 1,
                "pagesize": pageSize,
                "rank_cid": 0,
                "type": 1,
                "page": page,
                "rank_id": rankid
            ],
            headers: ["kg-tid": "369"]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if let code = Song.intValue(root["error_code"]), code != 0 {
            throw KGError.server("榜单歌曲读取失败（\(code)）")
        }
        var raw: [[String: Any]] = []
        func append(_ value: Any?) {
            if let items = value as? [[String: Any]] { raw.append(contentsOf: items) }
        }
        if let payload = root["data"] as? [String: Any] {
            append(payload["songlist"])
            append(payload["songs"])
            append(payload["list"])
            append(payload["info"])
            if let info = payload["info"] as? [String: Any] {
                append(info["songlist"])
                append(info["songs"])
                append(info["list"])
            }
        }
        append(root["data"])
        append(root["songlist"])
        append(root["songs"])
        return raw.compactMap { item in normalizeRankSong(item) }
    }

    // MARK: - 歌手

    static func artistID(named name: String) async throws -> Int? {
        let results = try await search(name, pageSize: 30)
        let exact = results.first {
            $0.SingerName == name || $0.SingerName.contains(name) || name.contains($0.SingerName)
        }
        return (exact ?? results.first)?.AuthorID
    }

    static func artistSongs(authorID: Int, page: Int = 1, pageSize: Int = 30) async throws -> [Song] {
        let clienttime = Int(Date().timeIntervalSince1970)
        let appid = KGApi.shared.appid
        let clientver = KGApi.shared.clientver
        let key = KGSign.md5("\(appid)\(KGSign.androidSalt)\(clientver)\(clienttime)")
        let data = try await KGApi.shared.post(
            path: "/kmr/v1/audio_group/author",
            host: "https://openapi.kugou.com",
            params: [:],
            body: [
                "appid": appid,
                "clientver": clientver,
                "mid": KGApi.shared.mid,
                "clienttime": clienttime,
                "key": key,
                "author_id": "\(authorID)",
                "pagesize": "\(pageSize)",
                "page": "\(page)",
                "sort": 2,
                "area_code": "all"
            ],
            router: "openapi.kugou.com",
            headers: ["kg-tid": "220"]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if let code = Song.intValue(root["error_code"]), code != 0 {
            throw KGError.server("歌手作品读取失败（\(code)）")
        }
        let raw = root["data"] as? [[String: Any]] ?? []
        return raw.compactMap { normalizeArtistSong($0) }
    }

    private static func normalizeArtistSong(_ item: [String: Any]) -> Song? {
        let hash = (item["hash"] as? String)
            ?? (item["hash_320"] as? String)
            ?? (item["hash_high"] as? String)
            ?? (item["hash_128"] as? String)
        guard let fileHash = hash, !fileHash.isEmpty else { return nil }
        guard let songName = item["audio_name"] as? String, !songName.isEmpty else { return nil }

        var json: [String: Any] = [
            "FileHash": fileHash,
            "SongName": songName,
            "SingerName": (item["author_name"] as? String) ?? ""
        ]
        json["AlbumID"] = item["album_id"]
        json["AlbumName"] = item["album_name"]
        json["Duration"] = item["timelength"]
        json["MixSongID"] = item["album_audio_id"]
        json["Audioid"] = item["audio_id"]
        json["PayType"] = item["pay_type"]
        json["Privilege"] = item["privilege"]
        json["Image"] = findImage(in: item)
        return Song(json: json)
    }

    // MARK: - 专辑

    static func albumSongs(albumID: Int, page: Int = 1, pageSize: Int = 30) async throws -> [Song] {
        let data = try await KGApi.shared.post(
            path: "/v1/album_audio/lite",
            params: [:],
            body: [
                "album_id": "\(albumID)",
                "is_buy": "",
                "page": "\(page)",
                "pagesize": "\(pageSize)"
            ],
            router: "openapi.kugou.com",
            headers: ["kg-tid": "255"]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if let code = Song.intValue(root["error_code"]), code != 0 {
            throw KGError.server("专辑读取失败（\(code)）")
        }
        let raw = (root["data"] as? [String: Any])?["songs"] as? [[String: Any]]
            ?? (root["data"] as? [String: Any])?["info"] as? [[String: Any]]
            ?? []
        return raw.compactMap { normalizeAlbumSong($0) }
    }

    private static func normalizeAlbumSong(_ item: [String: Any]) -> Song? {
        let base = item["base"] as? [String: Any] ?? [:]
        let audio = item["audio_info"] as? [String: Any] ?? [:]
        let album = item["album_info"] as? [String: Any] ?? [:]
        let deprecated = item["deprecated"] as? [String: Any] ?? [:]

        let hash = (audio["hash"] as? String)
            ?? (audio["hash_320"] as? String)
            ?? (audio["hash_high"] as? String)
            ?? (audio["hash_128"] as? String)
            ?? (item["hash"] as? String)
        guard let fileHash = hash, !fileHash.isEmpty else { return nil }
        guard let songName = (base["audio_name"] as? String) ?? (item["songname"] as? String), !songName.isEmpty else { return nil }

        var json: [String: Any] = [
            "FileHash": fileHash,
            "SongName": songName,
            "SingerName": (base["author_name"] as? String) ?? (item["singername"] as? String) ?? ""
        ]
        json["AlbumID"] = base["album_id"] ?? item["album_id"] ?? album["album_id"]
        json["AlbumName"] = album["album_name"] ?? item["album_name"]
        json["Duration"] = audio["duration"] ?? item["duration"]
        json["MixSongID"] = base["album_audio_id"] ?? item["album_audio_id"]
        json["Audioid"] = base["audio_id"] ?? item["audio_id"]
        json["AuthorID"] = (item["authors"] as? [[String: Any]])?.first?["author_id"]
        json["PayType"] = deprecated["pay_type"] ?? item["pay_type"]
        json["Privilege"] = deprecated["privilege"] ?? item["privilege"]
        if let cover = album["cover"] as? String {
            json["Image"] = cover.replacingOccurrences(of: "{size}", with: "240")
        } else {
            json["Image"] = findImage(in: item)
        }
        return Song(json: json)
    }

    private static func normalizeRankSong(_ item: [String: Any]) -> Song? {
        let deprecated = item["deprecated"] as? [String: Any] ?? [:]
        let hash = (deprecated["hash"] as? String)
            ?? (item["hash"] as? String)
            ?? (item["hash_320"] as? String)
            ?? (item["hash_128"] as? String)
            ?? ""
        guard !hash.isEmpty else { return nil }
        var json: [String: Any] = [
            "FileHash": hash,
            "SongName": (item["songname"] as? String) ?? (item["name"] as? String) ?? "未知歌曲",
            "SingerName": (item["author_name"] as? String)
                ?? (item["singername"] as? String)
                ?? (item["singer_name"] as? String)
                ?? ((item["authors"] as? [[String: Any]])?.compactMap {
                    ($0["author_name"] as? String) ?? ($0["name"] as? String)
                }.joined(separator: "、") ?? "")
        ]
        json["Duration"] = deprecated["duration"] ?? item["timelen"] ?? item["duration"]
        json["AlbumID"] = deprecated["albumid"] ?? item["albumid"] ?? item["album_id"]
        json["MixSongID"] = item["album_audio_id"] ?? deprecated["mixsongid"] ?? item["mixsongid"]
        json["Audioid"] = item["audio_id"] ?? item["audioid"] ?? deprecated["audioid"]
        json["AuthorID"] = item["author_id"] ?? (item["authors"] as? [[String: Any]])?.first?["author_id"]
        let albumInfo = item["album_info"] as? [String: Any] ?? item["albuminfo"] as? [String: Any]
        json["AlbumName"] = item["album_name"] ?? albumInfo?["album_name"] ?? albumInfo?["name"]
        json["Privilege"] = item["privilege"] ?? deprecated["privilege"]
        json["PayType"] = item["pay_type"] ?? deprecated["pay_type"]
        if let trans = item["trans_param"] as? [String: Any], let cover = trans["union_cover"] as? String {
            json["Image"] = cover.replacingOccurrences(of: "{size}", with: "240")
        } else {
            json["Image"] = findImage(in: item)
        }
        return Song(json: json)
    }

    // MARK: - 云歌单

    static func playlists() async throws -> [CloudPlaylist] {
        guard KGApi.shared.token != nil, KGApi.shared.userid != 0 else { return [] }

        var lastError: Error?
        do {
            let all = try await allPlaylists(type: 2)
            if !all.isEmpty { return CloudPlaylistOrdering.newestFirst(all) }
        } catch { lastError = error }

        // 少数账号 type 2 只返回单一类型，按 0/1 再补一次。
        let created = (try? await allPlaylists(type: 0)) ?? []
        let collected = (try? await allPlaylists(type: 1)) ?? []
        var merged: [String: CloudPlaylist] = [:]
        var order: [String] = []
        func add(_ list: [CloudPlaylist]) {
            for playlist in list {
                let key = playlist.listid ?? playlist.id
                guard !key.isEmpty else { continue }
                if merged[key] == nil { order.append(key); merged[key] = playlist }
            }
        }
        add(created)
        add(collected)
        if !order.isEmpty { return CloudPlaylistOrdering.newestFirst(order.compactMap { merged[$0] }) }
        if let lastError = lastError { throw lastError }
        return []
    }

    private static func allPlaylists(type: Int) async throws -> [CloudPlaylist] {
        var result: [CloudPlaylist] = []
        var seen = Set<String>()
        var page = 1
        while page <= 8 {
            let batch = try await playlists(type: type, page: page)
            if batch.isEmpty { break }
            for playlist in batch {
                let key = playlist.listid ?? playlist.id
                if seen.insert(key).inserted { result.append(playlist) }
            }
            if batch.count < 30 { break }
            page += 1
        }
        return result
    }

    private static func playlists(type: Int, page: Int) async throws -> [CloudPlaylist] {
        guard let token = KGApi.shared.token, KGApi.shared.userid != 0 else { return [] }
        let data = try await KGApi.shared.post(
            path: "/v7/get_all_list",
            params: ["plat": "1", "userid": String(KGApi.shared.userid), "token": token],
            body: [
                "userid": KGApi.shared.userid,
                "token": token,
                "total_ver": 979,
                "type": type,
                "page": page,
                "pagesize": 30
            ],
            router: "cloudlist.service.kugou.com",
            lite: true
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("歌单接口返回格式异常")
        }
        let container = root["data"] as? [String: Any]
        var raw: [(item: [String: Any], hint: Int)] = []
        if let info = container?["info"] as? [String: Any] {
            let groups: [(String, Int)] = [("self", 0), ("collect", 1), ("love", 1), ("list", type)]
            for (key, hint) in groups {
                if let list = info[key] as? [[String: Any]] {
                    raw.append(contentsOf: list.map { (item: $0, hint: hint) })
                }
            }
        }
        if let info = container?["info"] as? [[String: Any]] {
            raw.append(contentsOf: info.map { (item: $0, hint: type) })
        }
        for key in ["list", "lists"] {
            if let list = container?[key] as? [[String: Any]] {
                raw.append(contentsOf: list.map { (item: $0, hint: type) })
            }
        }
        if let info = root["info"] as? [[String: Any]] {
            raw.append(contentsOf: info.map { (item: $0, hint: type) })
        }
        if raw.isEmpty, let status = Song.intValue(root["status"]), status != 1 {
            let code = Song.intValue(root["error_code"]) ?? 0
            let message = (root["error"] as? String) ?? (root["error_msg"] as? String) ?? ""
            throw KGError.server("歌单接口失败（\(status)/\(code)）\(message.isEmpty ? "" : "：\(message)")")
        }
        return raw.compactMap { pair in
            let item = pair.item
            let listid = stringValue(item["list_create_listid"])
                ?? stringValue(item["listid"])
                ?? stringValue(item["list_id"])
            let gid = stringValue(item["global_collection_id"])
                ?? stringValue(item["list_create_gid"])
                ?? stringValue(item["specialid"])
                ?? stringValue(item["gid"])
            guard let id = gid ?? listid, !id.isEmpty else { return nil }
            let name = stringValue(item["name"])
                ?? stringValue(item["list_name"])
                ?? stringValue(item["listname"])
                ?? stringValue(item["specialname"])
                ?? stringValue(item["title"])
                ?? "未命名歌单"
            let count = Song.intValue(item["count"])
                ?? Song.intValue(item["m_count"])
                ?? Song.intValue(item["song_count"])
                ?? Song.intValue(item["total"])
                ?? Song.intValue(item["list_count"])
                ?? 0
            let cover = findImage(in: item)
            let creator = stringValue(item["list_create_userid"])
                ?? stringValue(item["userid"])
                ?? stringValue(item["user_id"])
                ?? stringValue(item["owner_id"])
            let createdAt = playlistCreatedAt(item)
            let reportedType = Song.intValue(item["type"]) ?? pair.hint
            var resolvedType = reportedType
            if resolvedType != 1, let creatorID = creator, creatorID != String(KGApi.shared.userid) {
                // 收藏歌单的创建者不是自己；type=2 汇总里也靠这个区分。
                resolvedType = 1
            }
            if resolvedType == 2 { resolvedType = 0 }
            return CloudPlaylist(id: id, name: name, count: count, cover: cover,
                                 listid: listid, type: resolvedType, creatorID: creator,
                                 createdAt: createdAt)
        }
    }

    /// 把一批歌曲加入指定自建歌单。官方接口支持一次传多首，适合批量操作。
    static func addSongs(_ songs: [Song], to playlist: CloudPlaylist,
                         typeOverride: Int? = nil) async throws {
        guard let token = KGApi.shared.token, KGApi.shared.userid != 0 else {
            throw KGError.server("请先登录")
        }
        guard let listid = playlist.listid, !listid.isEmpty else {
            throw KGError.server("这个歌单没有 listid，不能写入")
        }
        guard !songs.isEmpty else { return }
        guard !playlist.isCollected || typeOverride == 0 else {
            throw KGError.server("收藏歌单不能直接写入，请选择我创建的歌单")
        }

        let clienttime = Int(Date().timeIntervalSince1970)
        let resources: [[String: Any]] = songs.map { song in
            [
                "number": 1,
                "name": song.SongName,
                "hash": song.FileHash,
                "size": 0,
                "sort": 0,
                "timelen": (song.Duration ?? 0) * 1000,
                "bitrate": 0,
                "album_id": song.AlbumID ?? 0,
                "mixsongid": song.MixSongID ?? song.Audioid ?? 0
            ]
        }
        let data = try await KGApi.shared.post(
            path: "/cloudlist.service/v6/add_song",
            params: [
                "last_time": "\(clienttime)",
                "last_area": "gztx",
                "userid": "\(KGApi.shared.userid)",
                "token": token
            ],
            body: [
                "userid": KGApi.shared.userid,
                "token": token,
                "listid": listid,
                "list_ver": 0,
                "type": typeOverride ?? 0,
                "slow_upload": 1,
                "scene": "false;null",
                "data": resources
            ],
            lite: true
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("加入歌单返回格式异常")
        }
        let status = Song.intValue(root["status"]) ?? 0
        if status != 1 {
            let code = Song.intValue(root["error_code"]) ?? 0
            let message = (root["error"]) as? String ?? (root["error_msg"] as? String) ?? ""
            throw KGError.server("加入歌单失败（\(status)/\(code)）\(message.isEmpty ? "" : "：\(message)")")
        }
    }

    /// 官方「我喜欢」歌单。名字优先，其次兼容“我的收藏 / favorite / liked”。
    static func favoritePlaylist() async throws -> CloudPlaylist? {
        let lists = try await playlists()
        let trimmed = lists.filter {
            let name = $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !name.isEmpty
        }
        let exact = trimmed.first { $0.name == "我喜欢" }
        let primary = exact
            ?? trimmed.first { $0.name.contains("我喜欢") }
            ?? trimmed.first { $0.name.contains("我的收藏") }
            ?? trimmed.first {
                let lower = $0.name.lowercased()
                return lower.contains("favorite") || lower.contains("liked")
            }
        guard let playlist = primary else { return nil }
        let listid = playlist.listid ?? listIDFromGlobalID(playlist.id) ?? playlist.id
        guard !listid.isEmpty else { return nil }
        // 官方「我喜欢」在云歌单里按 type=0 处理，收藏分组只是接口返回的位置。
        return CloudPlaylist(id: playlist.id, name: playlist.name, count: playlist.count,
                             cover: playlist.cover, listid: listid, type: 0,
                             creatorID: playlist.creatorID, createdAt: playlist.createdAt)
    }

    private static func listIDFromGlobalID(_ raw: String) -> String? {
        let parts = raw.split(separator: "_")
        guard parts.count >= 4, parts[0] == "collection" else { return nil }
        let value = String(parts[3])
        return value.isEmpty ? nil : value
    }

    /// 取消官方「我喜欢」中的一首歌：先找到该曲目的 fileid，再调删除接口。
    static func removeFavorite(_ song: Song, from playlist: CloudPlaylist) async throws {
        guard let token = KGApi.shared.token, KGApi.shared.userid != 0 else {
            throw KGError.server("请先登录")
        }
        guard let listid = playlist.listid, !listid.isEmpty else {
            throw KGError.server("官方「我喜欢」没有 listid，不能删除")
        }
        var fileID = song.FileID ?? 0
        if fileID == 0 {
            fileID = await findFavoriteFileID(hash: song.FileHash, playlist: playlist) ?? 0
        }
        guard fileID != 0 else {
            throw KGError.server("官方「我喜欢」里没有找到这首歌，先同步再试")
        }
        let data = try await KGApi.shared.post(
            path: "/v4/delete_songs",
            params: [:],
            body: [
                "listid": listid,
                "userid": KGApi.shared.userid,
                "token": token,
                "type": 0,
                "list_ver": 0,
                "data": [["fileid": fileID]]
            ],
            router: "cloudlist.service.kugou.com",
            lite: true
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("取消我喜欢返回格式异常")
        }
        let status = Song.intValue(root["status"]) ?? 0
        if status != 1 {
            let code = Song.intValue(root["error_code"]) ?? 0
            let message = (root["error"] as? String) ?? (root["error_msg"] as? String) ?? ""
            throw KGError.server("取消我喜欢失败（\(status)/\(code)）\(message.isEmpty ? "" : "：\(message)")")
        }
    }

    private static func findFavoriteFileID(hash: String, playlist: CloudPlaylist) async -> Int? {
        let target = hash.lowercased()
        var page = 1
        while page <= 20 {
            let batch = try? await playlistSongs(playlist: playlist, page: page, pageSize: 30)
            guard let songs = batch, !songs.isEmpty else { return nil }
            if let found = songs.first(where: { $0.FileHash.lowercased() == target }),
               let fileID = found.FileID, fileID != 0 {
                return fileID
            }
            if songs.count < 30 { break }
            if playlist.count > 0, songs.count * page >= playlist.count { break }
            page += 1
        }
        return nil
    }

    /// 从云歌单列表里提取当前账号昵称/头像，给资料接口做兜底。
    static func profileFromPlaylists() async -> KugouProfile? {
        guard let token = KGApi.shared.token, KGApi.shared.userid != 0 else { return nil }
        guard let data = try? await KGApi.shared.post(
            path: "/v7/get_all_list",
            params: ["plat": "1", "userid": String(KGApi.shared.userid), "token": token],
            body: [
                "userid": KGApi.shared.userid,
                "token": token,
                "total_ver": 979,
                "type": 2,
                "page": 1,
                "pagesize": 30
            ],
            router: "cloudlist.service.kugou.com",
            lite: true
        ), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let container = root["data"] as? [String: Any]
        var items: [[String: Any]] = []
        if let info = container?["info"] as? [String: Any] {
            for key in ["self", "collect", "love", "list"] {
                items.append(contentsOf: info[key] as? [[String: Any]] ?? [])
            }
        }
        if let info = container?["info"] as? [[String: Any]] {
            items.append(contentsOf: info)
        }
        for key in ["list", "lists"] {
            items.append(contentsOf: container?[key] as? [[String: Any]] ?? [])
        }
        if let direct = container, let nickname = stringValue(direct["nickname"]) {
            let avatar = stringValue(direct["pic"]) ?? stringValue(direct["avatar"])
            return KugouProfile(nickname: nickname, avatarURL: normalizedAvatar(avatar), signature: nil)
        }

        let ownID = String(KGApi.shared.userid)
        let selected = items.first { item in
            let creator = stringValue(item["list_create_userid"])
                ?? stringValue(item["userid"])
                ?? stringValue(item["user_id"])
                ?? stringValue(item["owner_id"])
            return creator == ownID
        } ?? (items.count == 1 ? items[0] : nil)
        guard let item = selected else { return nil }
        let nickname = stringValue(item["nickname"])
            ?? stringValue(item["username"])
            ?? stringValue(item["user_name"])
            ?? stringValue(item["list_create_username"])
            ?? ""
        let avatarRaw = stringValue(item["create_user_pic"])
            ?? stringValue(item["user_pic"])
            ?? stringValue(item["avatar"])
            ?? stringValue(item["headimg"])
        guard !nickname.isEmpty || avatarRaw != nil else { return nil }
        return KugouProfile(nickname: nickname, avatarURL: normalizedAvatar(avatarRaw), signature: nil)
    }

    private static func normalizedAvatar(_ raw: String?) -> String? {
        guard var value = raw, !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "{size}", with: "120")
        if value.hasPrefix("http://") {
            value = "https://" + String(value.dropFirst("http://".count))
        }
        return value.hasPrefix("http") ? value : nil
    }

    static func playlistSongs(playlist: CloudPlaylist, page: Int = 1, pageSize: Int = 30) async throws -> [Song] {
        guard let token = KGApi.shared.token else { return [] }

        // 用户自建 / 收藏歌单优先走 v4 云歌单接口，它支持分页和 listid。
        if let listid = playlist.listid, !listid.isEmpty {
            let types = playlist.type == 1 ? [1] : (playlist.type == 0 ? [0] : [0, 1])
            for listType in types {
                let data = try? await KGApi.shared.post(
                    path: "/v4/get_list_all_file_v3",
                    params: [:],
                    body: [
                        "listid": listid,
                        "userid": KGApi.shared.userid,
                        "type": listType,
                        "page": page,
                        "pagesize": pageSize,
                        "area_code": 1,
                        "allplatform": 1,
                        "show_cover": 1,
                        "token": token
                    ],
                    router: "cloudlist.service.kugou.com",
                    lite: true
                )
                if let data = data {
                    let songs = parsePlaylistSongs(data)
                    if !songs.isEmpty { return songs }
                }
            }

            // v3 偶发只返回空壳，换云歌单旧端点再试一次。
            let fallbackBody: [String: Any] = [
                "listid": listid,
                "userid": KGApi.shared.userid,
                "type": types.first ?? 0,
                "page": page,
                "pagesize": pageSize,
                "area_code": 1,
                "allplatform": 1,
                "show_cover": 1,
                "show_relate_goods": 0,
                "token": token
            ]
            if let data = try? await KGApi.shared.post(
                path: "/v4/get_list_all_file",
                params: ["plat": "1"],
                body: fallbackBody,
                router: "cloudlist.service.kugou.com",
                lite: true
            ), !parsePlaylistSongs(data).isEmpty {
                return parsePlaylistSongs(data)
            }
        }

        // 官方推荐歌单只有 global_collection_id，走老接口。
        if let gid = playlist.globalID {
            return try await playlistSongs(id: gid)
        }
        return []
    }

    /// 歌单详情按“最新加入在最上面”展示。
    /// 酷狗云歌单接口按加入时间正序返回（第 1 页是最早加入的），所以从最后一页
    /// 往前取，并把每页内部倒序：第 1 次加载拿到的是最后 30 首里最新的那批。
    static func playlistSongsNewestFirst(playlist: CloudPlaylist,
                                         page: Int,
                                         pageSize: Int = 30) async throws -> [Song] {
        let size = max(pageSize, 1)
        let total = max(playlist.count, 0)
        guard total > 0 else {
            // 极少数账号拿不到 count，退回接口顺序，至少保证分页能继续。
            return try await playlistSongs(playlist: playlist, page: page, pageSize: size)
        }
        let totalPages = (total + size - 1) / size
        let apiPage = totalPages - (page - 1)
        guard apiPage >= 1 else { return [] }
        let batch = try await playlistSongs(playlist: playlist, page: apiPage, pageSize: size)
        return Array(batch.reversed())
    }

    static func playlistSongs(id: String) async throws -> [Song] {
        guard let token = KGApi.shared.token else { return [] }
        let data = try await KGApi.shared.post(
            path: "/v3/get_list_info",
            params: [:],
            body: [
                "data": [["global_collection_id": id]],
                "userid": KGApi.shared.userid,
                "token": token
            ],
            router: "pubsongs.kugou.com",
            lite: true
        )
        return parsePlaylistSongs(data)
    }

    private static func parsePlaylistSongs(_ data: Data) -> [Song] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var raw: [[String: Any]] = []

        func appendArray(_ value: Any?) {
            if let list = value as? [[String: Any]] {
                raw.append(contentsOf: list)
            }
        }

        if let container = root["data"] as? [String: Any] {
            appendArray(container["songs"])
            appendArray(container["list"])
            appendArray(container["lists"])
            appendArray(container["file_list"])
            appendArray(container["file"])
            appendArray(container["info"])
            if let info = container["info"] as? [String: Any] {
                appendArray(info["songs"])
                appendArray(info["list"])
                appendArray(info["file"])
                appendArray(info["file_list"])
                appendArray(info["data"])
            }
        }
        appendArray(root["data"])
        appendArray(root["songs"])
        appendArray(root["info"])
        appendArray(root["list"])

        var unique: [[String: Any]] = []
        var seen = Set<String>()
        for item in raw {
            let key = stringValue(item["hash"]) ?? stringValue(item["FileHash"]) ?? ""
            if key.isEmpty || seen.insert(key).inserted {
                unique.append(item)
            }
        }
        return unique.compactMap { normalizePlaylistSong($0) }
    }

    private static func normalizePlaylistSong(_ item: [String: Any]) -> Song? {
        guard let hash = stringValue(item["hash"]), !hash.isEmpty else { return nil }
        var json = item
        json["FileHash"] = hash
        let fullName = stripAudioExtension(stringValue(item["name"]) ?? stringValue(item["filename"]) ?? "")
        if let range = fullName.range(of: " - ") {
            json["SongName"] = String(fullName[range.upperBound...])
            json["SingerName"] = String(fullName[..<range.lowerBound])
        } else {
            json["SongName"] = fullName.isEmpty ? "未知歌曲" : fullName
            json["SingerName"] = stringValue(item["singername"]) ?? ""
        }
        if let album = item["albuminfo"] as? [String: Any] {
            json["AlbumName"] = album["name"] as? String
            if json["AlbumID"] == nil { json["AlbumID"] = album["albumid"] ?? album["id"] }
        }
        if json["Duration"] == nil { json["Duration"] = item["timelen"] ?? item["duration"] }
        if json["AlbumID"] == nil { json["AlbumID"] = item["album_id"] ?? item["albumid"] }
        if json["MixSongID"] == nil { json["MixSongID"] = item["mixsongid"] ?? item["album_audio_id"] }
        if json["Audioid"] == nil { json["Audioid"] = item["audioid"] ?? item["audio_id"] }
        if json["FileID"] == nil { json["FileID"] = item["fileid"] ?? item["file_id"] }
        if json["Image"] == nil { json["Image"] = findImage(in: item) }
        if json["Privilege"] == nil { json["Privilege"] = item["privilege"] }
        return Song(json: json)
    }

    private static func stripAudioExtension(_ raw: String) -> String {
        Song.cleanTitle(raw)
    }

    /// 云歌单时间字段在不同账号/接口版本里命名不一致。
    /// 拆成逐项查找，避免一长串 `??` 让 Swift 类型检查器超时。
    private static func playlistCreatedAt(_ item: [String: Any]) -> Int? {
        let keys = ["list_create_time", "listCreateTime",
                    "create_time", "createTime",
                    "collect_time", "collectTime",
                    "subscribe_time", "update_time", "updateTime",
                    "add_time", "addTime", "addtime"]
        for key in keys {
            if let value = Song.intValue(item[key]) { return value }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// 推荐接口的封面字段名不稳定，递归找一圈。
    private static func findImage(in value: Any) -> String? {
        let keys = ["sizable_cover", "cover_img_url", "flexible_cover", "album_image", "albumimg", "album_img", "img", "image", "cover", "union_cover", "pic"]
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

    /// 老记录里没有封面时，按 hash 回查专辑图。
    static func songCover(hash: String) async -> String? {
        guard var components = URLComponents(string: "https://m.kugou.com/app/i/getSongInfo.php") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "cmd", value: "playInfo"),
            URLQueryItem(name: "hash", value: hash)
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let raw = (root["album_img"] as? String) ?? (root["imgUrl"] as? String)
        guard var value = raw, value.contains("imge.kugou.com") || value.contains("singerimg.kugou.com") else { return nil }
        value = value.replacingOccurrences(of: "{size}", with: "240")
        if value.hasPrefix("http://") { value = "https://" + value.dropFirst(7) }
        return value
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
            remember("试听", for: song.FileHash)
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

    /// 伴唱：请求酷狗魔法音乐的 acappella 双音轨（人声 + 伴奏）。
    /// 只有部分歌曲有该资源，取不到时上层会退回普通播放。
    static func karaokeURL(for song: Song) async throws -> URL? {
        guard KGApi.shared.token != nil, KGApi.shared.userid != 0 else { return nil }
        _ = await KGDevice.registerIfNeeded()
        KGApi.shared.lastMixSongID = song.MixSongID ?? 0
        let audioID = song.MixSongID ?? song.Audioid
        if let url = try? await liteURL(hash: song.FileHash,
                                        albumID: song.AlbumID,
                                        albumAudioID: audioID,
                                        quality: "acappella") {
            return url
        }
        if let url = try? await authorizedURL(hash: song.FileHash,
                                              albumID: song.AlbumID,
                                              albumAudioID: audioID,
                                              quality: "acappella") {
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

    /// 返回当前歌曲可选的歌词来源；优先标题精确匹配，再补歌手+标题候选。
    static func lyricCandidates(hash: String, title: String, artist: String = "") async throws -> [LyricCandidate] {
        let keywords = [title, artist.isEmpty ? title : "\(artist) \(title)"]
        var seen = Set<String>()
        var result: [LyricCandidate] = []
        for keyword in keywords where !keyword.isEmpty {
            guard let batch = try? await lyricCandidates(keyword: keyword, hash: hash) else { continue }
            for candidate in batch where seen.insert(candidate.id).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    /// 下载指定歌词来源。优先 KRC（逐字），失败时回落 LRC。
    static func lyric(candidate: LyricCandidate) async throws -> [LyricLine] {
        if let data = try? await lyricPayload(id: candidate.id, accessKey: candidate.accesskey, fmt: "krc"),
           let text = LyricParser.decodeKRC(data) {
            let lines = LyricParser.parse(text)
            if !lines.isEmpty { return lines }
        }
        if let data = try? await lyricPayload(id: candidate.id, accessKey: candidate.accesskey, fmt: "lrc"),
           let text = String(data: data, encoding: .utf8) {
            let lines = LyricParser.parse(text)
            if !lines.isEmpty { return lines }
        }
        throw KGError.server("这条歌词暂时无法解析")
    }

    /// 兼容旧调用：自动选第一条能解析的候选。
    static func lyric(hash: String, title: String, artist: String = "") async throws -> [LyricLine] {
        let candidates = try await lyricCandidates(hash: hash, title: title, artist: artist)
        for candidate in candidates.prefix(4) {
            if let lines = try? await lyric(candidate: candidate), !lines.isEmpty {
                return lines
            }
        }
        return []
    }

    private static func lyricCandidates(keyword: String, hash: String) async throws -> [LyricCandidate] {
        var components = URLComponents(string: "https://krcs.kugou.com/search")!
        components.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "man", value: "yes"),
            URLQueryItem(name: "client", value: "mobi"),
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "hash", value: hash),
        ]
        guard let url = components.url else { return [] }
        let data = try await KGApi.shared.plain(url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["candidates"] as? [[String: Any]] else { return [] }
        return raw.compactMap { item in
            let rawID = item["id"]
            let id: String?
            if let string = rawID as? String { id = string }
            else if let number = rawID as? NSNumber { id = number.stringValue }
            else { id = nil }
            guard let value = id, let key = item["accesskey"] as? String, !key.isEmpty else { return nil }
            return LyricCandidate(
                id: value,
                accesskey: key,
                song: item["song"] as? String,
                singer: item["singer"] as? String,
                duration: Song.intValue(item["duration"]),
                krctype: Song.intValue(item["krctype"]),
                language: item["language"] as? String
            )
        }
    }

    private static func lyricPayload(id: String, accessKey: String, fmt: String) async throws -> Data? {
        var components = URLComponents(string: "https://lyrics.kugou.com/download")!
        components.queryItems = [
            URLQueryItem(name: "ver", value: "1"),
            URLQueryItem(name: "client", value: "pc"),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "accesskey", value: accessKey),
            URLQueryItem(name: "fmt", value: fmt),
            URLQueryItem(name: "charset", value: "utf8"),
        ]
        guard let url = components.url else { return nil }
        let data = try await KGApi.shared.plain(url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content"] as? String,
              let decoded = Data(base64Encoded: content, options: .ignoreUnknownCharacters),
              !decoded.isEmpty else { return nil }
        return decoded
    }

}
