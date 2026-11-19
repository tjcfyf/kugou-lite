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
    let dev = "XG9WZZIL4J"
    let appid = 1005
    let clientver = 20489

    var token: String?
    var userid: Int = 0

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Requests

    func get(path: String,
             host: String = "https://gateway.kugou.com",
             params: [String: String],
             router: String? = nil,
             lite: Bool = false) async throws -> Data {
        var all = merged(params, lite: lite)
        all["signature"] = KGSign.sign(params: all, salt: lite ? KGSign.liteSalt : KGSign.androidSalt)
        guard let url = makeURL(host: host, path: path, params: all) else { throw KGError.network }
        var request = makeRequest(url: url, params: all, router: router)
        request.httpMethod = "GET"
        return try await send(request)
    }

    func post(path: String,
              host: String = "https://gateway.kugou.com",
              params: [String: String],
              body: [String: Any]? = nil,
              contentType: String? = nil,
              router: String? = nil,
              lite: Bool = false) async throws -> Data {
        var all = merged(params, lite: lite)
        let bodyString: String
        if let body = body, let data = try? JSONSerialization.data(withJSONObject: body),
           let string = String(data: data, encoding: .utf8) {
            bodyString = string
        } else {
            bodyString = ""
        }
        all["signature"] = KGSign.sign(params: all,
                                        salt: lite ? KGSign.liteSalt : KGSign.androidSalt,
                                        data: bodyString)
        guard let url = makeURL(host: host, path: path, params: all) else { throw KGError.network }
        var request = makeRequest(url: url, params: all, router: router)
        request.httpMethod = "POST"
        if !bodyString.isEmpty {
            request.httpBody = Data(bodyString.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let contentType = contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return try await send(request)
    }

    /// Web 版签名（登录二维码接口用）。
    func webGet(path: String, host: String, params: [String: String]) async throws -> Data {
        var all = merged(params)
        all["signature"] = KGSign.web(params: all)
        guard let url = makeURL(host: host, path: path, params: all) else { throw KGError.network }
        let request = makeRequest(url: url, params: all, router: nil)
        return try await send(request)
    }

    /// Web/H5 签名（活动页领取会员用）。
    func webPost(path: String,
                 host: String = "https://gateway.kugou.com",
                 params: [String: String]) async throws -> Data {
        var all = merged(params)
        all["signature"] = KGSign.web(params: all)
        guard let url = makeURL(host: host, path: path, params: all) else { throw KGError.network }
        var request = makeRequest(url: url, params: all, router: nil)
        request.httpMethod = "POST"
        return try await send(request)
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

    // MARK: - Plumbing

    private func merged(_ extra: [String: String], lite: Bool = false) -> [String: String] {
        var all = extra
        if all["dfid"] == nil { all["dfid"] = dfid }
        if all["mid"] == nil { all["mid"] = mid }
        if all["uuid"] == nil { all["uuid"] = "-" }
        if all["appid"] == nil { all["appid"] = lite ? "3116" : "\(appid)" }
        if all["clientver"] == nil { all["clientver"] = lite ? "11440" : "\(clientver)" }
        all["clienttime"] = "\(Int(Date().timeIntervalSince1970))"
        if let token = token, !token.isEmpty { all["token"] = token }
        if userid != 0 { all["userid"] = "\(userid)" }
        return all
    }

    private func makeURL(host: String, path: String, params: [String: String]) -> URL? {
        guard var components = URLComponents(string: host + path) else { return nil }
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url
    }

    private func makeRequest(url: URL, params: [String: String], router: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi", forHTTPHeaderField: "User-Agent")
        request.setValue(dfid, forHTTPHeaderField: "dfid")
        request.setValue(mid, forHTTPHeaderField: "mid")
        request.setValue(params["clienttime"], forHTTPHeaderField: "clienttime")
        request.setValue("1", forHTTPHeaderField: "kg-rc")
        request.setValue("5d816a0", forHTTPHeaderField: "kg-thash")
        request.setValue("1", forHTTPHeaderField: "kg-rec")
        request.setValue("B9EDA08A64250DEFFBCADDEE00F8F25F", forHTTPHeaderField: "kg-rf")
        if let router = router { request.setValue(router, forHTTPHeaderField: "x-router") }
        if let token = token, !token.isEmpty {
            request.setValue("token=\(token); userid=\(userid); dfid=\(dfid); mid=\(mid)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
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
}
