import Foundation

enum VIPClaimResult {
    case claimed
    case alreadyClaimed
    case failed
    case notLoggedIn
}

/// 酷狗概念版的「听歌领会员」。
///
/// 概念版客户端在每次播放前会上报一次听歌行为，服务端据此发放当日会员。
/// 这里复刻同样的两次调用，每天只成功领一次；失败则下次播放再试。
enum KGVIP {
    private static let claimedKey = "kg.vip.claimedDate"

    static func claimIfNeeded() async -> VIPClaimResult {
        guard let token = KGApi.shared.token, !token.isEmpty, KGApi.shared.userid != 0 else {
            return .notLoggedIn
        }

        let today = dateKey()
        if UserDefaults.standard.string(forKey: claimedKey) == today { return .alreadyClaimed }

        // 1) 领取当天的听歌奖励
        let receive = try? await KGApi.shared.post(
            path: "/youth/v1/recharge/receive_vip_listen_song",
            params: ["source_id": "90139", "receive_day": today],
            contentType: "application/x-www-form-urlencoded",
            lite: true
        )
        let received = isOK(receive)

        try? await Task.sleep(nanoseconds: 500_000_000)

        // 2) 领取升级奖励（失败不影响第一步的结果）
        _ = try? await KGApi.shared.post(
            path: "/youth/v1/listen_song/upgrade_vip_reward",
            params: ["kugouid": "\(KGApi.shared.userid)", "ad_type": "1"],
            contentType: "application/x-www-form-urlencoded",
            lite: true
        )

        if received {
            UserDefaults.standard.set(today, forKey: claimedKey)
            return .claimed
        }
        return .failed
    }

    static func dateKey() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func isOK(_ data: Data?) -> Bool {
        guard let data = data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let status = Song.intValue(root["status"]), status == 1 { return true }
        return false
    }
}
