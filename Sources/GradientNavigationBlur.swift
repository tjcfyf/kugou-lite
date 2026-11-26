import SwiftUI
import UIKit

/// 顶栏渐变模糊：从状态栏/导航栏区域向下逐渐变清晰。
/// SwiftUI 的 material 只能整块均匀模糊，这里用 UIVisualEffectView + CAGradientLayer
/// 做一张“从上到下 alpha 递减”的模糊背板，插在导航栏下方、内容上方。
struct GradientNavigationBlur: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Installer {
        let controller = Installer()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: Installer, context: Context) {}

    final class Installer: UIViewController {
        private let backdropTag = 0x5A17B1
        private weak var installedNavigationController: UINavigationController?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfNeeded()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            layoutBackdrop()
        }

        private func installIfNeeded() {
            guard let navigation = findNavigationController() else { return }
            installedNavigationController = navigation

            let bar = navigation.navigationBar
            // 只让这三棵根导航栈透明；详情页 push 进来也沿用同一层渐变模糊。
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = nil
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.compactAppearance = appearance
            bar.isTranslucent = true
            bar.setBackgroundImage(UIImage(), for: .default)
            bar.shadowImage = UIImage()
            bar.backgroundColor = .clear

            if let old = navigation.view.viewWithTag(backdropTag) {
                old.removeFromSuperview()
            }
            let blur = GradientBlurBackdrop(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            blur.tag = backdropTag
            blur.isUserInteractionEnabled = false
            blur.backgroundColor = .clear
            blur.autoresizingMask = [.flexibleWidth]
            // addSubview 后再把导航栏提到最前，确保模糊层在滚动内容之上、
            // 导航标题之下。原来 insert(belowSubview:) 在部分层级里会落到内容下面，
            // 结果完全看不到模糊，只剩 NavigationBar 的白底。
            navigation.view.addSubview(blur)
            navigation.view.bringSubviewToFront(bar)
            layoutBackdrop()
        }

        private func layoutBackdrop() {
            guard let navigation = installedNavigationController ?? findNavigationController(),
                  let blur = navigation.view.viewWithTag(backdropTag) else { return }
            let bar = navigation.navigationBar
            let height = max(bar.frame.maxY + 62, 138)
            blur.frame = CGRect(x: 0, y: 0, width: navigation.view.bounds.width, height: height)
        }

        private func findNavigationController() -> UINavigationController? {
            var current: UIViewController? = self
            while let controller = current {
                if let navigation = controller as? UINavigationController { return navigation }
                current = controller.parent
            }
            return nil
        }
    }
}

/// 模糊层 + 垂直 alpha 遮罩，底部完全透明，滚动内容从这里过渡到清晰。
/// 用容器 view 承载 UIVisualEffectView，遮罩加在容器 layer 上；
/// 直接给 UIVisualEffectView 自己加 mask 时，部分系统版本只遮住内容层，
/// 模糊效果本身仍然整块铺满，看起来就像一层白色罩。
final class GradientBlurBackdrop: UIView {
    private let blurView: UIVisualEffectView
    private let fadeMask = CAGradientLayer()

    init(effect: UIBlurEffect?) {
        blurView = UIVisualEffectView(effect: effect)
        super.init(frame: .zero)

        backgroundColor = .clear
        isUserInteractionEnabled = false
        blurView.backgroundColor = .clear
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        fadeMask.colors = [
            UIColor.black.cgColor,
            UIColor.black.withAlphaComponent(0.72).cgColor,
            UIColor.clear.cgColor,
        ]
        fadeMask.locations = [0, 0.56, 1]
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
        layer.mask = fadeMask
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
        fadeMask.frame = bounds
    }
}

extension View {
    /// 放在三个根 Tab 的内容上；会找到所在 UINavigationController 并安装顶栏渐变模糊。
    func gradientNavigationBlur() -> some View {
        background(
            GradientNavigationBlur()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}
