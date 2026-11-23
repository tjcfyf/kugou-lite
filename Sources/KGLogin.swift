import UIKit

struct KugouQRCode {
    let key: String
    let image: UIImage?
}

enum KGLogin {
    static func createQR() async throws -> KugouQRCode {
        let data = try await KGApi.shared.webGet(
            path: "/v2/qrcode",
            host: "https://login-user.kugou.com",
            params: [
                "appid": "1001",
                "type": "1",
                "plat": "4",
                "qrcode_txt": "https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=3116&",
                "srcappid": "2919",
            ]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let key = payload["qrcode"] as? String else {
            throw KGError.server("二维码生成失败")
        }

        var image: UIImage?
        if let raw = payload["qrcode_img"] as? String {
            let base64 = raw.components(separatedBy: ",").last ?? raw
            if let bytes = Data(base64Encoded: base64) {
                image = UIImage(data: bytes)
            }
        }
        return KugouQRCode(key: key, image: image)
    }

    static func check(_ key: String) async throws -> (status: Int, token: String?, userid: Int?, vipToken: String?) {
        let data = try await KGApi.shared.webGet(
            path: "/v2/get_userinfo_qrcode",
            host: "https://login-user.kugou.com",
            params: [
                "plat": "4",
                "appid": "3116",
                "srcappid": "2919",
                "qrcode": key,
                "dev": KGApi.shared.dev,
            ]
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any] else {
            throw KGError.server("二维码状态异常")
        }
        let status = Song.intValue(payload["status"]) ?? 0
        return (
            status,
            payload["token"] as? String,
            Song.intValue(payload["userid"]),
            (payload["vip_token"] as? String) ?? (payload["vipToken"] as? String)
        )
    }
}

struct PhoneLoginResult {
    let userid: Int
    let token: String
    let vipToken: String?
}

extension KGLogin {
    /// 概念版短信验证码接口。失败时把酷狗返回的错误码/文案原样带到界面上。
    static func sendSMSCode(phone: String) async throws {
        guard isValidPhone(phone) else {
            throw KGError.server("请输入正确的 11 位手机号")
        }
        let data = try await KGApi.shared.post(
            path: "/v7/send_mobile_code",
            host: "http://login.user.kugou.com",
            params: [:],
            body: [
                "businessid": 5,
                "mobile": phone,
                "plat": 3,
            ],
            lite: true
        )
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("验证码接口返回异常")
        }
        let errorCode = Song.intValue(root["error_code"]) ?? 0
        let status = Song.intValue(root["status"]) ?? 0
        if errorCode != 0 || (status != 0 && status != 1) {
            throw KGError.server(serverMessage(root, fallback: "验证码发送失败"))
        }
        if status == 0 && errorCode == 0,
           let message = root["error_msg"] as? String, !message.isEmpty {
            throw KGError.server(message)
        }
    }

    /// 概念版 v7 手机号+验证码登录。`p2 / t1 / t2` 都是客户端加密参数，
    /// `params` 里才是真正的手机号和验证码。
    static func loginByPhone(phone: String, code: String) async throws -> PhoneLoginResult {
        guard isValidPhone(phone) else {
            throw KGError.server("请输入正确的 11 位手机号")
        }
        guard (4...6).contains(code.count), code.allSatisfy({ $0.isNumber }) else {
            throw KGError.server("请输入短信验证码")
        }

        let clientTime = Int64(Date().timeIntervalSince1970 * 1000)
        let randomKey = KGLoginCrypto.randomKey()
        let paramsJSON = "{\"mobile\":\"\(phone)\",\"code\":\"\(code)\"}"
        guard let params = KGLoginCrypto.aesParamsHex(paramsJSON, randomKey: randomKey) else {
            throw KGError.server("登录参数加密失败")
        }
        let pkJSON = "{\"clienttime_ms\":\(clientTime),\"key\":\"\(randomKey)\"}"
        guard let pk = KGRSA.encryptRawNoPadding(Data(pkJSON.utf8), key: .lite) else {
            throw KGError.server("登录密钥加密失败")
        }
        guard let t1 = KGLoginCrypto.aesHex("|\(clientTime)",
                                           key: KGLoginCrypto.t1Key,
                                           iv: KGLoginCrypto.t1IV),
              let t2 = KGLoginCrypto.aesHex(
                [
                    KGLoginCrypto.guid(),
                    KGLoginCrypto.t2DeviceSalt,
                    "02:00:00:00:00:00",
                    KGApi.shared.dev,
                    String(clientTime),
                ].joined(separator: "|"),
                key: KGLoginCrypto.t2Key,
                iv: KGLoginCrypto.t2IV
              ) else {
            throw KGError.server("设备参数加密失败")
        }

        let body: [String: Any] = [
            "plat": 1,
            "support_multi": 1,
            "t1": t1,
            "t2": t2,
            "clienttime_ms": Int(clientTime),
            "mobile": KGLoginCrypto.maskedPhone(phone),
            "key": KGLoginCrypto.loginKey(clientTime: clientTime),
            "pk": pk,
            "params": params,
            "dfid": KGApi.shared.dfid,
            "dev": KGApi.shared.dev,
            "gitversion": "5f0b7c4",
        ]

        let data = try await KGApi.shared.post(
            path: "/v7/login_by_verifycode",
            host: "https://loginserviceretry.kugou.com",
            params: [:],
            body: body,
            headers: [
                "SUPPORT-CALM": "1",
                "User-Agent": "Android16-1070-11440-130-0-LOGIN-wifi",
            ],
            lite: true
        )

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("登录接口返回异常")
        }
        let status = Song.intValue(root["status"]) ?? 0
        guard status == 1, let payload = root["data"] as? [String: Any] else {
            throw KGError.server(serverMessage(root, fallback: "登录失败，请检查验证码"))
        }
        guard let userid = Song.intValue(payload["userid"]), userid > 0 else {
            throw KGError.server(serverMessage(root, fallback: "登录成功但没有拿到用户 ID"))
        }

        var token: String?
        if let secured = payload["secu_params"] as? String, !secured.isEmpty {
            token = KGLoginCrypto.aesParamsString(hex: secured, randomKey: randomKey)
                .flatMap { extractToken($0) }
        }
        if token == nil {
            token = (payload["token"] as? String).flatMap { extractToken($0) }
        }
        guard let token = token, !token.isEmpty else {
            throw KGError.server("登录成功但没有拿到 token")
        }

        let vipToken = (payload["vip_token"] as? String)
            ?? (payload["vipToken"] as? String)
            ?? (payload["secu_vip_token"] as? String)
        return PhoneLoginResult(userid: userid, token: token, vipToken: vipToken)
    }

    /// 概念版开放平台登录：QQ App 授权拿到 access_token/openid 后，
    /// 由 /v6/login_by_openplat 直接换酷狗 token，不再依赖网页 qq_callback 的 Cookie。
    static func loginByOpenPlat(accessToken: String, openid: String) async throws -> PhoneLoginResult {
        guard !accessToken.isEmpty, !openid.isEmpty else {
            throw KGError.server("QQ 没有返回完整的授权信息")
        }

        let clientTime = Int64(Date().timeIntervalSince1970 * 1000)
        let randomKey = KGLoginCrypto.randomKey()
        let paramsJSON = "{\"access_token\":\"\(accessToken)\"}"
        guard let params = KGLoginCrypto.aesParamsHex(paramsJSON, randomKey: randomKey) else {
            throw KGError.server("登录参数加密失败")
        }
        let pkJSON = "{\"clienttime_ms\":\(clientTime),\"key\":\"\(randomKey)\"}"
        guard let pk = KGRSA.encryptRawNoPadding(Data(pkJSON.utf8), key: .lite) else {
            throw KGError.server("登录密钥加密失败")
        }

        let dev = "android\(clientTime)"
        guard let t1 = KGLoginCrypto.aesHex("|\(clientTime)",
                                           key: KGLoginCrypto.t1Key,
                                           iv: KGLoginCrypto.t1IV),
              let t2 = KGLoginCrypto.aesHex(
                [
                    KGLoginCrypto.guid(),
                    KGLoginCrypto.t2DeviceSalt,
                    "02:00:00:00:00:00",
                    dev,
                    String(clientTime),
                ].joined(separator: "|"),
                key: KGLoginCrypto.t2Key,
                iv: KGLoginCrypto.t2IV
              ) else {
            throw KGError.server("设备参数加密失败")
        }

        let body: [String: Any] = [
            "dev": dev,
            "force_login": 1,
            "partnerid": 1,
            "clienttime_ms": Int(clientTime),
            "t1": t1,
            "t2": t2,
            "t3": "MCwwLDAsMCwwLDAsMCwwLDA=",
            "openid": openid,
            "third_appid": "101706348",
            "params": params,
            "pk": pk,
        ]

        let data = try await KGApi.shared.post(
            path: "/v6/login_by_openplat",
            host: "http://login.user.kugou.com",
            params: [
                "plat": "1",
                "userid": "0",
                "token": "",
                "t_mid": KGApi.shared.mid,
                "t": KGLoginCrypto.guid(),
                "t_appid": "3116",
                "t_clientver": "10597",
                "srcappid": "2919",
                "third_appid": "101706348",
                "partnerid": "1",
                "force_bind": "1",
            ],
            body: body,
            headers: [
                "x-router": "login.user.kugou.com",
                "SUPPORT-CALM": "1",
                "User-Agent": "Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi",
            ],
            lite: true
        )

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw KGError.server("登录接口返回异常")
        }
        let status = Song.intValue(root["status"]) ?? 0
        guard status == 1, let payload = root["data"] as? [String: Any] else {
            throw KGError.server(serverMessage(root, fallback: "QQ 登录失败"))
        }

        var decrypted: [String: Any]?
        if let secured = payload["secu_params"] as? String, !secured.isEmpty,
           let text = KGLoginCrypto.aesParamsString(hex: secured, randomKey: randomKey),
           let data = text.data(using: .utf8) {
            decrypted = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }

        let userid = Song.intValue(decrypted?["userid"])
            ?? Song.intValue(payload["userid"])
            ?? 0
        guard userid > 0 else {
            throw KGError.server(serverMessage(root, fallback: "登录成功但没有拿到用户 ID"))
        }

        let token = (decrypted?["token"] as? String)
            ?? (payload["token"] as? String)
            ?? ""
        guard !token.isEmpty else {
            throw KGError.server("登录成功但没有拿到 token")
        }

        let vipToken = (decrypted?["vip_token"] as? String)
            ?? (payload["vip_token"] as? String)
            ?? (payload["vipToken"] as? String)

        return PhoneLoginResult(userid: userid, token: token, vipToken: vipToken)
    }

    private static func isValidPhone(_ phone: String) -> Bool {
        phone.range(of: "^1[3-9]\\d{9}$", options: .regularExpression) != nil
    }

    private static func extractToken(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        if text.contains("\\\"") {
            text = text.replacingOccurrences(of: "\\\"", with: "\"")
        }
        if text.hasPrefix("{"),
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = object["token"] as? String {
            return token
        }
        if text.hasPrefix("%7B") || text.contains("token%22") {
            let decoded = text.removingPercentEncoding ?? text
            return extractToken(decoded)
        }
        return text.isEmpty ? nil : text
    }

    private static func serverMessage(_ root: [String: Any], fallback: String) -> String {
        for key in ["error_msg", "msg", "message", "error", "data"] {
            if let value = root[key] as? String, !value.isEmpty { return value }
        }
        if let code = Song.intValue(root["error_code"]), code != 0 {
            switch code {
            case 20028: return "操作太频繁，请稍后再试"
            case 20006: return "验证码错误或已过期"
            case 20007: return "验证码已过期，请重新获取"
            case 20010: return "手机号格式不正确或暂不支持登录"
            case 20020: return "验证码已过期，请重新获取"
            default: return "\(fallback)（错误码 \(code)）"
            }
        }
        if let status = Song.intValue(root["status"]), status != 1 {
            return "\(fallback)（状态 \(status)）"
        }
        return fallback
    }
}
