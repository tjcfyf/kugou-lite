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

/// 播放页收起：页面只做轻微下移 + 淡出，真正缩向底栏的是「专辑图」。
///
/// 之前直接把整页快照 frame 缩到 56pt，视觉上就是一张完整播放页被压成
/// 窄条；现在拆成两层：
/// 1. pageShot：整页快照，保持原始尺寸，只下移和淡出；
/// 2. coverShot：从大封面矩形裁出的封面快照，单独按封面→迷你圆盘的路径缩小。
///
/// 两层都只改 UIKit 的 frame/alpha，不触发 SwiftUI 每帧 reflow，iOS 15
/// 上能稳定贴着手指走。最后 coverShot 落到迷你封面后再做 0.16s 交叉淡化，
/// 交给下面已经在旋转的 BottomArtwork。
final class PlayerCollapseTransition {
    static let shared = PlayerCollapseTransition()

    private var pageShot: UIView?
    private var coverShot: UIView?
    private var animator: UIViewPropertyAnimator?

    private var interactivePageRect: CGRect = .zero
    private var interactiveCoverStart: CGRect = .zero
    private var interactiveCoverTarget: CGRect = .zero
    private var interactiveScreen: CGSize = .zero
    private var isInteractive = false

    var isInteractiveActive: Bool { isInteractive }

    /// 点击关闭按钮 / 非交互收起。
    @discardableResult
    func begin(from panelRect: CGRect,
               to targetRect: CGRect,
               coverRect: CGRect?,
               startRadius: CGFloat,
               duration: TimeInterval,
               completion: @escaping () -> Void) -> Bool {
        guard pageShot == nil, coverShot == nil, !isInteractive,
              let page = makePageSnapshot(from: panelRect) else { return false }

        let startCover = normalizedCoverRect(coverRect, in: page.bounds)
        let targetCover = clamped(targetRect, in: page.superview?.bounds ?? page.frame)
        attach(page: page, coverRect: startCover)

        interactivePageRect = page.frame
        interactiveCoverStart = startCover ?? .zero
        interactiveCoverTarget = targetCover
        interactiveScreen = page.frame.size
        isInteractive = false

        let endPage = pageEndFrame(screen: interactiveScreen, travel: 0.10)
        let animator = makeAnimator(duration: duration) {
            page.frame = endPage
            if let cover = self.coverShot, startCover != nil {
                cover.frame = targetCover
                cover.layer.cornerRadius = targetCover.width / 2
            }
        } completion: { [weak self, weak page, weak cover = self.coverShot] _ in
            guard let self, let page else { return }
            self.animator = nil
            page.removeFromSuperview()
            if self.pageShot === page { self.pageShot = nil }
            guard let cover, cover.superview != nil else {
                self.coverShot = nil
                completion()
                return
            }
            self.finishCover(cover, completion: completion)
        }
        // page 的 alpha 在 UIViewPropertyAnimator 里是线性 1→0；为了让页面
        // 尽早让位给封面，另起一个更短的淡出，主 animator 仍然负责封面路径。
        page.alpha = 1
        self.animator = animator
        UIView.animate(withDuration: min(0.16, duration * 0.62),
                       delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState]) {
            page.alpha = 0
        }
        animator.startAnimation()
        return true
    }

    /// 开始跟手收起。页面仍然是全屏，封面快照必须从窗口里单独裁出来。
    @discardableResult
    func beginInteractive(from panelRect: CGRect,
                          origin: CGRect,
                          screen: CGSize,
                          coverRect: CGRect?,
                          startRadius: CGFloat) -> Bool {
        guard pageShot == nil, coverShot == nil, !isInteractive, !panelRect.isEmpty,
              let page = makePageSnapshot(from: panelRect) else { return false }

        let startCover = normalizedCoverRect(coverRect, in: page.bounds)
        let targetCover = clamped(origin, in: page.superview?.bounds ?? page.frame)
        attach(page: page, coverRect: startCover)

        interactivePageRect = page.frame
        interactiveCoverStart = startCover ?? .zero
        interactiveCoverTarget = targetCover
        interactiveScreen = screen
        isInteractive = true

        page.alpha = 1
        if let cover = coverShot, startCover != nil {
            cover.layer.cornerRadius = min(12, startCover!.width / 2)
        }
        return true
    }

    /// 跟手阶段每一帧只改快照 frame/alpha；不触发 SwiftUI 布局。
    func updateInteractive(progress: CGFloat) {
        guard isInteractive, let page = pageShot else { return }
        let p = min(max(progress, 0), 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        page.frame = pageFrame(progress: p)
        // 页面尽早淡出；它不再缩小，只下移，避免出现「小号播放页」。
        page.alpha = p * p * p

        if let cover = coverShot, !interactiveCoverStart.isEmpty {
            let rect = coverFrame(progress: p)
            cover.frame = rect
            cover.layer.cornerRadius = min(28, rect.width / 2)
        }

        CATransaction.commit()
    }

    /// 松手：progress=0 收进迷你播放器，progress=1 回到全屏。
    @discardableResult
    func finishInteractive(to progress: CGFloat,
                           duration: TimeInterval,
                           completion: @escaping () -> Void) -> Bool {
        guard isInteractive, let page = pageShot else { return false }
        isInteractive = false

        let p = min(max(progress, 0), 1)
        let closing = p < 0.999
        let endPage = closing
            ? pageEndFrame(screen: interactiveScreen, travel: 0.10)
            : interactivePageRect
        let endPageAlpha: CGFloat = closing ? 0 : 1

        let endCover: CGRect
        if closing {
            endCover = interactiveCoverTarget
        } else {
            endCover = interactiveCoverStart
        }

        let animator = makeAnimator(duration: duration) {
            page.frame = endPage
            if !closing {
                page.alpha = endPageAlpha
            }
            if let cover = self.coverShot, !self.interactiveCoverStart.isEmpty {
                cover.frame = endCover
                cover.layer.cornerRadius = min(28, endCover.width / 2)
            }
        } completion: { [weak self, weak page, weak cover = self.coverShot] _ in
            guard let self, let page else { return }
            self.animator = nil
            if closing {
                page.removeFromSuperview()
                if self.pageShot === page { self.pageShot = nil }
                guard let cover, cover.superview != nil else {
                    self.coverShot = nil
                    completion()
                    return
                }
                self.finishCover(cover, completion: completion)
            } else {
                page.removeFromSuperview()
                if self.pageShot === page { self.pageShot = nil }
                cover?.removeFromSuperview()
                if self.coverShot === cover { self.coverShot = nil }
                completion()
            }
        }
        self.animator = animator
        if closing {
            page.alpha = max(0, min(1, page.alpha))
            // 收尾阶段页面已经淡得差不多，这里直接把剩余部分压到 0，
            // 封面继续走完 0.28s，避免页面残影拖到最后。
            UIView.animate(withDuration: min(0.12, duration * 0.5),
                           delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                page.alpha = 0
            }
        }
        animator.startAnimation()
        return true
    }

    func cancel() {
        animator?.stopAnimation(true)
        animator = nil
        pageShot?.removeFromSuperview()
        coverShot?.removeFromSuperview()
        pageShot = nil
        coverShot = nil
        isInteractive = false
    }

    // MARK: - Snapshot

    private func makePageSnapshot(from rect: CGRect) -> UIView? {
        guard let window = keyWindow, rect.width > 1, rect.height > 1 else { return nil }
        guard let shot = window.resizableSnapshotView(
            from: rect,
            afterScreenUpdates: false,
            withCapInsets: .zero
        ) else { return nil }

        shot.frame = rect
        // 只做视觉层，触摸必须穿透到底栏/迷你播放器。
        shot.isUserInteractionEnabled = false
        shot.layer.masksToBounds = true
        shot.layer.cornerCurve = .continuous
        shot.accessibilityElementsHidden = true
        return shot
    }

    private func makeCoverSnapshot(from rect: CGRect) -> UIView? {
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
        shot.layer.cornerRadius = min(12, min(rect.width, rect.height) / 2)
        shot.accessibilityElementsHidden = true
        return shot
    }

    private func attach(page: UIView, coverRect: CGRect?) {
        guard let window = page.superview ?? keyWindow else { return }
        if page.superview == nil {
            window.addSubview(page)
        }
        pageShot = page

        if let coverRect, let cover = makeCoverSnapshot(from: coverRect) {
            window.addSubview(cover)
            coverShot = cover
        }
    }

    /// page 快照的起点是全屏；cover 快照的起点是播放页大封面。
    private func pageFrame(progress p: CGFloat) -> CGRect {
        let travel = min(interactivePageRect.height * 0.10, 90)
        return interactivePageRect.offsetBy(dx: 0, dy: (1 - p) * travel)
    }

    private func pageEndFrame(screen: CGSize, travel: CGFloat) -> CGRect {
        interactivePageRect.offsetBy(dx: 0, dy: min(screen.height * travel, 90))
    }

    private func coverFrame(progress p: CGFloat) -> CGRect {
        let start = interactiveCoverStart
        let end = interactiveCoverTarget
        return CGRect(
            x: start.minX + (end.minX - start.minX) * p,
            y: start.minY + (end.minY - start.minY) * p,
            width: start.width + (end.width - start.width) * p,
            height: start.height + (end.height - start.height) * p
        )
    }

    /// 快照落到迷你封面后不要瞬间移除。最后一帧如果硬切，视觉上就是
    /// 「卡一下，然后才出现圆形旋转封面」。这里用 0.16s 的轻微缩小 +
    /// 淡出，把静态封面交给下面已经在旋转的 BottomArtwork。
    private func finishCover(_ cover: UIView, completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
            animations: {
                cover.alpha = 0
                cover.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            },
            completion: { [weak self, weak cover] _ in
                cover?.removeFromSuperview()
                if self?.coverShot === cover { self?.coverShot = nil }
                completion()
            }
        )
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

    private func normalizedCoverRect(_ rect: CGRect?, in bounds: CGRect) -> CGRect? {
        guard let rect, rect.width > 1, rect.height > 1 else { return nil }
        let x = max(bounds.minX, min(rect.minX, bounds.maxX))
        let y = max(bounds.minY, min(rect.minY, bounds.maxY))
        let w = min(rect.width, bounds.maxX - x)
        let h = min(rect.height, bounds.maxY - y)
        guard w > 1, h > 1 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
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
