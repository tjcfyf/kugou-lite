import Foundation

struct LyricLine: Identifiable, Equatable {
    let time: TimeInterval
    let text: String
    var id: TimeInterval { time }
}

enum LyricParser {
    static func parse(_ raw: String) -> [LyricLine] {
        let pattern = "\\[(\\d{1,2}):(\\d{1,2})(?:\\.(\\d{1,3}))?\\]([^\\[]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: text.length))

        var lines: [LyricLine] = []
        for match in matches where match.numberOfRanges >= 5 {
            let minutes = Double(text.substring(with: match.range(at: 1))) ?? 0
            let seconds = Double(text.substring(with: match.range(at: 2))) ?? 0
            var fraction: Double = 0
            if match.range(at: 3).location != NSNotFound {
                let digits = text.substring(with: match.range(at: 3))
                fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
            }
            let content = text.substring(with: match.range(at: 4))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            lines.append(LyricLine(time: minutes * 60 + seconds + fraction, text: content))
        }
        return lines.sorted { $0.time < $1.time }
    }
}
