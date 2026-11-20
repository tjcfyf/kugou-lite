import UIKit

/// 从专辑封面里取一个可用的主色：先缩到 24×24，再按色相桶做加权统计，
/// 过滤掉接近纯黑、纯白和低饱和度的像素，避免背景被灰黑色吃掉。
enum ArtworkPalette {
    static func dominantColor(from image: UIImage) -> UIColor? {
        guard let cgImage = image.cgImage else { return nil }

        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }

            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var buckets: [Int: (weight: Double, red: Double, green: Double, blue: Double)] = [:]

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }

            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

            // 纯黑、纯白和灰调不参与主色统计。
            guard luminance > 0.10, luminance < 0.94, saturation > 0.08 else { continue }

            let redBucket = min(Int(red * 7.999), 7)
            let greenBucket = min(Int(green * 7.999), 7)
            let blueBucket = min(Int(blue * 7.999), 7)
            let key = (redBucket << 6) | (greenBucket << 3) | blueBucket
            let weight = 1.0 + saturation * 3.0

            let old = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (
                old.weight + weight,
                old.red + red * weight,
                old.green + green * weight,
                old.blue + blue * weight
            )
        }

        if let best = buckets.max(by: { $0.value.weight < $1.value.weight })?.value,
           best.weight > 0 {
            return UIColor(
                red: CGFloat(best.red / best.weight),
                green: CGFloat(best.green / best.weight),
                blue: CGFloat(best.blue / best.weight),
                alpha: 1
            )
        }

        // 极端情况下（整张图几乎无彩色），再退回整体平均值。
        var redSum = 0.0
        var greenSum = 0.0
        var blueSum = 0.0
        var count = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            guard luminance > 0.08, luminance < 0.96 else { continue }
            redSum += red
            greenSum += green
            blueSum += blue
            count += 1
        }
        guard count > 0 else { return nil }

        return UIColor(
            red: CGFloat(redSum / count),
            green: CGFloat(greenSum / count),
            blue: CGFloat(blueSum / count),
            alpha: 1
        )
    }
}
