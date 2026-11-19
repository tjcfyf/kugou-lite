import Foundation

enum KGUser {
    /// 查询概念版会员状态，用来确认 token 是否生效、会员有没有到账。
    static func vipText() async -> String? {
        guard KGApi.shared.token != nil, KGApi.shared.userid != 0 else { return nil }
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

        if let list = root["data"] as? [[String: Any]] {
            for item in list {
                let isVip = Song.intValue(item["is_vip"]) ?? 0
                guard isVip == 1 else { continue }
                let type = (item["product_type"] as? String) ?? "vip"
                let end = (item["vip_end_time"] as? String) ?? ""
                return "\(type.uppercased()) 有效期至 \(end)"
            }
            return "未检测到有效会员"
        }

        if let message = root["error"] as? String, !message.isEmpty {
            return "查询失败：\(message)"
        }
        return "未检测到有效会员"
    }
}
