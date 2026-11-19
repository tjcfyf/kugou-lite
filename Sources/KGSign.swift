import Foundation
import CryptoKit

/// 酷狗网关的签名算法。
///
/// Android 端签名 = MD5(salt + 按 key 排序的 k=v 串 + body + salt)。
enum KGSign {
    static let androidSalt = "OIlwieks28dk2k092lksi2UIkp"
    static let webSalt = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt"
    /// 概念版（lite）签名盐。
    static let liteSalt = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
    /// 获取播放地址时给 `key` 参数用的盐（标准版）。
    static let playKeySalt = "57ae12eb6890223e355ccfcb74edf70d"
    /// 概念版（lite）的 key 盐，和标准版不是一个。
    static let litePlayKeySalt = "185672dd44712f60bb1736df5a377e82"

    static func md5(_ text: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func android(params: [String: String], data: String = "") -> String {
        sign(params: params, salt: androidSalt, data: data)
    }

    static func sign(params: [String: String], salt: String, data: String = "") -> String {
        let body = params.keys.sorted().map { key in
            "\(key)=\(params[key] ?? "")"
        }.joined()
        return md5(salt + body + data + salt)
    }

    static func web(params: [String: String], data: String = "") -> String {
        let body = params.keys.sorted().map { key in
            "\(key)=\(params[key] ?? "")"
        }.joined()
        return md5(webSalt + body + data + webSalt)
    }

    static func playKey(hash: String, mid: String, userid: Int, appid: Int, lite: Bool = false) -> String {
        md5(hash.lowercased() + (lite ? litePlayKeySalt : playKeySalt) + "\(appid)" + mid + "\(userid)")
    }
}
