import Foundation
import Security

/// 酷狗用户资料接口的 RSA-PKCS1 公钥加密。
/// iOS 没有直接暴露 BigInt，但 Security 的 SecKey API 可以完成 PKCS#1 v1.5。
enum KGRSA {
    enum Key {
        /// 概念版（appid 3116）公钥
        case lite
        /// 标准版（appid 1005）公钥
        case standard

        var modulusBase64URL: String {
            switch self {
            case .lite:
                return "xAotDadlEfO7HMK706-9i-qDtNawW2wT64kgxT8a92ebMroNDtuEMkDvG4Nu_tPuJAc0wUwTmf1llNFq8i9SUl0U1y4BVcbcyGONT3u5TzoLH0wp-ZGXLyoWCiXrCp5yQza-f2m70xn_qxxt2EcLAh3ENPP6uon0oqAbM7290Is"
            case .standard:
                return "yABu0DhC0mKCCb0xSYTKXtbP4G4wyV-dRwTZxJeR16k1upUOywvI6_X1mU8LrJJ6frFRs8HeNDMD-lOcgxNuzP19flEeLbzhjqqfeEybUNRD51hll54KXiFuRsaEBmqNa5mFgLuqItc_V5Aoa7FHQugyRORNttcH_-FixccALUU"
            }
        }
    }

    private static var keyCache: [String: SecKey] = [:]

    /// 返回大写 HEX 的 RSA-PKCS1 密文。
    static func encryptPKCS1(_ plaintext: Data, key: Key) -> String? {
        guard let publicKey = publicKey(for: key),
              let encrypted = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionPKCS1, plaintext as CFData, nil) else {
            return nil
        }
        return (encrypted as Data).map { String(format: "%02X", $0) }.joined()
    }

    /// 登录接口的 `pk` 字段用的是 RSA/ECB/NoPadding：明文补零到 128 字节，
    /// 再直接做模幂。SecKeyCreateEncryptedData 不支持 raw，改用 SecKeyEncrypt(.None)。
    static func encryptRawNoPadding(_ plaintext: Data, key: Key) -> String? {
        guard let publicKey = publicKey(for: key) else { return nil }
        let blockSize = SecKeyGetBlockSize(publicKey)
        var block = [UInt8](repeating: 0, count: blockSize)
        let prefix = [UInt8](plaintext.prefix(blockSize))
        block.replaceSubrange(0..<prefix.count, with: prefix)

        var cipher = [UInt8](repeating: 0, count: blockSize)
        var cipherLength = blockSize
        let status = block.withUnsafeBufferPointer { pointer in
            SecKeyEncrypt(publicKey,
                          SecPadding(rawValue: 0),
                          pointer.baseAddress!,
                          block.count,
                          &cipher,
                          &cipherLength)
        }
        guard status == errSecSuccess, cipherLength > 0 else { return nil }
        return cipher.prefix(cipherLength).map { String(format: "%02X", $0) }.joined()
    }

    private static func publicKey(for key: Key) -> SecKey? {
        let cacheKey = key.modulusBase64URL
        if let cached = keyCache[cacheKey] { return cached }
        guard let modulus = Data(base64URLEncoded: key.modulusBase64URL) else { return nil }
        let modulusDER = derInteger(modulus)
        let exponentDER = Data([0x02, 0x03, 0x01, 0x00, 0x01])
        var der = Data([0x30])
        der.append(lengthBytes(modulusDER.count + exponentDER.count))
        der.append(modulusDER)
        der.append(exponentDER)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ]
        guard let secKey = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil) else { return nil }
        keyCache[cacheKey] = secKey
        return secKey
    }

    private static func derInteger(_ bytes: Data) -> Data {
        var content = bytes
        if content.first == nil || content.first! >= 0x80 {
            content.insert(0, at: 0)
        }
        var out = Data([0x02])
        out.append(lengthBytes(content.count))
        out.append(content)
        return out
    }

    private static func lengthBytes(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        var value = length
        var parts: [UInt8] = []
        while value > 0 {
            parts.insert(UInt8(value & 0xff), at: 0)
            value >>= 8
        }
        return Data([0x80 | UInt8(parts.count)] + parts)
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var value = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = value.count % 4
        if padding > 0 { value += String(repeating: "=", count: 4 - padding) }
        self.init(base64Encoded: value)
    }
}
