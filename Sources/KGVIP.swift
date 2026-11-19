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
/// 这里复刻同样的调用，每天只成功领一次；失败则下次播放再试。
enum KGVIP {
    private static let claimedKey = "kg.vip.claimedDate"

    static func claimIfNeeded() async -> VIPClaimResult {
        guard let token = KGApi.shared.token, !token.isEmpty, KGApi.shared.userid != 0 else {
            return .notLoggedIn
        }

        let today = dateKey()
        if UserDefaults.standard.string(forKey: claimedKey) == today { return .alreadyClaimed }

        // 概念版的领取前提是当天"听过歌"，所以先补一条听歌上报。
        _ = await reportListen()

        // 升级奖励要先有广告播放记录。
        _ = await adReport()

        // 概念版和标准版两套 appid 都试一遍，只要有一条成功就算领到。
        var received = false
        for lite in [true, false] {
            let reply = await receive(lite: lite)
            if reply.ok { received = true; break }
        }
        if !received {
            for appid in [3116, 1005] {
                let reply = await receiveH5(appid: appid)
                if reply.ok { received = true; break }
            }
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        // 升级奖励（失败不影响第一步的结果）
        _ = await upgrade(lite: true)

        if received {
            UserDefaults.standard.set(today, forKey: claimedKey)
            return .claimed
        }
        return .failed
    }

    /// 把几次领取请求的真实返回摊开，用于判断到底是哪一步被拒。
    static func probeReport() async -> String {
        guard KGApi.shared.token != nil, KGApi.shared.userid != 0 else { return "未登录" }

        var lines: [String] = []
        let today = dateKey()
        lines.append("日期 \(today) / uid \(KGApi.shared.userid)")

        let liteReply = await receive(lite: true)
        lines.append("① 概念版领取 " + liteReply.text)

        let stdReply = await receive(lite: false)
        lines.append("② 标准版领取 " + stdReply.text)

        let upgradeReply = await upgrade(lite: true)
        lines.append("③ 升级奖励 " + upgradeReply.text)

        let adReply = await adReport()
        lines.append("④ 广告上报 " + adReply.text)

        let h5Reply = await receiveH5(appid: 3116)
        lines.append("⑤ H5领取 " + h5Reply.text)

        let taskReply = await taskStatus()
        lines.append("⑥ 听歌任务 " + taskReply.text)

        return lines.joined(separator: "\n")
    }

    // MARK: - Steps

    private struct Reply {
        let ok: Bool
        let text: String
    }

    private static func receive(lite: Bool) async -> Reply {
        let data = try? await KGApi.shared.post(
            path: "/youth/v1/recharge/receive_vip_listen_song",
            params: ["source_id": "90139", "receive_day": dateKey()],
            contentType: "application/x-www-form-urlencoded",
            lite: lite
        )
        return parse(data, prefix: lite ? "lite" : "std")
    }

    private static func upgrade(lite: Bool) async -> Reply {
        let data = try? await KGApi.shared.post(
            path: "/youth/v1/listen_song/upgrade_vip_reward",
            params: ["kugouid": "\(KGApi.shared.userid)", "ad_type": "1"],
            contentType: "application/x-www-form-urlencoded",
            lite: lite
        )
        return parse(data, prefix: lite ? "lite" : "std")
    }

    private static func adReport() async -> Reply {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let data = try? await KGApi.shared.post(
            path: "/youth/v1/ad/play_report",
            params: [:],
            body: [
                "ad_id": 12307537187,
                "play_start": now - 30000,
                "play_end": now,
            ],
            lite: true
        )
        return parse(data, prefix: "lite")
    }

    /// H5 活动页签名（web salt）的领取方式，酷狗的概念版签到页走这套。
    private static func receiveH5(appid: Int) async -> Reply {
        let params = h5Params(appid: appid, extra: [
            "source_id": "90139",
            "receive_day": dateKey(),
        ])
        let data = try? await KGApi.shared.webPost(
            path: "/youth/v1/recharge/receive_vip_listen_song",
            params: params
        )
        return parse(data, prefix: "h5-\(appid)")
    }

    private static func taskStatus() async -> Reply {
        let params = h5Params(appid: 3116, extra: [:])
        let data = try? await KGApi.shared.webGet(
            path: "/youth/v1/activity/get_listen_song_task",
            host: "https://gateway.kugou.com",
            params: params
        )
        return parse(data, prefix: "task")
    }

    private static func h5Params(appid: Int, extra: [String: String]) -> [String: String] {
        var params: [String: String] = [
            "appid": "\(appid)",
            "clientver": appid == 3116 ? "11440" : "20489",
            "mid": KGApi.shared.mid,
            "dfid": KGApi.shared.dfid,
            "uuid": "-",
            "srcappid": "2919",
            "clienttime": "\(Int(Date().timeIntervalSince1970))",
        ]
        if let token = KGApi.shared.token { params["token"] = token }
        if KGApi.shared.userid != 0 { params["userid"] = "\(KGApi.shared.userid)" }
        extra.forEach { params[$0.key] = $0.value }
        return params
    }

    /// 听歌上报，概念版用它把"今日已听"记到任务进度里。
    private static func reportListen() async -> Reply {
        let data = try? await KGApi.shared.post(
            path: "/youth/v2/report/listen_song",
            params: ["clientver": "10566"],
            body: ["mixsongid": KGApi.shared.lastMixSongID > 0 ? KGApi.shared.lastMixSongID : 666075191],
            lite: true
        )
        return parse(data, prefix: "listen")
    }

    // MARK: - Parsing

    private static func parse(_ data: Data?, prefix: String) -> Reply {
        guard let data = data else { return Reply(ok: false, text: "\(prefix) 无响应") }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data.prefix(160), encoding: .utf8) ?? ""
            return Reply(ok: false, text: "\(prefix) 非 JSON：\(raw)")
        }

        let status = Song.intValue(root["status"]) ?? -1
        let errcode = Song.intValue(root["errcode"]) ?? 0
        let errorCode = Song.intValue(root["error_code"]) ?? 0
        let message = (root["error_msg"] as? String)
            ?? (root["errmsg"] as? String)
            ?? (root["message"] as? String)
            ?? (root["error"] as? String)
            ?? ""

        // 成功判定：status == 1，或 errcode == 0 且带了明确成功文案
        var ok = status == 1 && errcode == 0
        if errorCode == 131001 { ok = true }
        if !ok, errcode == 0, errorCode == 0, message.contains("成功") { ok = true }

        var text = "\(prefix) status=\(status) errcode=\(errcode) error_code=\(errorCode)"
        if !message.isEmpty { text += " msg=\(message)" }
        if !ok {
            let raw = String(data: data.prefix(200), encoding: .utf8) ?? ""
            text += " | \(raw)"
        }
        return Reply(ok: ok, text: text)
    }

    static func dateKey() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
