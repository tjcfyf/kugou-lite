import Foundation

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
