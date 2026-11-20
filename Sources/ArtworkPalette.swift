import SwiftUI
import UIKit

/// 从专辑封面中间区域提取三个主色，用于播放页的纯色背景。
/// 只做轻量色桶统计，不引第三方库，也不参与全站主题。
enum ArtworkPalette {
    static let fallback: [Color] = [
        Color(red: 0.13, green: 0.14, blue: 0.18),
        Color(red: 0.24, green: 0.26, blue: 0.33),
        Color(red: 0.38, green: 0.40, blue: 0.48)
    ]

    static func colors(from image: UIImage) -> [Color] {
        let side = 64
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let small = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fill(rect)
            image.draw(in: rect)
        }
        guard let cgImage = small.cgImage else { return fallback }

        let byteCount = side * side * 4
        let rawPixels = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 4)
        defer { rawPixels.deallocate() }
        guard let context = CGContext(data: rawPixels,
                                      width: side,
                                      height: side,
                                      bitsPerComponent: 8,
                                      bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return fallback
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        let pixels = rawPixels.assumingMemoryBound(to: UInt8.self)

        // 只取画面中间 60%：专辑图边缘常有文字、边框或纯黑留白。
        let lower = Int(Double(side) * 0.20)
        let upper = Int(Double(side) * 0.80)
        var buckets: [Int: Bucket] = [:]
        for y in lower..<upper {
            for x in lower..<upper {
                let offset = (y * side + x) * 4
                let r = Double(pixels[offset]) / 255
                let g = Double(pixels[offset + 1]) / 255
                let b = Double(pixels[offset + 2]) / 255
                let maxChannel = max(r, max(g, b))
                let minChannel = min(r, min(g, b))
                // 去掉接近纯黑/纯白的像素，避免背景直接变成黑白。
                guard maxChannel > 0.12, minChannel < 0.94 else { continue }
                let key = (Int(r * 15) << 8) | (Int(g * 15) << 4) | Int(b * 15)
                let saturation = maxChannel > 0 ? (maxChannel - minChannel) / maxChannel : 0
                buckets[key, default: Bucket()].add(r: r, g: g, b: b, saturation: saturation)
            }
        }

        let candidates = buckets.values
            .filter { $0.count >= 6 }
            .sorted { $0.score > $1.score }
        var selected: [Bucket] = []
        for candidate in candidates {
            let color = candidate.color
            let isFarEnough = selected.allSatisfy { existing in
                let distance = existing.color.distance(to: color)
                return distance > 0.16
            }
            if isFarEnough {
                selected.append(candidate)
            }
            if selected.count == 3 { break }
        }

        guard let primary = selected.first else { return fallback }
        var colors = selected.map { Color(uiColor: $0.uiColor) }
        if colors.count < 3 {
            let variants = variants(of: primary.uiColor)
            for color in variants where colors.count < 3 {
                colors.append(Color(uiColor: color))
            }
        }
        while colors.count < 3 {
            colors.append(fallback[colors.count])
        }
        return colors
    }

    private struct Bucket {
        var count = 0
        var r = 0.0
        var g = 0.0
        var b = 0.0
        var saturation = 0.0

        mutating func add(r: Double, g: Double, b: Double, saturation: Double) {
            count += 1
            self.r += r
            self.g += g
            self.b += b
            self.saturation += saturation
        }

        var score: Double {
            let averageSaturation = count > 0 ? saturation / Double(count) : 0
            return Double(count) * (0.55 + averageSaturation * 1.45)
        }

        var uiColor: UIColor {
            guard count > 0 else { return .black }
            return UIColor(red: CGFloat(r / Double(count)),
                           green: CGFloat(g / Double(count)),
                           blue: CGFloat(b / Double(count)),
                           alpha: 1)
        }

        var color: UIColor { uiColor }
    }

    private static func variants(of color: UIColor) -> [UIColor] {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return fallback.map { UIColor($0) }
        }
        let darker = UIColor(hue: hue,
                             saturation: min(1, saturation * 0.92),
                             brightness: max(0.12, brightness * 0.62),
                             alpha: 1)
        let lighter = UIColor(hue: hue,
                              saturation: min(1, saturation * 1.08),
                              brightness: min(0.92, brightness * 1.34),
                              alpha: 1)
        return [darker, lighter]
    }
}

private extension UIColor {
    func distance(to other: UIColor) -> Double {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let dr = Double(r1 - r2)
        let dg = Double(g1 - g2)
        let db = Double(b1 - b2)
        return (dr * dr + dg * dg + db * db).squareRoot()
    }
}
