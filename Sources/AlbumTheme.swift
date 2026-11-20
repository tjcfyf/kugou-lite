import SwiftUI
import UIKit
import Combine

/// 当前播放封面的全局主题色。播放页、底栏和所有页面背景都跟随它，
/// 但颜色只用于渐变和强调，不改变正文的黑白层级。
@MainActor
final class AlbumThemeStore: ObservableObject {
    static let shared = AlbumThemeStore()

    @Published private(set) var palette: UIColor?
    @Published private(set) var paletteKey: String?

    private var cancellable: AnyCancellable?
    private var loadTask: Task<Void, Never>?
    private var requestedKey: String?
    private let imageCache = NSCache<NSString, UIImage>()

    private init() {
        imageCache.countLimit = 24
        cancellable = PlayerEngine.shared.$current
            .map { $0?.coverURL }
            .removeDuplicates()
            .sink { [weak self] url in
                self?.load(url)
            }
    }

    var paletteColor: Color? {
        palette.map { Color(uiColor: $0) }
    }

    var accentColor: Color {
        Color(uiColor: accentUIColor)
    }

    /// 背景用专辑主色，按钮/图标/进度等改用互补色，保证和背景有明确的色相与明度差。
    var accentUIColor: UIColor {
        guard let palette = palette else {
            return UIColor(named: "Accent") ?? UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)
        }

        return UIColor { traits in
            let base = palette.resolvedColor(with: traits)
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            guard base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha),
                  saturation > 0.10 else {
                // 中性封面就退回黑/白对比，不再硬塞蓝色。
                return traits.userInterfaceStyle == .dark
                    ? UIColor(white: 0.96, alpha: 1)
                    : UIColor(white: 0.08, alpha: 1)
            }

            let complementHue = hue >= 0.5 ? hue - 0.5 : hue + 0.5
            let complementSaturation = min(max(saturation * 0.82, 0.52), 0.88)
            let complementBrightness: CGFloat = traits.userInterfaceStyle == .dark ? 0.58 : 0.50
            return UIColor(hue: complementHue,
                           saturation: complementSaturation,
                           brightness: complementBrightness,
                           alpha: 1)
        }
    }

    /// 供逐字歌词插值使用，避免把 SwiftUI 的环境色转成固定的 UIColor。
    func accentComponents(for scheme: ColorScheme) -> (Double, Double, Double) {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        let color = accentUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return (0, 0.478, 1)
        }
        return (Double(red), Double(green), Double(blue))
    }

    /// 播放页背景：不再用近黑/近白打底，而是用中心色的深/浅变体铺满整页，
    /// 只保留从亮到暗的渐变，黑底和白底都尽量少。
    func playerGradientColors(for scheme: ColorScheme) -> (top: Color, mid: Color, bottom: Color) {
        let colors = playerGradientUIColors(for: scheme)
        return (Color(uiColor: colors.top), Color(uiColor: colors.mid), Color(uiColor: colors.bottom))
    }

    /// 播放页前景：按播放页三段背景的平均亮度选深色或浅色，不再固定用白/黑。
    /// 这样亮封面配深色字、暗封面配浅色字，文字和图标都能真正和背景形成对比。
    func playerForegroundColors(for scheme: ColorScheme) -> (primary: Color, secondary: Color, tertiary: Color) {
        let foreground = playerForegroundUIColor(for: scheme)
        return (Color(uiColor: foreground),
                Color(uiColor: foreground.withAlphaComponent(0.80)),
                Color(uiColor: foreground.withAlphaComponent(0.56)))
    }

    func playerForegroundComponents(for scheme: ColorScheme) -> (Double, Double, Double) {
        let color = playerForegroundUIColor(for: scheme)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return (1, 1, 1)
        }
        return (Double(red), Double(green), Double(blue))
    }

    /// 强调色如果本身太亮/太暗，文字改用与强调色反差更大的黑或白。
    func accentForegroundColor(for scheme: ColorScheme) -> Color {
        let accent = accentUIColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        return relativeLuminance(accent) < 0.42
            ? Color(uiColor: UIColor(white: 0.98, alpha: 1))
            : Color(uiColor: UIColor(red: 0.035, green: 0.045, blue: 0.060, alpha: 1))
    }

    /// 窗口边缘/安全区露出一部分时，用当前专辑色和底色混出的深/浅色，避免闪纯黑条。
    var windowBackgroundUIColor: UIColor {
        UIColor { traits in
            let base = (UIColor(named: "Background") ?? .black).resolvedColor(with: traits)
            guard let palette = self.palette else { return base }
            let tint = palette.resolvedColor(with: traits)
            let amount: CGFloat = traits.userInterfaceStyle == .dark ? 0.24 : 0.22
            return self.blend(base, with: tint, amount: amount)
        }
    }

    private func playerGradientUIColors(for scheme: ColorScheme) -> (top: UIColor, mid: UIColor, bottom: UIColor) {
        guard let palette = palette else {
            let base = UIColor(named: "Background") ?? .black
            return (base, base, base)
        }
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        let base = palette.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        if scheme == .dark {
            return (blend(base, with: .black, amount: 0.12),
                    blend(base, with: .black, amount: 0.40),
                    blend(base, with: .black, amount: 0.64))
        }
        return (blend(base, with: .white, amount: 0.18),
                blend(base, with: .white, amount: 0.48),
                blend(base, with: .white, amount: 0.78))
    }

    private func playerForegroundUIColor(for scheme: ColorScheme) -> UIColor {
        guard palette != nil else {
            return UIColor(named: "TextPrimary") ?? UIColor(white: 0.96, alpha: 1)
        }
        let colors = playerGradientUIColors(for: scheme)
        let average = (relativeLuminance(colors.top) * 0.25)
                    + (relativeLuminance(colors.mid) * 0.50)
                    + (relativeLuminance(colors.bottom) * 0.25)
        if average < 0.42 {
            return UIColor(white: 0.98, alpha: 1)
        }
        return UIColor(red: 0.035, green: 0.045, blue: 0.060, alpha: 1)
    }

    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return 0 }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func blend(_ color: UIColor, with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard color.getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return color }
        let t = min(max(amount, 0), 1)
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: 1)
    }

    func load(_ url: URL?) {
        let key = url?.absoluteString
        guard key != requestedKey else { return }
        requestedKey = key
        loadTask?.cancel()

        guard let url = url, let key = key else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.requestedKey == nil else { return }
                withAnimation(.easeInOut(duration: 0.55)) {
                    self.palette = nil
                    self.paletteKey = nil
                }
            }
            return
        }

        let cacheKey = key as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            apply(cached, for: key)
            return
        }

        loadTask = Task { [weak self] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let image = UIImage(data: data),
                  !Task.isCancelled else { return }
            self?.imageCache.setObject(image, forKey: cacheKey)
            self?.apply(image, for: key)
        }
    }

    private func apply(_ image: UIImage, for key: String) {
        guard let color = ArtworkPalette.centerColor(from: image)
                ?? ArtworkPalette.dominantColor(from: image) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.requestedKey == key else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                self.palette = color
                self.paletteKey = key
            }
        }
    }
}
