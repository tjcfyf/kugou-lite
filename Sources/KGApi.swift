import Foundation

enum KGError: LocalizedError {
    case server(String)
    case network
    case empty

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .network: return "网络不太稳定，稍后再试"
        case .empty: return "没有找到结果"
        }
    }
}

final class KGApi {
    static let shared = KGApi()

    /// 注册过的设备标识，一次生成后长期复用。
    let dfid = "0ioR4Q0iH0fq2IyTuR3vSaEC"
    let mid = "199824834906423470329396513350141137567"
    let appid = 1005
    let clientver = 20489

    var token: String?
    var userid: Int = 0

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept-Encoding": "gzip"]
        return URLSession(configuration: config)
    }()

    private init() {}

    func get(path: String,
             host: String = "https://gateway.kugou.com",
             params: [String: String],
             router: String? = nil) async throws -> Data {
        var all = params
        all["dfid"] = dfid
        all["mid"] = mid
        all["uuid"] = "-"
        all["appid"] = "\(appid)"
        all["clientver"] = "\(clientver)"
        all["clienttime"] = "\(Int(Date().timeIntervalSince1970))"
        if let token = token, !token.isEmpty { all["token"] = token }
        if userid != 0 { all["userid"] = "\(userid)" }

        let signature = KGSign.android(params: all)
        all["signature"] = signature

        guard var components = URLComponents(string: host + path) else { throw KGError.network }
        components.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw KGError.network }

        var request = URLRequest(url: url)
        request.setValue("Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi", forHTTPHeaderField: "User-Agent")
        request.setValue(dfid, forHTTPHeaderField: "dfid")
        request.setValue(mid, forHTTPHeaderField: "mid")
        request.setValue(all["clienttime"], forHTTPHeaderField: "clienttime")
        request.setValue("1", forHTTPHeaderField: "kg-rc")
        request.setValue("5d816a0", forHTTPHeaderField: "kg-thash")
        request.setValue("1", forHTTPHeaderField: "kg-rec")
        request.setValue("B9EDA08A64250DEFFBCADDEE00F8F25F", forHTTPHeaderField: "kg-rf")
        if let router = router { request.setValue(router, forHTTPHeaderField: "x-router") }
        if let token = token, !token.isEmpty {
            request.setValue("token=\(token); userid=\(userid)", forHTTPHeaderField: "Cookie")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw KGError.network }
            if http.statusCode >= 400 { throw KGError.server("服务返回 \(http.statusCode)") }
            return data
        } catch let error as KGError {
            throw error
        } catch {
            throw KGError.network
        }
    }

    /// 免签名的移动端接口（播放地址、歌词）。
    func plain(_ url: URL, cookie: Bool = false) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        if cookie, let token = token, !token.isEmpty {
            request.setValue("token=\(token); userid=\(userid)", forHTTPHeaderField: "Cookie")
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } catch {
            throw KGError.network
        }
    }
}
