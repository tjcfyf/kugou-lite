import AuthenticationServices
import Foundation
import UIKit

struct QQAuthorization {
    let accessToken: String
    let openid: String
}

/// 用 ASWebAuthenticationSession 打开 QQ 的移动授权页。
/// 页面会优先唤起手机 QQ；用户在 QQ 内点确认后，回调
/// tencent205141://tauth.qq.com/#access_token=...&openid=...
/// 直接回到本 App，不需要在 Sonora 里扫二维码。
final class QQAppLoginSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = QQAppLoginSession()

    private var session: ASWebAuthenticationSession?
    private var completion: ((Result<QQAuthorization, Error>) -> Void)?

    func start(completion: @escaping (Result<QQAuthorization, Error>) -> Void) {
        self.completion = completion

        var components = URLComponents(string: "https://openmobile.qq.com/oauth2.0/m_authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: "205141"),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: "get_user_info"),
            URLQueryItem(name: "redirect_uri", value: "tencent205141://tauth.qq.com/"),
            URLQueryItem(name: "display", value: "mobile"),
            URLQueryItem(name: "callback_type", value: "scheme"),
            URLQueryItem(name: "callback_name", value: "tencent205141"),
            URLQueryItem(name: "cancel_display", value: "1"),
            URLQueryItem(name: "switch", value: "1"),
            URLQueryItem(name: "compat_v", value: "1"),
        ]

        guard let url = components.url else {
            finish(.failure(QQLoginError("QQ 授权地址生成失败")))
            return
        }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "tencent205141") { [weak self] callback, error in
            guard let self else { return }
            if let error {
                let ns = error as NSError
                if ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    self.finish(.failure(QQLoginError("你取消了 QQ 授权")))
                } else {
                    self.finish(.failure(QQLoginError("QQ 授权失败：\(error.localizedDescription)")))
                }
                return
            }
            guard let callback, let auth = Self.parse(callback) else {
                self.finish(.failure(QQLoginError("QQ 没有返回 access_token 或 openid")))
                return
            }
            self.finish(.success(auth))
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        if !session.start() {
            finish(.failure(QQLoginError("无法打开 QQ 授权页")))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
        return window ?? ASPresentationAnchor()
    }

    private func finish(_ result: Result<QQAuthorization, Error>) {
        let block = completion
        completion = nil
        session = nil
        DispatchQueue.main.async {
            block?(result)
        }
    }

    private static func parse(_ url: URL) -> QQAuthorization? {
        var items: [URLQueryItem] = []
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            items.append(contentsOf: components.queryItems ?? [])
            if let fragment = components.fragment,
               let fragmentComponents = URLComponents(string: "?" + fragment) {
                items.append(contentsOf: fragmentComponents.queryItems ?? [])
            }
        }
        let token = items.first(where: { $0.name == "access_token" })?.value ?? ""
        let openid = items.first(where: { $0.name == "openid" })?.value ?? ""
        guard !token.isEmpty, !openid.isEmpty else { return nil }
        return QQAuthorization(accessToken: token, openid: openid)
    }
}

struct QQLoginError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
