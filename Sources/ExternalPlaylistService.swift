import Foundation

struct ExternalTrack: Equatable {
    let name: String
    let artist: String
    let album: String?
}

struct ExternalPlaylist: Equatable {
    let name: String
    let coverURL: URL?
    let tracks: [ExternalTrack]
}

enum PlaylistImportSource: String, CaseIterable, Identifiable {
    case netease
    case qq
    case kugou
    case soda

    var id: String { rawValue }

    var title: String {
        switch self {
        case .netease: return "网易云音乐"
        case .qq: return "QQ 音乐"
        case .kugou: return "酷狗音乐"
        case .soda: return "汽水音乐"
        }
    }

    var shortTitle: String {
        switch self {
        case .netease: return "网易云"
        case .qq: return "QQ 音乐"
        case .kugou: return "酷狗"
        case .soda: return "汽水"
        }
    }

    var tint: String {
        switch self {
        case .netease: return "E60026"
        case .qq: return "31C27C"
        case .kugou: return "2D8CF0"
        case .soda: return "FF4D67"
        }
    }

    var placeholder: String {
        switch self {
        case .netease: return "粘贴网易云歌单链接或 ID"
        case .qq: return "粘贴 QQ 音乐歌单链接或 ID"
        case .kugou: return "粘贴酷狗歌单链接 / specialid / collection ID"
        case .soda: return "粘贴汽水歌单分享链接"
        }
    }
}

enum PlaylistImportError: LocalizedError {
    case invalidInput
    case network(String)
    case empty(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput: return "没有识别到歌单 ID，请检查链接"
        case .network(let message): return message
        case .empty(let message): return message
        case .unsupported(let message): return message
        }
    }
}

enum ExternalPlaylistService {
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"

    static func fetch(source: PlaylistImportSource, input: String) async throws -> ExternalPlaylist {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PlaylistImportError.invalidInput }

        // 所有来源都保留「粘贴歌曲列表」的兜底：分享链接失效、平台没有公开接口时，
        // 用户仍然可以把歌单一首一首贴进来完成导入。
        if looksLikePlainTrackList(trimmed) {
            let tracks = parseTrackList(trimmed)
            guard !tracks.isEmpty else { throw PlaylistImportError.empty("没有解析到歌曲，请按每行「歌名 - 歌手」粘贴") }
            return ExternalPlaylist(name: "\(source.shortTitle)导入歌单", coverURL: nil, tracks: tracks)
        }

        switch source {
        case .netease:
            return try await fetchNetease(trimmed)
        case .qq:
            return try await fetchQQ(trimmed)
        case .kugou:
            return try await fetchKugou(trimmed)
        case .soda:
            return try await fetchSoda(trimmed)
        }
    }

    // MARK: - 网易云

    private static func fetchNetease(_ input: String) async throws -> ExternalPlaylist {
        guard let id = firstMatch(#"(?:\?|&)id=(\d{4,})"#, in: input)
                ?? firstMatch(#"/playlist/(\d{4,})"#, in: input)
                ?? firstMatch(#"^\d{4,}$"#, in: input) else {
            throw PlaylistImportError.invalidInput
        }

        var request = URLRequest(url: URL(string: "https://music.163.com/api/playlist/detail?id=\(id)")!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        let json = try await requestJSON(request)

        guard let result = json["result"] as? [String: Any] else {
            throw PlaylistImportError.network("网易云返回格式异常")
        }
        let name = (result["name"] as? String) ?? "网易云歌单"
        let cover = (result["coverImgUrl"] as? String).flatMap(URL.init(string:))
        let rawTracks = (result["tracks"] as? [[String: Any]]) ?? []
        let tracks = rawTracks.compactMap { item -> ExternalTrack? in
            guard let title = item["name"] as? String, !title.isEmpty else { return nil }
            let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let album = (item["album"] as? [String: Any])?["name"] as? String
            return ExternalTrack(name: title, artist: artists.joined(separator: " / "), album: album)
        }
        guard !tracks.isEmpty else { throw PlaylistImportError.empty("网易云歌单里没有读到歌曲，可能是私密歌单") }
        return ExternalPlaylist(name: name, coverURL: cover, tracks: tracks)
    }

    // MARK: - QQ 音乐

    private static func fetchQQ(_ input: String) async throws -> ExternalPlaylist {
        guard let id = firstMatch(#"(?:disstid=|playlist/)(\d{4,})"#, in: input)
                ?? firstMatch(#"^\d{4,}$"#, in: input) else {
            throw PlaylistImportError.invalidInput
        }

        var components = URLComponents(string: "https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "utf8", value: "1"),
            URLQueryItem(name: "onlysong", value: "0"),
            URLQueryItem(name: "disstid", value: id),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "g_tk", value: "5381"),
            URLQueryItem(name: "loginUin", value: "0"),
            URLQueryItem(name: "hostUin", value: "0"),
            URLQueryItem(name: "inCharset", value: "utf8"),
            URLQueryItem(name: "outCharset", value: "utf-8"),
            URLQueryItem(name: "notice", value: "0"),
            URLQueryItem(name: "platform", value: "yqq.json"),
            URLQueryItem(name: "needNewCode", value: "0")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        let json = try await requestJSON(request)

        guard let cdlist = json["cdlist"] as? [[String: Any]], let first = cdlist.first else {
            throw PlaylistImportError.network("QQ 音乐返回格式异常")
        }
        let name = (first["dissname"] as? String) ?? "QQ 音乐歌单"
        let rawTracks = (first["songlist"] as? [[String: Any]]) ?? []
        var cover: URL?
        let tracks = rawTracks.compactMap { item -> ExternalTrack? in
            guard let title = item["songname"] as? String, !title.isEmpty else { return nil }
            let singers = (item["singer"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let album = item["albumname"] as? String
            if cover == nil, let albumMid = item["albummid"] as? String, !albumMid.isEmpty {
                cover = URL(string: "https://y.gtimg.cn/music/photo_new/T002R300x300M000\(albumMid).jpg")
            }
            return ExternalTrack(name: title, artist: singers.joined(separator: " / "), album: album)
        }
        guard !tracks.isEmpty else { throw PlaylistImportError.empty("QQ 音乐歌单里没有读到歌曲") }
        return ExternalPlaylist(name: name, coverURL: cover, tracks: tracks)
    }

    // MARK: - 酷狗

    private static func fetchKugou(_ input: String) async throws -> ExternalPlaylist {
        // 云歌单的 global_collection_id 可以直接用现有登录态读取。
        if let globalID = firstMatch(#"(collection_[A-Za-z0-9_]+)"#, in: input) {
            let songs = (try? await KGService.playlistSongs(id: globalID)) ?? []
            guard !songs.isEmpty else {
                throw PlaylistImportError.empty("没有读到这个酷狗歌单，可能是私密歌单或登录态已失效")
            }
            return ExternalPlaylist(
                name: "酷狗歌单",
                coverURL: songs.first?.coverURL,
                tracks: songs.map { ExternalTrack(name: $0.SongName, artist: $0.artist, album: $0.AlbumName) }
            )
        }

        guard let id = firstMatch(#"(?:specialid=|special/single/)(\d{4,})"#, in: input)
                ?? firstMatch(#"^\d{4,}$"#, in: input) else {
            throw PlaylistImportError.invalidInput
        }

        // Meting 的酷狗源接受 specialid；如果已经失效，就给出明确提示。
        var components = URLComponents(string: "https://api.i-meto.com/meting/api")!
        components.queryItems = [
            URLQueryItem(name: "server", value: "kugou"),
            URLQueryItem(name: "type", value: "playlist"),
            URLQueryItem(name: "id", value: id)
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data = try await requestData(request)
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !list.isEmpty else {
            throw PlaylistImportError.empty("这个酷狗分享链接没有读到歌曲。请确认歌单是公开的，或直接粘贴歌单里的歌曲列表。")
        }
        let tracks = list.compactMap { item -> ExternalTrack? in
            guard let title = item["title"] as? String, !title.isEmpty else { return nil }
            return ExternalTrack(name: title, artist: (item["author"] as? String) ?? "", album: nil)
        }
        let cover = (list.first?["pic"] as? String).flatMap(URL.init(string:))
        return ExternalPlaylist(name: "酷狗歌单", coverURL: cover, tracks: tracks)
    }

    // MARK: - 汽水音乐

    private static func fetchSoda(_ input: String) async throws -> ExternalPlaylist {
        guard input.contains("qishui.douyin.com") || input.contains("music.douyin.com/qishui") else {
            throw PlaylistImportError.unsupported("请粘贴汽水音乐的分享链接，或按每行「歌名 - 歌手」粘贴歌曲列表。")
        }

        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw PlaylistImportError.invalidInput
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data = try await requestData(request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw PlaylistImportError.network("汽水分享页解码失败")
        }
        guard let marker = html.range(of: "_ROUTER_DATA = ") else {
            throw PlaylistImportError.unsupported("这个汽水分享页没有歌单数据，请换一个公开歌单链接。")
        }

        // _ROUTER_DATA 是一段嵌在分享页里的 JSON，后面还会接脚本代码；
        // 用花括号配对截出完整 JSON，避免把 JS 尾巴一起丢给 JSONSerialization。
        let start = marker.upperBound
        var depth = 0
        var inString = false
        var escaped = false
        var end = start
        var found = false
        for index in html.indices[start...] {
            let ch = html[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                else if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        end = html.index(after: index)
                        found = true
                        break
                    }
                }
            }
        }
        guard found,
              let json = try? JSONSerialization.jsonObject(with: Data(html[start..<end].utf8)) as? [String: Any],
              let loader = json["loaderData"] as? [String: Any],
              let page = loader["playlist_page"] as? [String: Any] else {
            throw PlaylistImportError.network("汽水歌单数据解析失败")
        }

        let info = page["playlistInfo"] as? [String: Any]
        let name = (info?["title"] as? String) ?? "汽水音乐歌单"
        let medias = (page["medias"] as? [[String: Any]]) ?? []
        var cover: URL?
        if let coverInfo = info?["url_cover"] as? [String: Any],
           let uri = coverInfo["uri"] as? String,
           let bases = coverInfo["urls"] as? [String],
           let base = bases.first,
           let prefix = coverInfo["template_prefix"] as? String {
            cover = URL(string: base + uri + "~tplv-\(prefix)-crop-center:720:720.jpg")
        }

        let tracks = medias.compactMap { media -> ExternalTrack? in
            guard let entity = media["entity"] as? [String: Any],
                  let track = entity["track"] as? [String: Any],
                  let title = track["name"] as? String, !title.isEmpty else { return nil }
            let artists = (track["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let album = (track["album"] as? [String: Any])?["name"] as? String
            return ExternalTrack(name: title, artist: artists.joined(separator: " / "), album: album)
        }
        guard !tracks.isEmpty else {
            throw PlaylistImportError.empty("这个汽水歌单里没有读到歌曲，可能是私密歌单或分享页已失效")
        }
        return ExternalPlaylist(name: name, coverURL: cover, tracks: tracks)
    }

    // MARK: - 工具

    private static func requestJSON(_ request: URLRequest) async throws -> [String: Any] {
        let data = try await requestData(request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlaylistImportError.network("平台返回的不是有效数据")
        }
        return json
    }

    private static func requestData(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw PlaylistImportError.network("平台请求失败（\(http.statusCode)）")
            }
            return data
        } catch let error as PlaylistImportError {
            throw error
        } catch {
            throw PlaylistImportError.network("网络请求失败：\(error.localizedDescription)")
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private static func looksLikePlainTrackList(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return lines.count >= 2 && !text.hasPrefix("http")
    }

    private static func parseTrackList(_ text: String) -> [ExternalTrack] {
        text.components(separatedBy: .newlines).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            // 去掉网易云/QQ 分享文本前的序号：1. 歌名 - 歌手
            line = line.replacingOccurrences(of: #"^\d+[.、)]\s*"#, with: "", options: .regularExpression)
            let separators = [" - ", " – ", " — ", "\t", "｜", "|"]
            for separator in separators where line.contains(separator) {
                let parts = line.components(separatedBy: separator)
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { return ExternalTrack(name: name, artist: artist, album: nil) }
            }
            return ExternalTrack(name: line, artist: "", album: nil)
        }
    }
}

enum PlaylistMatcher {
    static func match(_ tracks: [ExternalTrack], progress: @escaping @MainActor (Int, Int) -> Void) async -> [Song] {
        guard !tracks.isEmpty else { return [] }
        var results = [Song?](repeating: nil, count: tracks.count)
        let total = tracks.count

        await withTaskGroup(of: (Int, Song?).self) { group in
            var next = 0
            let initial = min(4, total)
            for _ in 0..<initial {
                let index = next
                next += 1
                let track = tracks[index]
                group.addTask { (index, await matchOne(track)) }
            }

            var finished = 0
            for await result in group {
                results[result.0] = result.1
                finished += 1
                await progress(finished, total)
                if next < total {
                    let index = next
                    next += 1
                    let track = tracks[index]
                    group.addTask { (index, await matchOne(track)) }
                }
            }
        }

        return results.compactMap { $0 }
    }

    private static func matchOne(_ track: ExternalTrack) async -> Song? {
        let query = [track.name, track.artist]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return nil }
        let songs = (try? await KGService.search(query, pageSize: 6)) ?? []
        guard !songs.isEmpty else { return nil }

        let targetName = normalize(track.name)
        let targetArtist = normalize(track.artist)
        let exact = songs.first { song in
            let name = normalize(song.SongName)
            let artist = normalize(song.SingerName)
            let nameOK = name == targetName || name.contains(targetName) || targetName.contains(name)
            let artistOK = targetArtist.isEmpty || artist.contains(targetArtist) || targetArtist.contains(artist)
            return nameOK && artistOK
        }
        if let exact { return exact }
        return songs.first { normalize($0.SongName).contains(targetName) } ?? songs.first
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "·", with: "")
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
