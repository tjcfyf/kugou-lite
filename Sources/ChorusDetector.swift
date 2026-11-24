import Foundation

/// 从歌词结构推断副歌区间：副歌最稳定的特征是同一句/同一组句子重复出现。
/// 不依赖平台私有标记，纯本地计算，KRC/LRC 都能用。
enum ChorusDetector {
    static func ranges(from lines: [LyricLine], duration: Double) -> [ClosedRange<Double>] {
        guard lines.count >= 4 else { return [] }

        let normalized = lines.map { normalize($0.text) }
        var frequency: [String: Int] = [:]
        for text in normalized where !text.isEmpty {
            frequency[text, default: 0] += 1
        }

        var marks = Array(repeating: false, count: lines.count)
        for index in lines.indices {
            let text = normalized[index]
            // 太短的“啊/哦/耶”会大量重复，不能当副歌标记。
            if text.count >= 4, (frequency[text] ?? 0) >= 2 {
                marks[index] = true
            }
        }

        // 有些副歌每句只出现一次，但连续两三句作为一个整体会重复。
        // 用二元组签名补一层检测，避免整首歌没有标记。
        var pairFrequency: [String: Int] = [:]
        if lines.count >= 6 {
            for index in 0..<(lines.count - 1) {
                let signature = normalized[index] + "|" + normalized[index + 1]
                if normalized[index].count >= 3, normalized[index + 1].count >= 3 {
                    pairFrequency[signature, default: 0] += 1
                }
            }
            for index in 0..<(lines.count - 1) {
                let signature = normalized[index] + "|" + normalized[index + 1]
                if normalized[index].count >= 3, normalized[index + 1].count >= 3,
                   (pairFrequency[signature] ?? 0) >= 2 {
                    marks[index] = true
                    marks[index + 1] = true
                }
            }
        }

        var ranges: [ClosedRange<Double>] = []
        for index in lines.indices where marks[index] {
            let start = max(0, lines[index].time)
            let end: Double
            if index + 1 < lines.count {
                end = max(start, lines[index + 1].time)
            } else if duration > start {
                end = duration
            } else {
                end = start + max(lines[index].duration, 2)
            }
            guard end > start else { continue }
            if let last = ranges.last, start <= last.upperBound + 0.8 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, end)
            } else {
                ranges.append(start...end)
            }
        }
        return ranges
    }

    private static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        return String(lowered.filter { $0.isLetter || $0.isNumber })
    }
}
