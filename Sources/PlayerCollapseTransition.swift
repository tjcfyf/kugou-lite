import UIKit

/// 播放页窗口形变的几何计算。`PlayerPanelFrame`、交互拖动和收起快照使用
/// 同一套公式，保证展开/收起第一帧不会错位。
enum PlayerPanelGeometry {
    static func rect(progress: CGFloat, origin: CGRect, screen: CGSize) -> CGRect {
        let p = min(max(progress, 0), 1)
        let w = max(screen.width, 1)
        let h = max(screen.height, 1)

        let top = origin.minY * (1 - p)
        let bottom = min(h, origin.maxY + (h - origin.maxY) * p)
        let left = origin.minX * (1 - p)
        let right = min(w, origin.maxX + (w - origin.maxX) * p)

        return CGRect(
            x: left,
            y: max(0, min(top, bottom)),
            width: max(0, right - left),
            height: max(0, bottom - top)
        )
    }
}

/// Apple Music 式收起：整页播放页作为一张 sheet 跟着手指往下滑，
/// 不缩成小播放页，也不把封面单独抠出来飘在首页上。
///
/// 1. 跟手阶段只改 UIKit 快照的 frame / 顶部圆角，SwiftUI 页面不 reflow；
/// 2. 往下拖时整页下移，顶部逐渐出现 14pt 圆角，像一张被拉下来的卡片；
/// 3. 松手关闭时快照继续滑出屏幕底部，取消时弹回原位；
/// 4. 滑出后再隐藏真实播放页，避免在切换点销毁整页造成卡顿。
final class PlayerCollapseTransition {
    static let shared = PlayerCollapseTransition()

    private var pageShot: UIView?
    private var animator: UIViewPropertyAnimator?

    private var pageRect: CGRect = .zero
    private var screen: CGSize = .zero
    private var isInteractive = false

    var isInteractiveActive: Bool { isInteractive }

    /// 点击关闭按钮 / 非交互收起。
    @discardableResult
    func begin(from panelRect: CGRect,
               duration: TimeInterval,
               completion: @escaping () -> Void) -> Bool {
        guard pageShot == nil, !isInteractive,
              let page = makeSnapshot(from: panelRect) else { return false }

        pageRect = page.frame
        screen = page.frame.size
        attach(page)

        let end = pageRect.offsetBy(dx: 0, dy: max(screen.height, 1) + 24)
        let animator = makeAnimator(duration: duration) {
            page.frame = end
            page.layer.cornerRadius = 14
        } completion: { [weak self, weak page] _ in
            guard let self, let page else { return }
            self.animator = nil
            page.removeFromSuperview()
            if self.pageShot === page { self.pageShot = nil }
            completion()
        }
        self.animator = animator
        animator.startAnimation()
        return true
    }

    /// 跟手开始：从当前全屏播放页裁一张整页快照。
    @discardableResult
    func beginInteractive(from panelRect: CGRect,
                          screen: CGSize) -> Bool {
        guard pageShot == nil, !isInteractive, !panelRect.isEmpty,
              let page = makeSnapshot(from: panelRect) else { return false }

        pageRect = page.frame
        self.screen = screen
        isInteractive = true
        attach(page)
        return true
    }

    /// 跟手阶段：只移动整页快照，不缩放、不重排 SwiftUI。
    func updateInteractive(progress: CGFloat) {
        guard isInteractive, let page = pageShot else { return }
        let p = progress
        let travel = max(screen.height * 0.2, 1)
        // progress 允许小于 0：用户拖过 20% 屏幕后，卡片继续跟着手指走。
        let offset = min(max(screen.height, 1) + 24, (1 - p) * travel)
        let radius = min(14, 14 * max(0, min(1, p)))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        page.frame = pageRect.offsetBy(dx: 0, dy: offset)
        page.layer.cornerRadius = radius
        CATransaction.commit()
    }

    /// 松手：progress=0 滑出屏幕；progress=1 回到全屏。
    @discardableResult
    func finishInteractive(to progress: CGFloat,
                           duration: TimeInterval,
                           completion: @escaping () -> Void) -> Bool {
        guard isInteractive, let page = pageShot else { return false }
        isInteractive = false

        let closing = progress < 0.999
        let end: CGRect
        if closing {
            end = pageRect.offsetBy(dx: 0, dy: max(screen.height, 1) + 24)
        } else {
            end = pageRect
        }

        let animator = makeAnimator(duration: duration) {
            page.frame = end
            page.layer.cornerRadius = closing ? 14 : 0
        } completion: { [weak self, weak page] _ in
            guard let self, let page else { return }
            self.animator = nil
            page.removeFromSuperview()
            if self.pageShot === page { self.pageShot = nil }
            completion()
        }
        self.animator = animator
        animator.startAnimation()
        return true
    }

    func cancel() {
        animator?.stopAnimation(true)
        animator = nil
        pageShot?.removeFromSuperview()
        pageShot = nil
        isInteractive = false
    }

    // MARK: - Snapshot

    private func makeSnapshot(from rect: CGRect) -> UIView? {
        guard let window = keyWindow, rect.width > 1, rect.height > 1 else { return nil }
        guard let shot = window.resizableSnapshotView(
            from: rect,
            afterScreenUpdates: false,
            withCapInsets: .zero
        ) else { return nil }

        shot.frame = rect
        shot.isUserInteractionEnabled = false
        shot.layer.masksToBounds = true
        shot.layer.cornerCurve = .continuous
        shot.accessibilityElementsHidden = true
        return shot
    }

    private func attach(_ page: UIView) {
        guard let window = page.superview ?? keyWindow else { return }
        if page.superview == nil {
            window.addSubview(page)
        }
        pageShot = page
    }

    private func makeAnimator(duration: TimeInterval,
                              animations: @escaping () -> Void,
                              completion: @escaping (UIViewAnimatingPosition) -> Void) -> UIViewPropertyAnimator {
        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.32, y: 0.02),
                controlPoint2: CGPoint(x: 0.18, y: 1.0)
            )
        )
        animator.addAnimations(animations)
        animator.addCompletion(completion)
        return animator
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}
