import Foundation

struct KugouProfile: Equatable {
    let nickname: String
    let avatarURL: String?
    let signature: String?
}

enum KGUser {
    /// 查询概念版会员状态，用来确认 token 是否生效、会员有没有到账。
    private static func describe(type: String, end: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: end) {
            if date > Date() {
                return "\(type.uppercased()) 有效期至 \(end)"
            }
            formatter.dateFormat = "yyyy-MM-dd"
            return "今日畅听权益已生效（旧豪华VIP记录到期 \(formatter.string(from: date))，不影响听歌）"
        }
        return "\(type.uppercased()) 有效期至 \(end)"
    }

    /// 概念版畅听 VIP 走批量接口，get_union_vip 里的日期是旧的豪华 VIP 记录。
    private static func conceptVipText() async -> String? {
        let body: [String: Any] = [
            "get_type": "2",
            "busi_type": "concept",
            "useridlist": [KGApi.shared.userid],
            "clientappid": "3116",
            "kugouid": "\(KGApi.shared.userid)",
            "clienttoken": KGApi.shared.token ?? "",
        ]
        guard let data = try? await KGApi.shared.post(
            path: "/v2/batch_union_vipinfo",
            host: "https://kugouvip.kugou.com",
            params: [:],
            body: body,
            contentType: "application/json; charset=utf-8",
            lite: true
        ), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var best: Date?
        var type = "畅听VIP"
        walk(root) { dict in
            if let product = dict["product_type"] as? String, !product.isEmpty {
                type = product.uppercased()
            }
            for key in ["vip_end_time", "m_y_endtime", "vip_y_endtime", "end_time"] {
                guard let raw = dict[key] as? String, let date = parse(raw) else { continue }
                if best == nil || date > best! { best = date }
            }
        }
        guard let end = best else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        if end > Date() {
            return "\(type) 有效期至 \(formatter.string(from: end))"
        }
        return nil
    }

    private static func walk(_ value: Any, visit: ([String: Any]) -> Void) {
        if let dict = value as? [String: Any] {
            visit(dict)
            dict.values.forEach { walk($0, visit: visit) }
        } else if let list = value as? [Any] {
            list.forEach { walk($0, visit: visit) }
        }
    }

    private static func parse(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: raw) { return date }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    /// 当前登录用户的昵称、头像、签名。先用概念版 appid，失败再试标准版。
    static func profile() async -> KugouProfile? {
        guard let token = KGApi.shared.token, !token.isEmpty, KGApi.shared.userid != 0 else {
            return nil
        }
        if let profile = await fetchProfile(lite: true, token: token) { return profile }
        if let profile = await fetchProfile(lite: false, token: token) { return profile }
        // 资料接口的 RSA 参数偶尔被风控，退一步从云歌单列表里取当前账号的昵称/头像。
        return await KGService.profileFromPlaylists()
    }

    private static func fetchProfile(lite: Bool, token: String) async -> KugouProfile? {
        let appid = lite ? 3116 : 1005
        let clientver = lite ? 11440 : 20489
        let clienttime = Int(Date().timeIntervalSince1970 * 1000)
        guard let plain = try? JSONSerialization.data(withJSONObject: [
            "clienttime": clienttime,
            "token": token
        ]) else { return nil }
        guard let p = KGRSA.encryptPKCS1(plain, key: lite ? .lite : .standard) else { return nil }
        let salt = lite ? KGSign.liteSalt : KGSign.androidSalt
        let key = KGSign.md5("\(appid)\(salt)\(clientver)\(clienttime)")
        let body: [String: Any] = [
            "p": p,
            "appid": appid,
            "mid": KGApi.shared.mid,
            "clientver": clientver,
            "source": 0,
            "clienttime": clienttime,
            "uuid": "-",
            "userid": KGApi.shared.userid,
            "key": key
        ]
        guard let data = try? await KGApi.shared.post(
            path: "/v1/get_my_userinfo",
            host: "http://relation.user.kugou.com",
            params: [:],
            body: body,
            contentType: "application/json",
            headers: ["Host": "relation.user.kugou.com"],
            lite: lite
        ), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Song.intValue(root["status"]) == 1,
              let payload = root["data"] as? [String: Any] else {
            return nil
        }
        let nickname = (payload["nickname"] as? String)
            ?? (payload["user_name"] as? String)
            ?? (payload["username"] as? String)
            ?? ""
        var avatar = (payload["pic"] as? String)
            ?? (payload["avatar"] as? String)
            ?? (payload["photo"] as? String)
        if let value = avatar, value.hasPrefix("http://") {
            avatar = "https://" + String(value.dropFirst("http://".count))
        }
        let signature = (payload["signature"] as? String) ?? (payload["memo"] as? String)
        guard !nickname.isEmpty || avatar != nil else { return nil }
        return KugouProfile(nickname: nickname, avatarURL: avatar, signature: signature)
    }

    /// 会员接口的原文，面板里用来判断是不是解析问题。
    static func rawVip() async -> String {
        guard let data = try? await KGApi.shared.get(
            path: "/v1/get_union_vip",
            host: "https://kugouvip.kugou.com",
            params: [
                "busi_type": "concept",
                "opt_product_types": "dvip,qvip",
                "product_type": "svip",
            ],
            lite: true
        ) else { return "请求失败" }
        let raw = String(data: data.prefix(300), encoding: .utf8) ?? ""
        return raw
    }

    static func vipText() async -> String? {
        guard KGApi.shared.token != nil, KGApi.shared.userid != 0 else { return nil }

        if let concept = await conceptVipText() { return concept }
        if let end = KGVIP.adFreeEndTime, end > Date() {
            return "畅听权益至 \(KGVIP.shortTime(end))（广告奖励）"
        }
        guard let data = try? await KGApi.shared.get(
            path: "/v1/get_union_vip",
            host: "https://kugouvip.kugou.com",
            params: [
                "busi_type": "concept",
                "opt_product_types": "dvip,qvip",
                "product_type": "svip",
            ],
            lite: true
        ) else {
            return "会员状态查询失败"
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "会员状态解析失败"
        }

        if let single = root["data"] as? [String: Any] {
            let isVip = Song.intValue(single["is_vip"]) ?? 0
            if isVip == 1 {
                let type = (single["product_type"] as? String) ?? "vip"
                let end = (single["vip_end_time"] as? String) ?? ""
                return describe(type: type, end: end)
            }
            if let list = single["list"] as? [[String: Any]], !list.isEmpty {
                for item in list {
                    let v = Song.intValue(item["is_vip"]) ?? 0
                    if v == 1 {
                        let type = (item["product_type"] as? String) ?? "vip"
                        let end = (item["vip_end_time"] as? String) ?? ""
                        return describe(type: type, end: end)
                    }
                }
            }
            return "未检测到有效会员"
        }

        if let list = root["data"] as? [[String: Any]] {
            for item in list {
                let isVip = Song.intValue(item["is_vip"]) ?? 0
                guard isVip == 1 else { continue }
                let type = (item["product_type"] as? String) ?? "vip"
                let end = (item["vip_end_time"] as? String) ?? ""
                return describe(type: type, end: end)
            }
            return "未检测到有效会员"
        }

        if let message = root["error"] as? String, !message.isEmpty {
            return "查询失败：\(message)"
        }
        return "未检测到有效会员"
    }
}
