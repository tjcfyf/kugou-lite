import Foundation
import UIKit

/// 登录排查日志：只写入 App Documents，不弹系统权限。
/// 页面显示脱敏版本；分享文件里保留完整 access_token，方便本地复现。
final class LoginDebug {
    static let shared = LoginDebug()
    private(set) var entries: [String] = []
    private let queue = DispatchQueue(label: "sonora.login.debug")

    var hasEntries: Bool { !entries.isEmpty }

    func clear() {
        queue.sync { entries.removeAll() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    func add(_ text: String) {
        queue.sync {
            let stamp = ISO8601DateFormatter().string(from: Date())
            entries.append("[\(stamp)] \(text)")
        }
        persist()
    }

    /// 页面上展示的版本：把 access_token / params / pk 的长串打码。
    var maskedText: String {
        queue.sync {
            entries.map { line in
                var value = line
                if let regex = try? NSRegularExpression(pattern: "accessToken=([^\n]+)") {
                    let range = NSRange(value.startIndex..<value.endIndex, in: value)
                    value = regex.stringByReplacingMatches(in: value, range: range,
                                                           withTemplate: "accessToken=<已脱敏>")
                }
                for key in ["access_token", "params", "pk", "token"] {
                    let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]+)\""
                    if let regex = try? NSRegularExpression(pattern: pattern) {
                        let range = NSRange(value.startIndex..<value.endIndex, in: value)
                        value = regex.stringByReplacingMatches(
                            in: value, range: range,
                            withTemplate: "\"\(key)\":\"<已脱敏 \(key.count) 字符>\""
                        )
                    }
                }
                return value
            }.joined(separator: "\n\n")
        }
    }

    var fullText: String {
        queue.sync { entries.joined(separator: "\n\n") }
    }

    var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("Sonora-QQLogin.log")
    }

    func persist() {
        let text = fullText
        try? text.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }
}
