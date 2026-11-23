import UIKit

/// 播放页窗口形变的几何计算。`PlayerPanelFrame`、交互拖动和收起快照必须使用
/// 同一套公式，否则第一帧会和真实面板错位。
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

/// 播放页收起/取消时的快照动画。
///
/// 这条路径完全不碰 SwiftUI 页面树：
/// 1. 从窗口裁一张当前播放页快照；
/// 2. 跟手阶段只改快照的 frame / cornerRadius；
/// 3. 松手后用 UIViewPropertyAnimator 把快照继续送到迷你播放器或送回全屏。
///
/// 这样 iOS 15 上不会出现「每一帧重新排版整页 → 只跳几帧」的 PPT 式收起。
final class PlayerCollapseTransition {
    static let shared = PlayerCollapseTransition()

    private var snapshot: UIView?
    private var animator: UIViewPropertyAnimator?

    // 交互拖动期间使用的目标几何。
    private var interactiveOrigin: CGRect = .zero
    private var interactiveScreen: CGSize = .zero
    private var isInteractive = false

    var isInteractiveActive: Bool { isInteractive }

    /// 点击关闭按钮 / 非交互收起。
    @discardableResult
    func begin(from panelRect: CGRect,
               to targetRect: CGRect,
               startRadius: CGFloat,
               duration: TimeInterval,
               completion: @escaping () -> Void) -> Bool {
        guard snapshot == nil, !isInteractive,
              let shot = makeSnapshot(from: panelRect) else { return false }

        let target = clamped(targetRect, in: shot.superview?.bounds ?? shot.frame)
        let animator = makeAnimator(duration: duration) {
            shot.frame = target
            shot.layer.cornerRadius = 28
        } completion: { [weak self, weak shot] _ in
            shot?.removeFromSuperview()
            if self?.snapshot === shot { self?.snapshot = nil }
            self?.animator = nil
            completion()
        }
        start(animator, startRadius: startRadius, on: shot)
        return true
    }

    /// 开始跟手收起。此时播放页仍然是全屏，所以从全屏矩形裁图。
    @discardableResult
    func beginInteractive(from panelRect: CGRect,
                          origin: CGRect,
                          screen: CGSize,
                          startRadius: CGFloat) -> Bool {
        guard snapshot == nil, !isInteractive, !panelRect.isEmpty,
              let shot = makeSnapshot(from: panelRect) else { return false }
        interactiveOrigin = origin
        interactiveScreen = screen
        isInteractive = true
        shot.layer.cornerRadius = startRadius
        return true
    }

    /// 跟手阶段每一帧只改快照 frame；不触发 SwiftUI 布局。
    func updateInteractive(progress: CGFloat) {
        guard isInteractive, let shot = snapshot else { return }
        let rect = PlayerPanelGeometry.rect(progress: progress,
                                            origin: interactiveOrigin,
                                            screen: interactiveScreen)
        let radius = max(0, 28 * (1 - min(max(progress, 0), 1)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shot.frame = rect
        shot.layer.cornerRadius = radius
        CATransaction.commit()
    }

    /// 松手：progress=0 收进迷你播放器，progress=1 回到全屏。
    @discardableResult
    func finishInteractive(to progress: CGFloat,
                           duration: TimeInterval,
                           completion: @escaping () -> Void) -> Bool {
        guard isInteractive, let shot = snapshot else { return false }
        isInteractive = false

        let target = PlayerPanelGeometry.rect(progress: progress,
                                              origin: interactiveOrigin,
                                              screen: interactiveScreen)
        let radius = max(0, 28 * (1 - min(max(progress, 0), 1)))
        let animator = makeAnimator(duration: duration) {
            shot.frame = target
            shot.layer.cornerRadius = radius
        } completion: { [weak self, weak shot] _ in
            shot?.removeFromSuperview()
            if self?.snapshot === shot { self?.snapshot = nil }
            self?.animator = nil
            completion()
        }
        start(animator, startRadius: shot.layer.cornerRadius, on: shot)
        return true
    }

    func cancel() {
        animator?.stopAnimation(true)
        animator = nil
        snapshot?.removeFromSuperview()
        snapshot = nil
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
        shot.isUserInteractionEnabled = true
        shot.layer.masksToBounds = true
        shot.layer.cornerCurve = .continuous
        shot.accessibilityElementsHidden = true
        window.addSubview(shot)
        snapshot = shot
        return shot
    }

    private func makeAnimator(duration: TimeInterval,
                              animations: @escaping () -> Void,
                              completion: @escaping (UIViewAnimatingPosition) -> Void) -> UIViewPropertyAnimator {
        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.3, y: 0.2),
                controlPoint2: CGPoint(x: 0.3, y: 1.0)
            )
        )
        animator.addAnimations(animations)
        animator.addCompletion(completion)
        return animator
    }

    private func start(_ animator: UIViewPropertyAnimator, startRadius: CGFloat, on shot: UIView) {
        shot.layer.cornerRadius = startRadius
        self.animator = animator
        animator.startAnimation()
    }

    private func clamped(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - rect.width))
        let y = min(max(rect.minY, bounds.minY), max(bounds.minY, bounds.maxY - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
    }
}
