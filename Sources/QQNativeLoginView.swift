import SwiftUI
import UIKit
import Foundation

/// QQ 原生扫码登录。
///
/// 不再把 QQ 授权页放进 WKWebView：iOS 的 WKWebView 对第三方 iframe 的
/// Cookie 隔离很严格，QQ 扫码成功后 ptlogin 的会话 Cookie 经常带不进
/// graph.qq.com 的授权跳转，表现就是“手机 QQ 显示登录成功，网页又换一张码”。
/// 这里直接用 URLSession 走 QQ 的 ptqrshow / ptqrlogin 协议，二维码用原生
/// UIImage 显示，扫码确认后拿 code，再把 code 交给酷狗 qq_callback 换 KuGoo。
struct QQNativeLoginView: View {
    let reloadID: Int
    let onLogin: (String, Int, String?) -> Void
    let onFailure: (String) -> Void

    @StateObject private var model: QQNativeLoginModel

    init(reloadID: Int,
         onLogin: @escaping (String, Int, String?) -> Void,
         onFailure: @escaping (String) -> Void) {
        self.reloadID = reloadID
        self.onLogin = onLogin
        self.onFailure = onFailure
        _model = StateObject(wrappedValue: QQNativeLoginModel(onLogin: onLogin, onFailure: onFailure))
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 18)

            Text("QQ 快捷登录")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(Theme.text)

            Text("用手机 QQ 扫码，并在手机上确认授权")
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.card)

                if let image = model.qrImage {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.text))
                }
            }
            .frame(width: 236, height: 236)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )

            Text(model.status)
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Button("重新获取二维码") {
                    model.restart()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.text)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Theme.card)
                .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: reloadID) { _ in
            model.restart()
        }
    }
}

@MainActor
final class QQNativeLoginModel: ObservableObject {
    @Published var qrImage: UIImage?
    @Published var status = "正在获取二维码…"
    @Published var errorMessage: String?

    private let onLogin: (String, Int, String?) -> Void
    private let onFailure: (String) -> Void

    private var net: QQNet?
    private var task: Task<Void, Never>?
    private var running = false
    private var completed = false
    private var qrsig = ""
    private var ptLoginSig = ""
    private var didReportScanned = false

    init(onLogin: @escaping (String, Int, String?) -> Void,
         onFailure: @escaping (String) -> Void) {
        self.onLogin = onLogin
        self.onFailure = onFailure
    }

    func start() {
        guard !running else { return }
        running = true
        completed = false
        errorMessage = nil
        didReportScanned = false
        status = "正在获取二维码…"
        clearKuGooCookies()
        net = QQNet()
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        running = false
        task?.cancel()
        task = nil
        net?.session.invalidateAndCancel()
        net = nil
    }

    func restart() {
        stop()
        qrImage = nil
        start()
    }

    private func runLoop() async {
        while running {
            do {
                try await fetchQR()
            } catch {
                fail("二维码获取失败：\(error.localizedDescription)")
                return
            }

            var needNewQR = false
            while running && !needNewQR {
                do {
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                } catch {
                    return
                }

                do {
                    let result = try await pollOnce()
                    switch result {
                    case .waiting:
                        break
                    case .scanned:
                        if !didReportScanned {
                            didReportScanned = true
                            status = "已扫码，请在手机 QQ 上点击确认"
                        }
                    case .expired:
                        status = "二维码已失效，正在刷新…"
                        needNewQR = true
                    case .rejected:
                        fail("已在手机 QQ 上取消登录")
                        return
                    case .success(let authURL):
                        status = "已确认，正在换取登录态…"
                        try await completeAuth(authURL)
                        return
                    }
                } catch {
                    fail("QQ 登录失败：\(error.localizedDescription)")
                    return
                }
            }

            if needNewQR {
                qrImage = nil
                didReportScanned = false
            }
        }
    }

    private func fetchQR() async throws {
        guard let net = net else { throw QQLoginError("网络未初始化") }

        var xlogin = URLComponents(string: "https://xui.ptlogin2.qq.com/cgi-bin/xlogin")!
        xlogin.queryItems = [
            URLQueryItem(name: "appid", value: "716027609"),
            URLQueryItem(name: "daid", value: "383"),
            URLQueryItem(name: "style", value: "33"),
            URLQueryItem(name: "hide_title_bar", value: "1"),
            URLQueryItem(name: "hide_border", value: "1"),
            URLQueryItem(name: "target", value: "self"),
            URLQueryItem(name: "s_url", value: "https://graph.qq.com/oauth2.0/login_jump"),
            URLQueryItem(name: "pt_3rd_aid", value: "205141"),
        ]
        _ = try await net.get(xlogin.url!)

        var qr = URLComponents(string: "https://ssl.ptlogin2.qq.com/ptqrshow")!
        qr.queryItems = [
            URLQueryItem(name: "appid", value: "716027609"),
            URLQueryItem(name: "e", value: "2"),
            URLQueryItem(name: "l", value: "M"),
            URLQueryItem(name: "s", value: "3"),
            URLQueryItem(name: "d", value: "72"),
            URLQueryItem(name: "v", value: "4"),
            URLQueryItem(name: "t", value: String(Double.random(in: 0..<1))),
            URLQueryItem(name: "daid", value: "383"),
            URLQueryItem(name: "pt_3rd_aid", value: "205141"),
            URLQueryItem(name: "u1", value: "https://graph.qq.com/oauth2.0/login_jump"),
        ]

        let (data, _) = try await net.get(qr.url!)
        guard let image = UIImage(data: data), image.size.width > 0 else {
            throw QQLoginError("QQ 没有返回二维码图片")
        }

        qrsig = cookie(named: "qrsig")
        ptLoginSig = cookie(named: "pt_login_sig")
        guard !qrsig.isEmpty else {
            throw QQLoginError("QQ 没有返回 qrsig")
        }

        qrImage = image
        status = "请用手机 QQ 扫码"
        didReportScanned = false
    }

    private enum PollResult {
        case waiting
        case scanned
        case expired
        case rejected
        case success(String)
    }

    private func pollOnce() async throws -> PollResult {
        guard let net = net else { throw QQLoginError("网络未初始化") }

        var components = URLComponents(string: "https://ssl.ptlogin2.qq.com/ptqrlogin")!
        components.queryItems = [
            URLQueryItem(name: "u1", value: "https://graph.qq.com/oauth2.0/login_jump"),
            URLQueryItem(name: "ptqrtoken", value: String(ptqrToken(qrsig))),
            URLQueryItem(name: "ptredirect", value: "0"),
            URLQueryItem(name: "h", value: "1"),
            URLQueryItem(name: "t", value: "1"),
            URLQueryItem(name: "g", value: "1"),
            URLQueryItem(name: "from_ui", value: "1"),
            URLQueryItem(name: "ptlang", value: "2052"),
            URLQueryItem(name: "action", value: "0-0-\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "js_ver", value: "23071715"),
            URLQueryItem(name: "js_type", value: "1"),
            URLQueryItem(name: "login_sig", value: ptLoginSig),
            URLQueryItem(name: "pt_uistyle", value: "40"),
            URLQueryItem(name: "aid", value: "716027609"),
            URLQueryItem(name: "daid", value: "383"),
            URLQueryItem(name: "pt_3rd_aid", value: "205141"),
            URLQueryItem(name: "has_onekey", value: "1"),
        ]

        let (data, _) = try await net.get(components.url!)
        let text = String(data: data, encoding: .utf8) ?? ""

        if let parsed = parsePTUICB(text) {
            return parsed
        }
        if text.contains("二维码已失效") { return .expired }
        if text.contains("登录成功") {
            // 极少数情况下 ptuiCB 被截断；用正则兜底拿第三个字段。
            if let range = text.range(of: "https://ptlogin2.graph.qq.com/check_sig") {
                let tail = String(text[range.lowerBound...])
                return .success(tail)
            }
        }
        return .waiting
    }

    private func parsePTUICB(_ text: String) -> PollResult? {
        let pattern = #"ptuiCB\('(\d+)','[^']*','([^']*)','[^']*','([^']*)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 4 else {
            return nil
        }
        let code = ns.substring(with: match.range(at: 1))
        let rawURL = ns.substring(with: match.range(at: 3))
            .replacingOccurrences(of: "&amp;", with: "&")

        switch code {
        case "66":
            return .waiting
        case "67":
            return .scanned
        case "65":
            return .expired
        case "68":
            return .rejected
        case "0":
            return .success(rawURL)
        default:
            return .waiting
        }
    }

    private func completeAuth(_ authURL: String) async throws {
        guard let net = net else { throw QQLoginError("网络未初始化") }
        guard let url = URL(string: authURL) else {
            throw QQLoginError("QQ 返回的登录地址无效")
        }

        // check_sig 会带 qrsig / pt_login_sig 换到 p_skey 等 QQ 会话 Cookie。
        // 这里不关心它的最终页面，只要 Cookie 落到同一个 URLSession 里。
        net.delegate.stopAtKugouCallback = false
        _ = try await net.get(url)

        var authorize = URLComponents(string: "https://graph.qq.com/oauth2.0/authorize")!
        authorize.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: "205141"),
            URLQueryItem(name: "redirect_uri", value: callbackURL(code: nil).absoluteString),
            URLQueryItem(name: "scope", value: "get_user_info"),
            URLQueryItem(name: "state", value: UUID().uuidString.replacingOccurrences(of: "-", with: "")),
        ]

        net.delegate.resetCapturedCode()
        net.delegate.stopAtKugouCallback = true
        let (authorizeData, authorizeResponse) = try await net.get(authorize.url!)

        var code = net.delegate.capturedCode
        if code == nil {
            code = extractCode(from: authorizeData, response: authorizeResponse)
        }
        guard let code = code, !code.isEmpty else {
            throw QQLoginError("QQ 已授权，但没有返回 code。可能是 QQ 授权页要求重新登录。")
        }

        status = "QQ 授权成功，正在同步酷狗账号…"
        net.delegate.stopAtKugouCallback = false
        let callback = callbackURL(code: code)
        _ = try await net.get(callback)

        // 酷狗 qq_callback 可能 302 到 cross.kugou.com/callmsg，等一拍再读 Cookie。
        try? await Task.sleep(nanoseconds: 600_000_000)

        if let session = findKuGooSession() {
            completed = true
            running = false
            task?.cancel()
            status = "登录成功"
            onLogin(session.token, session.userid, session.vipToken)
        } else {
            throw QQLoginError("QQ 已授权，但酷狗没有写入 KuGoo 登录态。")
        }
    }

    private func callbackURL(code: String?) -> URL {
        var components = URLComponents(string: "https://openplat-user.kugou.com/qq_callback")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "ver", value: "0"),
            URLQueryItem(name: "mid", value: KGApi.shared.mid),
            URLQueryItem(name: "dfid", value: KGApi.shared.dfid),
            URLQueryItem(name: "https", value: "1"),
            URLQueryItem(name: "domain", value: "kugou.com"),
            URLQueryItem(name: "callback", value: "SonoraThirdLogin"),
            URLQueryItem(name: "plat", value: "0"),
            URLQueryItem(name: "ktype", value: "0"),
            URLQueryItem(name: "clienttime", value: String(Int(Date().timeIntervalSince1970))),
            URLQueryItem(name: "appid", value: "3116"),
            URLQueryItem(name: "platid", value: "4"),
        ]
        if let code = code {
            items.append(URLQueryItem(name: "code", value: code))
        }
        components.queryItems = items
        return components.url!
    }

    private func extractCode(from data: Data, response: URLResponse) -> String? {
        if let url = response.url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            return code
        }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let patterns = [
            #"[?&]code=([A-Za-z0-9]+)"#,
            #""code"\s*:\s*"([A-Za-z0-9]+)""#,
            #"code%3D([A-Za-z0-9]+)"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: text, range: range), match.numberOfRanges >= 2 {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    private func ptqrToken(_ sig: String) -> Int {
        var value = 0
        for scalar in sig.unicodeScalars {
            value += (value << 5) + Int(scalar.value)
            value &= 0x7fffffff
        }
        return value & 0x7fffffff
    }

    private func cookie(named name: String) -> String {
        (HTTPCookieStorage.shared.cookies ?? [])
            .first(where: { $0.name == name })?
            .value ?? ""
    }

    private func clearKuGooCookies() {
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies ?? [] where cookie.name == "KuGoo" {
            storage.deleteCookie(cookie)
        }
    }

    private func findKuGooSession() -> (token: String, userid: Int, vipToken: String?)? {
        let storage = HTTPCookieStorage.shared
        var cookies = storage.cookies ?? []
        if let url = URL(string: "https://openplat-user.kugou.com/") {
            cookies.append(contentsOf: storage.cookies(for: url) ?? [])
        }
        for cookie in cookies where cookie.name == "KuGoo" {
            if let parsed = parseKuGoo(cookie.value) {
                return parsed
            }
        }
        return nil
    }

    private func parseKuGoo(_ raw: String) -> (token: String, userid: Int, vipToken: String?)? {
        var source = raw
        if !source.contains("="), let decoded = source.removingPercentEncoding {
            source = decoded
        }

        var token: String?
        var userid: Int?
        var vipToken: String?

        for pair in source.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            switch key.lowercased() {
            case "t", "token":
                token = value
            case "kugouid", "kugoo_id", "userid":
                userid = Int(value)
            case "vip_token", "viptoken":
                vipToken = value
            default:
                continue
            }
        }

        guard let token = token, !token.isEmpty,
              let userid = userid, userid > 0 else {
            return nil
        }
        return (token, userid, vipToken)
    }

    private func fail(_ message: String) {
        guard !completed else { return }
        completed = true
        running = false
        task?.cancel()
        status = "登录失败"
        errorMessage = message
        onFailure(message)
    }
}

private struct QQLoginError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private final class QQRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var storedCode: String?
    var stopAtKugouCallback = false

    var capturedCode: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedCode
    }

    func resetCapturedCode() {
        lock.lock()
        storedCode = nil
        lock.unlock()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            lock.lock()
            storedCode = code
            lock.unlock()
        }

        if stopAtKugouCallback,
           let url = request.url,
           url.host?.lowercased() == "openplat-user.kugou.com",
           url.path.lowercased().contains("qq_callback") {
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}

private final class QQNet {
    let session: URLSession
    let delegate: QQRedirectDelegate

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30

        delegate = QQRedirectDelegate()
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func get(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://xui.ptlogin2.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        return try await session.data(for: request, delegate: delegate)
    }
}
