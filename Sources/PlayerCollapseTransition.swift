import UIKit

/// 播放页窗口形变的几何计算。`PlayerPanelFrame` 和收起快照必须使用同一套
/// 公式，否则快照的第一帧会和真实面板错位。
enum PlayerPanelGeometry {
    static func rect(progress: CGFloat, origin: CGRect, screen: CGRect) -> CGRect {
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

/// 收起播放页时不再逐帧重排 SwiftUI 页面：
/// 1. 从当前窗口裁一张播放页快照；
/// 2. 用 UIViewPropertyAnimator 只改变快照的 frame / cornerRadius；
/// 3. 动画结束后再移除快照，露出底栏的迷你播放器。
///
/// 这样收起过程只有一张静态图层在动，避免每帧重新计算歌词、材质和裁切，
/// iOS 15 上也能稳定跑满 60fps。
final class PlayerCollapseTransition {
    static let shared = PlayerCollapseTransition()

    private var snapshot: UIView?
    private var animator: UIViewPropertyAnimator?

    /// - Parameters:
    ///   - panelRect: 当前面板在窗口中的真实矩形（可能已经跟手拖到一半）。
    ///   - targetRect: 底栏迷你播放器封面的矩形。
    ///   - startRadius: 当前面板圆角；收起目标是 28pt 圆盘。
    /// - Returns: 快照是否成功建立。失败时调用方应回退到普通 SwiftUI 动画。
    @discardableResult
    func begin(from panelRect: CGRect,
               to targetRect: CGRect,
               startRadius: CGFloat,
               duration: TimeInterval,
               completion: @escaping () -> Void) -> Bool {
        guard let window = keyWindow,
              panelRect.width > 1, panelRect.height > 1,
              targetRect.width > 1, targetRect.height > 1 else { return false }

        // 已经在收起中就不要叠第二张快照。
        guard snapshot == nil else { return false }

        guard let shot = window.resizableSnapshotView(
            from: panelRect,
            afterScreenUpdates: false,
            withCapInsets: .zero
        ) else { return false }

        shot.frame = panelRect
        shot.isUserInteractionEnabled = true
        shot.layer.masksToBounds = true
        shot.layer.cornerRadius = startRadius
        shot.layer.cornerCurve = .continuous
        shot.accessibilityElementsHidden = true
        window.addSubview(shot)
        snapshot = shot

        let target = clamped(targetRect, in: window.bounds)
        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: UICubicTimingParameters(
                controlPoint1: CGPoint(x: 0.3, y: 0.2),
                controlPoint2: CGPoint(x: 0.3, y: 1.0)
            )
        )
        animator.addAnimations {
            shot.frame = target
            shot.layer.cornerRadius = 28
        }
        animator.addCompletion { [weak self, weak shot] _ in
            shot?.removeFromSuperview()
            if self?.snapshot === shot { self?.snapshot = nil }
            self?.animator = nil
            completion()
        }
        self.animator = animator
        animator.startAnimation()
        return true
    }

    func cancel() {
        animator?.stopAnimation(true)
        animator = nil
        snapshot?.removeFromSuperview()
        snapshot = nil
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
