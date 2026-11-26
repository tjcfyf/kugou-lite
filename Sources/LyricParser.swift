import Foundation
import Compression

struct LyricWord: Equatable {
    let start: TimeInterval
    let duration: TimeInterval
    let text: String
}

struct LyricLine: Identifiable, Equatable {
    let time: TimeInterval
    let text: String
    var words: [LyricWord] = []
    var duration: TimeInterval = 0
    var translation: String?
    var romanization: String?

    var id: TimeInterval { time }

    init(time: TimeInterval,
         text: String,
         words: [LyricWord] = [],
         duration: TimeInterval = 0,
         translation: String? = nil,
         romanization: String? = nil) {
        self.time = time
        self.text = text
        self.words = words
        self.duration = duration
        self.translation = translation
        self.romanization = romanization
    }
}

/// LRC / 增强 LRC / KRC 的统一解析器。
/// KRC 是酷狗服务端提供的逐字格式，结构接近 YRC，但不做格式名称上的偷换。
enum LyricParser {
    // 歌词页是带逐行模糊的 LazyVStack；异常歌词文件（几百上千行、单行几百个
    // 逐字标签）会让首次滚动和逐字高亮直接占满主线程。正常歌曲远小于这些上限，
    // 这里只是把损坏/恶意的 LRC/KRC 截断到可渲染的规模。
    private static let maxLines = 500
    private static let maxScannedSourceLines = 3000
    private static let maxLineCharacters = 400
    private static let maxKRCWords = 120

    private static let krcLineRegex = try! NSRegularExpression(pattern: "^\\[(\\d+),(\\d+)\\](.*)$")
    private static let krcWordRegex = try! NSRegularExpression(pattern: "<(\\d+),(\\d+),\\d+>([^<]*)")
    private static let yrcWordRegex = try! NSRegularExpression(pattern: "\\((\\d+),(\\d+),\\d+\\)([^(]*)")
    private static let lrcLineRegex = try! NSRegularExpression(
        pattern: "^((?:\\[[0-9]{1,2}:[0-9]{1,2}(?:[\\.:][0-9]{1,3})?\\])+)(.*)$"
    )
    private static let lrcTimeRegex = try! NSRegularExpression(
        pattern: "\\[([0-9]{1,2}):([0-9]{1,2})(?:[\\.:]([0-9]{1,3}))?\\]"
    )
    private static let enhancedWordRegex = try! NSRegularExpression(
        pattern: "<([0-9]{1,2}):([0-9]{1,2})(?:[\\.:]([0-9]{1,3}))?>([^<]*)"
    )

    static func parse(_ raw: String) -> [LyricLine] {
        let text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let sourceLines = text.components(separatedBy: "\n")
        let language = decodeLanguage(sourceLines)
        var lines: [LyricLine] = []
        var lastLRC: (index: Int, time: TimeInterval, text: String)?
        var scanned = 0

        for sourceLine in sourceLines {
            scanned += 1
            guard scanned <= maxScannedSourceLines, lines.count < maxLines else { break }
            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { lastLRC = nil; continue }
            if line.hasPrefix("[language:") { continue }

            if let krc = parseKRCLine(line) {
                lastLRC = nil
                lines.append(krc)
                continue
            }

            guard let lrc = parseLRCLine(line), !lrc.text.isEmpty else {
                lastLRC = nil
                continue
            }

            // 同一时间戳的第二行：作为上一行的译文，而不是多插一条重复歌词。
            if let previous = lastLRC,
               abs(lrc.times[0] - previous.time) < 0.18,
               previous.text != lrc.text,
               lines.indices.contains(previous.index),
               lines[previous.index].translation == nil {
                lines[previous.index].translation = String(lrc.text.prefix(maxLineCharacters))
                lastLRC = nil
                continue
            }

            let index = lines.count
            let display = String(lrc.text.prefix(maxLineCharacters))
            if let words = lrc.words, !words.isEmpty, words.count <= maxKRCWords {
                lines.append(LyricLine(time: words[0].start,
                                       text: display,
                                       words: words,
                                       duration: max((words.last?.start ?? 0) + (words.last?.duration ?? 0) - words[0].start, 0.25)))
            } else {
                lines.append(LyricLine(time: lrc.times[0], text: display))
            }
            lastLRC = (index, lrc.times[0], lrc.text)
        }

        // [language:] 的 lyricContent 按“已解析行”的下标对齐。
        for index in lines.indices {
            if let value = language.translation[safe: index] ?? nil,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines[index].translation = String(value.prefix(maxLineCharacters))
            }
            if let value = language.romanization[safe: index] ?? nil,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines[index].romanization = String(value.prefix(maxLineCharacters))
            }
        }

        lines.sort { $0.time < $1.time }
        fillDurations(&lines)
        return lines
    }

    /// 正则过滤只剔除匹配行，不改动时间轴和译文；空表达式视为不过滤。
    static func filter(_ lines: [LyricLine], pattern: String) -> [LyricLine] {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let regex = try? NSRegularExpression(pattern: trimmed, options: [.caseInsensitive]) else {
            return lines
        }
        return lines.filter { line in
            let candidates = [line.text, line.translation ?? ""]
            return !candidates.contains { value in
                guard !value.isEmpty else { return false }
                let range = NSRange(location: 0, length: (value as NSString).length)
                return regex.firstMatch(in: value, range: range) != nil
            }
        }
    }

    /// KRC payload: 4 字节 "krc1" + 用固定 key 循环 XOR 的 zlib 数据。
    /// 该格式来自酷狗歌词接口，不是 EchoMusic 的私有实现。
    static func decodeKRC(_ data: Data) -> String? {
        guard data.count > 8 else { return nil }
        if let plain = String(data: data, encoding: .utf8), plain.contains("[") {
            return plain
        }
        let bytes = [UInt8](data)
        guard bytes.count > 8, bytes[0...3].elementsEqual(Array("krc1".utf8)) else { return nil }
        let key: [UInt8] = [0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47,
                            0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69]
        var decrypted = bytes
        for index in 4..<decrypted.count {
            decrypted[index] ^= key[(index - 4) % key.count]
        }

        // zlib 头 2 字节 + 尾部 Adler32 4 字节；Compression 的 ZLIB 解码器吃 raw deflate。
        var payload = Data(decrypted[4...])
        guard payload.count > 6 else { return nil }
        payload = payload.subdata(in: 2..<(payload.count - 4))
        guard let inflated = inflate(payload),
              let text = String(data: inflated, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    private static func inflate(_ data: Data) -> Data? {
        let capacity = max(data.count * 24, 64 * 1024)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let written = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(destination, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        return Data(bytes: destination, count: written)
    }

    private static func parseKRCLine(_ line: String) -> LyricLine? {
        guard line.count <= 2000 else { return nil }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = krcLineRegex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 4 else { return nil }
        let lineStart = Double(ns.substring(with: match.range(at: 1))) ?? 0
        let lineDuration = Double(ns.substring(with: match.range(at: 2))) ?? 0
        let content = ns.substring(with: match.range(at: 3))
        let contentNS = content as NSString
        let contentRange = NSRange(location: 0, length: contentNS.length)
        var matches = krcWordRegex.matches(in: content, range: contentRange)
        if matches.isEmpty {
            // YRC 的逐字标签是圆括号；KRC 是尖括号。两者时间语义一致。
            matches = yrcWordRegex.matches(in: content, range: contentRange)
        }

        var words: [LyricWord] = []
        var text = ""
        var cursor = 0
        for item in matches.prefix(maxKRCWords) {
            if item.range.location > cursor {
                text += contentNS.substring(with: NSRange(location: cursor,
                                                          length: item.range.location - cursor))
            }
            let offset = Double(contentNS.substring(with: item.range(at: 1))) ?? 0
            let duration = Double(contentNS.substring(with: item.range(at: 2))) ?? 0
            let value = contentNS.substring(with: item.range(at: 3))
            words.append(LyricWord(start: (lineStart + offset) / 1000,
                                   duration: max(duration / 1000, 0.001),
                                   text: value))
            text += value
            cursor = item.range.location + item.range.length
        }
        if cursor < contentNS.length, matches.count <= maxKRCWords {
            text += contentNS.substring(from: cursor)
        }

        let display = String(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maxLineCharacters))
        guard !display.isEmpty else { return nil }
        if words.isEmpty {
            return LyricLine(time: lineStart / 1000,
                             text: display,
                             duration: max(lineDuration / 1000, 0.3))
        }
        return LyricLine(time: lineStart / 1000,
                         text: display,
                         words: words,
                         duration: max(lineDuration / 1000, 0.3))
    }

    private static func parseLRCLine(_ line: String) -> (times: [TimeInterval], text: String, words: [LyricWord]?)? {
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = lrcLineRegex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 3 else { return nil }
        let stamps = ns.substring(with: match.range(at: 1))
        let body = ns.substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        let stampNS = stamps as NSString
        let stampMatches = lrcTimeRegex.matches(in: stamps, range: NSRange(location: 0, length: stampNS.length))
        let times = stampMatches.compactMap { item -> TimeInterval? in
            guard item.numberOfRanges >= 3 else { return nil }
            let minutes = Double(stampNS.substring(with: item.range(at: 1))) ?? 0
            let seconds = Double(stampNS.substring(with: item.range(at: 2))) ?? 0
            var fraction = 0.0
            if item.numberOfRanges >= 4, item.range(at: 3).location != NSNotFound {
                let digits = stampNS.substring(with: item.range(at: 3))
                fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
            }
            return minutes * 60 + seconds + fraction
        }
        guard !times.isEmpty else { return nil }

        // 增强 LRC：<mm:ss.xx>字，直接生成逐字时间轴。
        let bodyNS = body as NSString
        let bodyRange = NSRange(location: 0, length: bodyNS.length)
        let enhanced = enhancedWordRegex.matches(in: body, range: bodyRange)
        if !enhanced.isEmpty {
            var words: [LyricWord] = []
            var text = ""
            for (index, item) in enhanced.enumerated() {
                guard item.numberOfRanges >= 5 else { continue }
                let minutes = Double(bodyNS.substring(with: item.range(at: 1))) ?? 0
                let seconds = Double(bodyNS.substring(with: item.range(at: 2))) ?? 0
                var fraction = 0.0
                if item.numberOfRanges >= 5, item.range(at: 3).location != NSNotFound {
                    let digits = bodyNS.substring(with: item.range(at: 3))
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                let start = minutes * 60 + seconds + fraction
                let value = bodyNS.substring(with: item.range(at: 4))
                let nextStart: TimeInterval
                if index + 1 < enhanced.count {
                    let next = enhanced[index + 1]
                    let nextMinutes = Double(bodyNS.substring(with: next.range(at: 1))) ?? 0
                    let nextSeconds = Double(bodyNS.substring(with: next.range(at: 2))) ?? 0
                    var nextFraction = 0.0
                    if next.range(at: 3).location != NSNotFound {
                        let digits = bodyNS.substring(with: next.range(at: 3))
                        nextFraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                    }
                    nextStart = nextMinutes * 60 + nextSeconds + nextFraction
                } else {
                    nextStart = start + max(Double(value.count) * 0.12, 0.25)
                }
                words.append(LyricWord(start: start, duration: max(nextStart - start, 0.001), text: value))
                text += value
            }
            let display = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                return (times, display, words)
            }
        }

        let clean = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return (times, clean, nil)
    }

    private static func isTimestampLine(_ line: String) -> Bool {
        let ns = line as NSString
        return lrcLineRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func fillDurations(_ lines: inout [LyricLine]) {
        guard !lines.isEmpty else { return }
        for index in lines.indices {
            let next = index + 1 < lines.count ? lines[index + 1].time : lines[index].time + 3.0
            let wordEnd: TimeInterval
            if let last = lines[index].words.last {
                wordEnd = last.start + last.duration
            } else {
                wordEnd = lines[index].time
            }
            let end = max(next, wordEnd)
            lines[index].duration = max(end - lines[index].time, 0.25)
        }
    }

    private static func decodeLanguage(_ sourceLines: [String]) -> (translation: [String?], romanization: [String?]) {
        guard let line = sourceLines.first(where: { $0.hasPrefix("[language:") }) else { return ([], []) }
        let ns = line.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        guard ns.length > 11, ns.hasSuffix("]") else { return ([], []) }
        let code = ns.substring(with: NSRange(location: 10, length: ns.length - 11))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let cleaned = code.filter { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
        guard let data = Data(base64Encoded: cleaned, options: .ignoreUnknownCharacters),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["content"] as? [[String: Any]] else { return ([], []) }

        var translations: [String?] = []
        var romanizations: [String?] = []
        for section in sections {
            let type = section["type"] as? Int ?? -1
            let raw = section["lyricContent"] as? [Any] ?? []
            let values = raw.map { stringValue($0) }
            if type == 1 { translations = values }
            if type == 0 { romanizations = values }
        }
        return (translations, romanizations)
    }

    private static func stringValue(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let array = value as? [Any] {
            return array.map { stringValue($0) }.joined()
        }
        return ""
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
