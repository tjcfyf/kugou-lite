import SwiftUI
import UIKit
import Combine

/// 当前播放封面的全局主题色。播放页、底栏和所有页面背景都跟随它，
/// 但颜色只用于渐变和强调，不改变正文的黑白层级。
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
                return UIColor(named: "Accent") ?? UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)
            }

            if traits.userInterfaceStyle == .dark {
                return UIColor(hue: hue,
                               saturation: min(saturation * 1.04, 1),
                               brightness: min(brightness + 0.16, 1),
                               alpha: 1)
            }
            return UIColor(hue: hue,
                           saturation: min(saturation * 0.96, 1),
                           brightness: max(brightness - 0.18, 0.12),
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
        guard let color = ArtworkPalette.dominantColor(from: image) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.requestedKey == key else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                self.palette = color
                self.paletteKey = key
            }
        }
    }
}
