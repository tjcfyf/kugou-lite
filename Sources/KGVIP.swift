import Foundation

enum VIPClaimResult {
    case claimed
    case alreadyClaimed
    case failed
    case notLoggedIn
}

/// 酷狗概念版 5.2.9 的播放页广告领 VIP。
///
/// 真实客户端在播放页广告关闭后调用：
/// `POST /youth/v1/recharge/receive_vip_listen_song?source_id=90154`
/// 不传 `receive_day`，服务端按当天计算，返回 `data.ad_vip_num`
/// （本次发放的小时数）和 `data.ad_vip_end_time`（权益结束时间）。
/// 旧的 `source_id=90139` 是每日签到任务，返回 131001 只代表签到已做，
/// 并不发放会员；`upgrade_vip_reward` 也不是 5.2.9 的领取接口。
enum KGVIP {
    private static let adFreeEndKey = "kg.vip.adFreeEndTime"
    private static let lastAttemptKey = "kg.vip.lastAttempt"
    private static let legacyClaimedKey = "kg.vip.claimedDate"

    private static let adRewardSource = 90154
    private static let dailyCheckInSource = 90139

    private(set) static var lastMessage = ""

    /// 本地记录的广告畅听结束时间。
    static var adFreeEndTime: Date? {
        let value = UserDefaults.standard.double(forKey: adFreeEndKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value / 1000)
    }

    static var adFreeActive: Bool {
        guard let end = adFreeEndTime else { return false }
        return end > Date()
    }

    static func claimIfNeeded() async -> VIPClaimResult {
        guard let token = KGApi.shared.token, !token.isEmpty, KGApi.shared.userid != 0 else {
            return .notLoggedIn
        }

        let defaults = UserDefaults.standard
        // 清掉旧版本把 131001 当成功后写入的日期，否则今天会一直被挡住。
        if defaults.string(forKey: legacyClaimedKey) != nil {
            defaults.removeObject(forKey: legacyClaimedKey)
        }

        if let end = adFreeEndTime, end.timeIntervalSinceNow > 3600 {
            lastMessage = "畅听权益有效至 \(shortTime(end))"
            return .alreadyClaimed
        }

        if let last = defaults.object(forKey: lastAttemptKey) as? Date,
           Date().timeIntervalSince(last) < 60 {
            return .alreadyClaimed
        }
        defaults.set(Date(), forKey: lastAttemptKey)

        // 听歌上报只为把当前歌曲记进任务；没有当前歌曲时不要用假 ID。
        if KGApi.shared.lastMixSongID > 0 {
            _ = await reportListen(mixsongID: KGApi.shared.lastMixSongID)
        }

        // 先补广告播放记录，再走真实播放页广告奖励。
        _ = await adReportV2()
        _ = await adReport()

        // 真实播放页广告奖励；失败后按客户端另外两条兜底路径尝试。
        let sources: [Int?] = [adRewardSource, nil, dailyCheckInSource]
        var lastFailure: Reward?

        for source in sources {
            let reward = await receive(sourceId: source)
            if reward.ok {
                store(reward)
                let hours = reward.hours > 0 ? "\(reward.hours) 小时" : "畅听"
                lastMessage = reward.endTime.map { "已领取 \(hours)，有效期至 \(shortTime($0))" }
                    ?? "已领取 \(hours) 畅听权益"
                return .claimed
            }
            if reward.errorCode == 51002 || reward.errorCode == 20018 || reward.errorCode == 20010 {
                lastMessage = "登录已失效，请重新登录"
                return .notLoggedIn
            }
            lastFailure = reward
        }

        lastMessage = lastFailure?.displayMessage ?? "今日会员领取失败，下次播放会再试"
        return .failed
    }

    /// 把真实请求的返回摊开，便于判断是哪一条链路被拒。
    static func probeReport() async -> String {
        guard KGApi.shared.token != nil, KGApi.shared.userid != 0 else { return "未登录" }

        var lines: [String] = []
        lines.append("日期 \(dateKey()) / uid \(KGApi.shared.userid)")
        lines.append("本地畅听 " + (adFreeEndTime.map { "有效至 \(shortTime($0))" } ?? "无记录"))

        let adReward = await receive(sourceId: adRewardSource)
        if adReward.ok { store(adReward) }
        lines.append("① 播放页广告奖励 source=90154 " + adReward.text)

        let directReward = await receive(sourceId: nil)
        if directReward.ok { store(directReward) }
        lines.append("② 直接广告奖励 source=0 " + directReward.text)

        let checkIn = await receive(sourceId: dailyCheckInSource)
        if checkIn.ok { store(checkIn) }
        lines.append("③ 每日签到 source=90139 " + checkIn.text)

        let listen = KGApi.shared.lastMixSongID > 0
            ? await reportListen(mixsongID: KGApi.shared.lastMixSongID)
            : Reply(ok: false, text: "listen 当前没有歌曲，跳过")
        lines.append("④ 听歌上报 " + listen.text)

        let task = await taskStatus()
        lines.append("⑤ 听歌任务 " + task.text)

        let adReply = await adReport()
        lines.append("⑥ 广告上报 v1 " + adReply.text)

        let adV2Reply = await adReportV2()
        lines.append("⑦ 广告上报 v2 " + adV2Reply.text)

        let vipRaw = await KGUser.rawVip()
        lines.append("⑧ 会员原文 " + vipRaw)

        let deviceReply = await KGDevice.register()
        lines.append("⑨ 设备注册 " + deviceReply)

        let testHash = "B3A52A7A958BF0AED0EBFBA2E9A818B7"
        let testAudioID = 32100650
        let authProbe = await KGService.authProbe(hash: testHash, albumAudioID: testAudioID)
        lines.append("⑩ 授权链路 " + authProbe)

        let privilege = await KGService.privilegeProbe(hash: testHash)
        lines.append("⑪ 权益 " + privilege)

        let stream = await KGService.streamProbe(hash: testHash, albumAudioID: testAudioID)
        lines.append("⑫ 取流 " + stream)

        return lines.joined(separator: "\n")
    }

    // MARK: - Steps

    private struct Reward {
        let ok: Bool
        let status: Int
        let errorCode: Int
        let hours: Int
        let endTime: Date?
        let serverTime: Date?
        let message: String
        let raw: String

        var text: String {
            var value = "status=\(status) error_code=\(errorCode)"
            if hours > 0 { value += " ad_vip_num=\(hours)" }
            if let endTime = endTime { value += " ad_vip_end=\(KGVIP.shortTime(endTime))" }
            if !message.isEmpty { value += " msg=\(message)" }
            if !ok, !raw.isEmpty { value += " | \(raw)" }
            return value
        }

        var displayMessage: String {
            if errorCode == 131001 || errorCode == 130012 { return "今天已经领取过了" }
            if errorCode == 130011 { return "还没有听歌记录，听一首歌后再试" }
            if !message.isEmpty { return message }
            if errorCode != 0 { return "领取失败（错误码 \(errorCode)）" }
            return "今日会员领取失败，下次播放会再试"
        }
    }

    private struct Reply {
        let ok: Bool
        let text: String
    }

    private static func receive(sourceId: Int?) async -> Reward {
        // 5.2.9 概念版当前版本号；新广告奖励在低版本 clientver 下会被旧活动逻辑拦截。
        var params: [String: String] = ["clientver": "11590"]
        if let sourceId = sourceId, sourceId > 0 {
            params["source_id"] = "\(sourceId)"
        }
        let data = try? await KGApi.shared.post(
            path: "/youth/v1/recharge/receive_vip_listen_song",
            params: params,
            contentType: "application/x-www-form-urlencoded",
            lite: true
        )
        return parseReward(data, label: "source=\(sourceId.map { String($0) } ?? "0")")
    }

    /// 概念版 5.2.9 的播放页广告上报格式（v2）。
    /// `is_gradient=1` 走 query，广告信息放在 JSON body 里。
    private static func adReportV2() async -> Reply {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let data = try? await KGApi.shared.post(
            path: "/youth/v2/ad/play_report",
            params: ["is_gradient": "1", "clientver": "11590"],
            body: [
                "ad_id": "12307537187",
                "play_start": now - 30000,
                "play_end": now,
                "has_download": 0,
            ],
            lite: true
        )
        return parseReply(data, prefix: "ad-v2")
    }

    private static func adReport() async -> Reply {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let data = try? await KGApi.shared.post(
            path: "/youth/v1/ad/play_report",
            params: ["clientver": "11590"],
            body: [
                "ad_id": 12307537187,
                "play_start": now - 30000,
                "play_end": now,
            ],
            lite: true
        )
        return parseReply(data, prefix: "ad")
    }

    private static func taskStatus() async -> Reply {
        let params = h5Params(appid: 3116, extra: [:])
        let data = try? await KGApi.shared.webGet(
            path: "/youth/v1/activity/get_listen_song_task",
            host: "https://gateway.kugou.com",
            params: params
        )
        return parseReply(data, prefix: "task")
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

    /// 听歌上报使用客户端专用 UA，通用 Discovery UA 不会被任务系统计入。
    private static func reportListen(mixsongID: Int) async -> Reply {
        let data = try? await KGApi.shared.post(
            path: "/youth/v2/report/listen_song",
            params: ["clientver": "10566"],
            body: ["mixsongid": mixsongID],
            headers: ["User-Agent": "Android13-1070-10566-201-0-ReportPlaySongToServerProtocol-wifi"],
            lite: true
        )
        return parseReply(data, prefix: "listen")
    }

    // MARK: - Parsing

    private static func parseReward(_ data: Data?, label: String) -> Reward {
        guard let data = data else {
            return Reward(ok: false, status: -1, errorCode: 0, hours: 0,
                          endTime: nil, serverTime: nil, message: "无响应", raw: "")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data.prefix(180), encoding: .utf8) ?? ""
            return Reward(ok: false, status: -1, errorCode: 0, hours: 0,
                          endTime: nil, serverTime: nil, message: "非 JSON", raw: raw)
        }

        let status = Song.intValue(root["status"]) ?? -1
        let errcode = Song.intValue(root["errcode"]) ?? 0
        let errorCode = Song.intValue(root["error_code"]) ?? 0
        let message = (root["error_msg"] as? String)
            ?? (root["errmsg"] as? String)
            ?? (root["message"] as? String)
            ?? (root["error"] as? String)
            ?? ""

        var hours = 0
        var endTime: Date?
        var serverTime: Date?
        if let payload = root["data"] as? [String: Any] {
            hours = Song.intValue(payload["ad_vip_num"])
                ?? Song.intValue(payload["award_vip_hour"])
                ?? 0
            if let end = Song.intValue(payload["ad_vip_end_time"]), end > 0 {
                endTime = Date(timeIntervalSince1970: TimeInterval(end) / 1000)
            }
            if let server = Song.intValue(payload["server_time"]), server > 0 {
                serverTime = Date(timeIntervalSince1970: TimeInterval(server) / 1000)
            }
        }

        // 唯一成功条件：status == 1。131001 只代表这个来源今天领过，
        // 不能像旧代码那样当成成功写缓存。
        let ok = status == 1 && errcode == 0
        let raw = ok ? "" : (String(data: data.prefix(220), encoding: .utf8) ?? "")
        return Reward(ok: ok, status: status, errorCode: errorCode, hours: hours,
                      endTime: endTime, serverTime: serverTime, message: message, raw: raw)
    }

    private static func parseReply(_ data: Data?, prefix: String) -> Reply {
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
        let ok = status == 1 && errcode == 0
        var text = "\(prefix) status=\(status) errcode=\(errcode) error_code=\(errorCode)"
        if !message.isEmpty { text += " msg=\(message)" }
        if !ok {
            let raw = String(data: data.prefix(200), encoding: .utf8) ?? ""
            text += " | \(raw)"
        }
        return Reply(ok: ok, text: text)
    }

    private static func store(_ reward: Reward) {
        guard let end = reward.endTime, end.timeIntervalSinceNow > 0 else { return }
        UserDefaults.standard.set(end.timeIntervalSince1970 * 1000, forKey: adFreeEndKey)
    }

    static func dateKey() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
