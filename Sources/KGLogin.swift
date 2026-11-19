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
                "qrcode_txt": "https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=1005&",
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

    static func check(_ key: String) async throws -> (status: Int, token: String?, userid: Int?) {
        let data = try await KGApi.shared.webGet(
            path: "/v2/get_userinfo_qrcode",
            host: "https://login-user.kugou.com",
            params: [
                "plat": "4",
                "appid": "1001",
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
        return (status, payload["token"] as? String, Song.intValue(payload["userid"]))
    }
}
