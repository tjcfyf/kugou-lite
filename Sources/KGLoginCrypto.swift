import Foundation
import CommonCrypto

/// 酷狗概念版（appid 3116 / clientver 11440）手机号登录所需的加解密。
/// 参数来自 Android 概念版登录链路：
/// - params：AES-256-CBC/PKCS7，随机 16 位 key，key32 = md5(key)，IV = key32 后 16 位
/// - pk：RSA/ECB/NoPadding，明文补零到 128 字节
/// - t1/t2：概念版固定 AES key/iv
enum KGLoginCrypto {
    static let liteSalt = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
    static let t1Key = "5e4ef500e9597fe004bd09a46d8add98"
    static let t1IV = "04bd09a46d8add98"
    static let t2Key = "fd14b35e3f81af3817a20ae7adae7020"
    static let t2IV = "17a20ae7adae7020"
    /// t2 里夹的固定串，和客户端设备信息一起参与加密。
    static let t2DeviceSalt = "0f607264fc6318a92b9e13c65db7cd3c"

    static func randomKey() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<16).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func data(hex: String) -> Data? {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    /// AES-256-CBC/PKCS7，key 和 iv 都按 UTF-8 字节使用。
    static func aes(_ data: Data, key: String, iv: String, decrypt: Bool) -> Data? {
        let keyData = Data(key.utf8)
        let ivData = Data(iv.utf8)
        guard keyData.count == kCCKeySizeAES256, ivData.count == kCCBlockSizeAES128 else {
            return nil
        }

        let outputCapacity = data.count + kCCBlockSizeAES128
        var output = [UInt8](repeating: 0, count: outputCapacity)
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outBytes in
            keyData.withUnsafeBytes { keyBytes in
                ivData.withUnsafeBytes { ivBytes in
                    data.withUnsafeBytes { dataBytes in
                        CCCrypt(decrypt ? CCOperation(kCCDecrypt) : CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress,
                                keyData.count,
                                ivBytes.baseAddress,
                                dataBytes.baseAddress,
                                data.count,
                                outBytes.baseAddress,
                                outBytes.count,
                                &outputLength)
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        return Data(output.prefix(outputLength))
    }

    /// params 用随机 key 的 md5 作为 AES key，取后 16 位作为 IV。
    static func aesParams(_ data: Data, randomKey: String, decrypt: Bool) -> Data? {
        let key32 = KGSign.md5(randomKey)
        let iv = String(key32.suffix(16))
        return aes(data, key: key32, iv: iv, decrypt: decrypt)
    }

    static func aesParamsHex(_ json: String, randomKey: String) -> String? {
        guard let data = json.data(using: .utf8),
              let encrypted = aesParams(data, randomKey: randomKey, decrypt: false) else {
            return nil
        }
        return hex(encrypted)
    }

    static func aesParamsString(hex: String, randomKey: String) -> String? {
        guard let data = data(hex: hex),
              let decrypted = aesParams(data, randomKey: randomKey, decrypt: true) else {
            return nil
        }
        return String(data: decrypted, encoding: .utf8)
    }

    static func aesHex(_ text: String, key: String, iv: String) -> String? {
        guard let data = text.data(using: .utf8),
              let encrypted = aes(data, key: key, iv: iv, decrypt: false) else {
            return nil
        }
        return hex(encrypted)
    }

    /// `key` 参数：md5(appid + liteSalt + clientver + clienttime_ms)
    static func loginKey(clientTime: Int64) -> String {
        KGSign.md5("3116" + liteSalt + "11440" + String(clientTime))
    }

    /// 手机号掩码，和概念版客户端一致：前两位 + 五个星号 + 最后一位。
    static func maskedPhone(_ phone: String) -> String {
        guard phone.count >= 11 else { return phone }
        let first = String(phone.prefix(2))
        let last = String(phone.suffix(1))
        return first + "*****" + last
    }

    static func guid() -> String {
        if let saved = UserDefaults.standard.string(forKey: "kg.guid"), !saved.isEmpty {
            return saved
        }
        let generated = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(generated, forKey: "kg.guid")
        return generated
    }
}
