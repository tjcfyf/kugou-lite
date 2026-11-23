import SwiftUI
import UIKit
import WebKit

enum ThirdPartyProvider: String, CaseIterable, Identifiable {
    case qq
    case wechat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qq: return "QQ 登录"
        case .wechat: return "微信登录"
        }
    }

    var shortTitle: String {
        switch self {
        case .qq: return "QQ"
        case .wechat: return "微信"
        }
    }

    var tint: Color {
        switch self {
        case .qq: return Color(red: 0.12, green: 0.56, blue: 0.98)
        case .wechat: return Color(red: 0.02, green: 0.69, blue: 0.24)
        }
    }

    /// 概念版 appid 3116，直接走 QQ/微信官方授权页，不套酷狗 openplat 外壳。
    /// 外壳页把 QQ 放在 iframe 里，iOS WKWebView 容易丢第三方 Cookie；
    /// 直连官方页是首方页面，二维码和回调都更稳定。
    var authURL: URL {
        let clienttime = String(Int(Date().timeIntervalSince1970))
        switch self {
        case .qq:
            return qqURL(clienttime: clienttime)
        case .wechat:
            return wechatURL(clienttime: clienttime)
        }
    }

    private func qqURL(clienttime: String) -> URL {
        let callback = "https://openplat-user.kugou.com/qq_callback"
            + "?ver=0&mid=\(KGApi.shared.mid)&dfid=\(KGApi.shared.dfid)"
            + "&https=1&domain=kugou.com&callback=SonoraThirdLogin"
            + "&plat=0&ktype=0&clienttime=\(clienttime)&appid=3116&platid=4"

        var components = URLComponents(string: "https://graph.qq.com/oauth2.0/show")!
        components.queryItems = [
            URLQueryItem(name: "which", value: "Login"),
            URLQueryItem(name: "display", value: "pc"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: "205141"),
            URLQueryItem(name: "redirect_uri", value: callback),
            URLQueryItem(name: "scope", value: "get_user_info"),
        ]
        return components.url!
    }

    private func wechatURL(clienttime: String) -> URL {
        let args: [String: Any] = [
            "mid": KGApi.shared.mid,
            "dfid": KGApi.shared.dfid,
            "https": "1",
            "domain": "kugou.com",
            "callback": "SonoraThirdLogin",
            "plat": 0,
            "ktype": 0,
            "clienttime": Int(clienttime) ?? 0,
            "appid": 3116,
            "platid": "4",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: args, options: [])) ?? Data()
        let encodedArgs = data.base64EncodedString()
        let callback = "https://openplat-user.kugou.com/wechat_callback?args=\(encodedArgs)"

        var components = URLComponents(string: "https://open.weixin.qq.com/connect/qrconnect")!
        components.queryItems = [
            URLQueryItem(name: "appid", value: "wxe1a0603d89981725"),
            URLQueryItem(name: "redirect_uri", value: callback),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "snsapi_login"),
            URLQueryItem(name: "state", value: ""),
        ]
        components.fragment = "wechat_redirect"
        return components.url!
    }

    var userAgent: String {
        // 强制桌面版 QQ/微信扫码页。移动版 QQ 会走“一键登录”并跳转 QQ App，
        // 回调无法可靠回到本 App；桌面版直接展示二维码，扫码完成后再回到网页。
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    }
}

struct ThirdPartyLoginView: View {
    let provider: ThirdPartyProvider
    let onLogin: (String, Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()

                ThirdPartyWebView(
                    url: provider.authURL,
                    userAgent: provider.userAgent,
                    loading: $loading,
                    onLogin: { token, userid, vipToken in
                        onLogin(token, userid, vipToken)
                        dismiss()
                    },
                    onFailure: { message in
                        loading = false
                        errorMessage = message
                        showError = true
                    }
                )

                if loading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.text))
                        Text("正在打开\(provider.shortTitle)…")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .padding(22)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .navigationTitle(provider.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundColor(Theme.text)
                }
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("\(provider.shortTitle) 登录失败"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("知道了"))
                )
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct ThirdPartyWebView: UIViewRepresentable {
    let url: URL
    let userAgent: String
    @Binding var loading: Bool
    let onLogin: (String, Int, String?) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // 部分第三方页面会同时看 UA 和 navigator.platform。只改 UA 有时仍被
        // 判成手机，QQ 会退回“一键登录”；这里把平台信息也伪装成桌面 Mac。
        let desktopScript = """
        Object.defineProperty(navigator, 'platform', { get: function() { return 'MacIntel'; } });
        Object.defineProperty(navigator, 'maxTouchPoints', { get: function() { return 0; } });
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: desktopScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.attach(webView)
        context.coordinator.prepareAndLoad(url)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var parent: ThirdPartyWebView
        private weak var webView: WKWebView?
        private var timer: Timer?
        private var completed = false
        private var checking = false
        private var failureWorkItem: DispatchWorkItem?

        init(parent: ThirdPartyWebView) {
            self.parent = parent
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
        }

        /// 先清掉旧的 KuGoo 登录态，避免上次登录的 cookie 让本次直接“成功”。
        func prepareAndLoad(_ url: URL) {
            guard let webView = webView else { return }
            let store = webView.configuration.websiteDataStore.httpCookieStore
            store.getAllCookies { [weak self] cookies in
                let group = DispatchGroup()
                for cookie in cookies where cookie.name == "KuGoo" {
                    group.enter()
                    store.delete(cookie) { group.leave() }
                }
                group.notify(queue: .main) {
                    guard let self = self else { return }
                    self.startPolling()
                    webView.load(URLRequest(url: url))
                }
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            failureWorkItem?.cancel()
            failureWorkItem = nil
        }

        private func startPolling() {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
                self?.checkCookies()
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func checkCookies() {
            guard !completed, !checking, let webView = webView else { return }
            checking = true
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self else { return }
                self.checking = false
                for cookie in cookies where cookie.name == "KuGoo" {
                    if let result = Self.parseKuGoo(cookie.value) {
                        DispatchQueue.main.async {
                            guard !self.completed else { return }
                            self.completed = true
                            self.stop()
                            self.parent.loading = false
                            self.parent.onLogin(result.token, result.userid, result.vipToken)
                        }
                        return
                    }
                }
            }
        }

        private static func parseKuGoo(_ raw: String) -> (token: String, userid: Int, vipToken: String?)? {
            var source = raw
            // 少数情况下整个 cookie 被 URL 编码；只在没有 '=' 时整体解一次，
            // 避免把 token 里的 %26 提前解码成 & 拆错字段。
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

        private func finishWithError(_ message: String) {
            guard !completed else { return }
            completed = true
            stop()
            DispatchQueue.main.async {
                self.parent.loading = false
                self.parent.onFailure(message)
            }
        }

        /// 不在导航失败时立刻报错：qq_callback / wechat_callback 的 302 响应
        /// 可能已经先写好了 KuGoo，只是后面的 cross.*/callmsg 页面打不开。
        /// 所以先等一拍读 cookie，读不到再显示错误。
        private func scheduleFailure(_ message: String, delay: TimeInterval) {
            guard !completed, failureWorkItem == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, !self.completed else { return }
                self.checkCookies()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                    guard let self = self, !self.completed else { return }
                    self.checkCookies()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                        guard let self = self, !self.completed else { return }
                        self.finishWithError(message)
                    }
                }
            }
            failureWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        private func handleNavigation(_ url: URL?) {
            guard let url = url else { return }
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()

            if host.contains("openplat-user.kugou.com") && path.contains("_callback") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.checkCookies()
                }
            }

            if host.hasPrefix("cross.") && host.hasSuffix("kugou.com") && path.contains("callmsg") {
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let code = items.first(where: { $0.name == "errcode" })?.value
                let message = items.first(where: { $0.name == "msg" })?.value

                if let code = code, code != "0" {
                    let detail = message?.isEmpty == false ? message! : "第三方登录未完成"
                    scheduleFailure("\(detail)（\(code)）", delay: 1.2)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.checkCookies()
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.loading = false
            checkCookies()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleFailure(error)
        }

        private func handleFailure(_ error: Error) {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            scheduleFailure(nsError.localizedDescription, delay: 0.8)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               let host = url.host?.lowercased() {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var rewrite = false

                // cross.www.kugou.com 在部分网络下解析失败，会白屏；
                // 酷狗自己的跨域回调页在 cross.kugou.com 上同样可用。
                if host == "cross.www.kugou.com" {
                    components?.host = "cross.kugou.com"
                    rewrite = true
                }

                // 酷狗回调/http 页面统一走 https，和 YAQMC 的处理一致。
                if url.scheme?.lowercased() == "http",
                   host == "openplat-user.kugou.com"
                    || (host.hasPrefix("cross.") && host.hasSuffix("kugou.com")) {
                    components?.scheme = "https"
                    rewrite = true
                }

                if rewrite, let fixedURL = components?.url, fixedURL != url {
                    decisionHandler(.cancel)
                    webView.load(URLRequest(url: fixedURL))
                    return
                }
            }
            handleNavigation(navigationAction.request.url)
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
