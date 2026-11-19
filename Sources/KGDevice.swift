import Foundation
import CommonCrypto
import Security

/// 酷狗设备注册：没有服务端签发的 dfid，取流接口一律返回「本次请求需要验证」。
/// 协议来自概念版客户端：AES 加密设备信息 + RSA 加密密钥，再拿回 dfid。
enum KGDevice {
    private static let registeredKey = "kg.dfid.registered"
    private static var lastAttempt: TimeInterval = 0

    static var isRegistered: Bool {
        UserDefaults.standard.bool(forKey: registeredKey) && KGApi.shared.dfid.count > 20
    }

    static func registerIfNeeded() async -> String {
        if isRegistered { return "已注册" }
        if Date().timeIntervalSince1970 - lastAttempt < 600 { return "刚刚试过，稍后再试" }
        lastAttempt = Date().timeIntervalSince1970
        return await register()
    }

    static func register() async -> String {
        let guid = UserDefaults.standard.string(forKey: "kg.guid") ?? {
            let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            UserDefaults.standard.set(value, forKey: "kg.guid")
            return value
        }()

        // 1) 设备信息 JSON
        let device: [String: Any] = [
            "availableRamSize": 4_983_533_568,
            "availableRomSize": 48_114_719,
            "availableSDSize": 48_114_717,
            "basebandVer": "",
            "batteryLevel": 100,
            "batteryStatus": 3,
            "brand": "Apple",
            "buildSerial": "unknown",
            "device": "iPhone13,2",
            "imei": guid,
            "imsi": "",
            "manufacturer": "Apple",
            "uuid": guid,
            "accelerometer": false, "accelerometerValue": "",
            "gravity": false, "gravityValue": "",
            "gyroscope": false, "gyroscopeValue": "",
            "light": false, "lightValue": "",
            "magnetic": false, "magneticValue": "",
            "orientation": false, "orientationValue": "",
            "pressure": false, "pressureValue": "",
            "step_counter": false, "step_counterValue": "",
            "temperature": false, "temperatureValue": "",
        ]
        guard let plain = try? JSONSerialization.data(withJSONObject: device) else {
            return "设备信息组装失败"
        }

        // 2) AES：key = md5(nonce).前16位，iv = 后16位
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let nonce = String((0..<6).map { _ in alphabet.randomElement()! })
        let digest = KGSign.md5(nonce)
        let keyString = String(digest.prefix(16))
        let ivString = String(digest.dropFirst(16).prefix(16))
        guard let cipher = aesCBC(plain, key: keyString, iv: ivString, encrypt: true) else {
            return "AES 加密失败"
        }
        let cipherBase64 = cipher.base64EncodedString()

        // 3) RSA 加密 {aes, uid, token}
        let payload: [String: Any] = [
            "aes": nonce,
            "uid": KGApi.shared.userid,
            "token": KGApi.shared.token ?? "",
        ]
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let hex = rsaEncrypt(payloadData) else {
            return "RSA 加密失败"
        }

        // 4) 发送
        let params = [
            "part": "1",
            "platid": "1",
            "p": hex,
        ]
        guard let bodyData = try? await postRegister(params: params, body: cipherBase64) else {
            return "设备注册请求失败"
        }

        // 5) 解密响应，取 dfid
        guard let json = aesDecryptToJSON(bodyData, key: keyString, iv: ivString) else {
            return "注册响应解密失败"
        }
        if let dfid = json["dfid"] as? String, !dfid.isEmpty {
            return save(dfid)
        }
        if let data = json["data"] as? [String: Any], let dfid = data["dfid"] as? String, !dfid.isEmpty {
            return save(dfid)
        }
        let raw = String(data: bodyData.prefix(120), encoding: .utf8) ?? ""
        return "注册未返回 dfid（\(raw)）"
    }

    private static func save(_ dfid: String) -> String {
        KGApi.shared.dfid = dfid
        UserDefaults.standard.set(dfid, forKey: "kg.dfid")
        UserDefaults.standard.set(true, forKey: registeredKey)
        return "注册成功 \(dfid.prefix(6))…"
    }

    // MARK: - 请求

    private static func postRegister(params: [String: String], body: String) async throws -> Data {
        var all = params
        all["dfid"] = KGApi.shared.dfid
        all["mid"] = KGApi.shared.mid
        all["uuid"] = "-"
        all["appid"] = "3116"
        all["clientver"] = "11440"
        all["clienttime"] = "\(Int(Date().timeIntervalSince1970))"
        if let token = KGApi.shared.token { all["token"] = token }
        if KGApi.shared.userid != 0 { all["userid"] = "\(KGApi.shared.userid)" }
        all["signature"] = KGSign.sign(params: all, salt: KGSign.liteSalt, data: body)

        var components = URLComponents(string: "https://userservice.kugou.com/risk/v3/r_register_dev")!
        components.queryItems = all.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi", forHTTPHeaderField: "User-Agent")
        request.setValue(KGApi.shared.dfid, forHTTPHeaderField: "dfid")
        request.setValue(KGApi.shared.mid, forHTTPHeaderField: "mid")
        request.setValue(all["clienttime"], forHTTPHeaderField: "clienttime")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw KGError.network
        }
        return data
    }

    // MARK: - 加密

    private static func aesCBC(_ data: Data, key: String, iv: String, encrypt: Bool) -> Data? {
        guard key.count == 16, iv.count == 16 else { return nil }
        let keyData = Data(key.utf8)
        let ivData = Data(iv.utf8)
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { inBytes in
                keyData.withUnsafeBytes { keyBytes in
                    ivData.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, keyData.count,
                            ivBytes.baseAddress,
                            inBytes.baseAddress, data.count,
                            outBytes.baseAddress, out.count,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return Data(out.prefix(moved))
    }

    private static func aesDecryptToJSON(_ data: Data, key: String, iv: String) -> [String: Any]? {
        // 服务端可能返回 JSON（含 base64 密文）或裸 base64
        var base64 = String(data: data, encoding: .utf8) ?? ""
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let str = json["data"] as? String {
                base64 = str
            } else {
                return json
            }
        }
        base64 = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cipher = Data(base64Encoded: base64),
              let plain = aesCBC(cipher, key: key, iv: iv, encrypt: false),
              let json = try? JSONSerialization.jsonObject(with: plain) as? [String: Any] else {
            return nil
        }
        return json
    }

    // MARK: - RSA

    private static let litePublicKey = """
    MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDECi0Np2UR87scwrvTr72L6oO01rBbbBPriSDFPxr3Z5syug0O24QyQO8bg27+0+4kBzTBTBOZ/WWU0WryL1JSXRTXLgFVxtzIY41Pe7lPOgsfTCn5kZcvKhYKJesKnnJDNr5/abvTGf+rHG3YRwsCHcQ08/q6ifSioBszvb3QiwIDAQAB
    """

    private static func rsaEncrypt(_ data: Data) -> String? {
        guard let der = Data(base64Encoded: litePublicKey.replacingOccurrences(of: "\n", with: "")),
              let pkcs1 = pkcs1FromSPKI(der) else { return nil }

        var error: Unmanaged<CFError>?
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 1024,
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) else {
            return nil
        }
        guard let cipher = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, data as CFData, &error) as Data? else {
            return nil
        }
        return cipher.map { String(format: "%02x", $0) }.joined()
    }

    /// 把 SubjectPublicKeyInfo 剥成 PKCS#1 RSAPublicKey。
    private static func pkcs1FromSPKI(_ der: Data) -> Data? {
        var index = der.startIndex
        guard der[index] == 0x30 else { return nil }
        index += 1
        guard skipLength(der, &index) else { return nil }
        // 算法标识 SEQUENCE
        guard index < der.endIndex, der[index] == 0x30 else { return nil }
        index += 1
        guard skipLength(der, &index) else { return nil }
        // 跳过 OID 和 NULL
        while index < der.endIndex, der[index] != 0x03 {
            index += 1
        }
        guard index < der.endIndex, der[index] == 0x03 else { return nil }
        index += 1
        guard skipLength(der, &index) else { return nil }
        // BIT STRING 首字节是 unused bits
        guard index < der.endIndex, der[index] == 0x00 else { return nil }
        index += 1
        return der.subdata(in: index..<der.endIndex)
    }

    private static func skipLength(_ der: Data, _ index: inout Data.Index) -> Bool {
        guard index < der.endIndex else { return false }
        let first = der[index]
        index += 1
        if first & 0x80 == 0 { return true }
        let count = Int(first & 0x7F)
        guard count > 0, index + count <= der.endIndex else { return false }
        index += count
        return true
    }
}
