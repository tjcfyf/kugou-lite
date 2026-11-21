import SwiftUI

/// Material 3 Expressive 运动常量（与 MD3Music-iOS 的 `M3ExpressiveMotion` 逐值对齐）。
///
/// 参考：
/// - `lib/core/theme/motion_constants.dart`
/// - `lib/modules/player/full_player_route.dart`
///
/// 这些曲线都是三次贝塞尔（两个控制点），SwiftUI 的 `.timingCurve(x1, y1, x2, y2)`
/// 与 Flutter 的 `Cubic(x1, y1, x2, y2)` 定义完全一致，可直接 1:1 复刻。
enum M3Motion {
    // MARK: - 基础时长

    /// M3 medium duration，对应 400ms。
    static let defaultDuration: Double = 0.40
    /// M3 long duration，对应 600ms。
    static let emphasisDuration: Double = 0.60

    // MARK: - 标准曲线

    /// `expressiveEasing = Cubic(0.05, 0.7, 0.1, 1.0)`
    /// 略带过冲的减速曲线，用于 tab 切换、卡片入场、内容显隐。
    static let expressive = Animation.timingCurve(
        0.05, 0.7, 0.1, 1.0,
        duration: defaultDuration
    )

    /// `emphasizedEasing = Cubic(0.2, 0.0, 0.0, 1.0)`
    /// M3 标准 emphasized，用于大型状态转换。
    static let emphasized = Animation.timingCurve(
        0.2, 0.0, 0.0, 1.0,
        duration: emphasisDuration
    )

    // MARK: - 播放页面板（FullPlayer）

    /// `kPlayerExpandDuration = 400ms`
    /// 从静止开始的展开：强 S 型，起步慢、中段最快、末端慢着陆。
    /// `panelExpandEasing = Cubic(0.52, 0.08, 0.3, 0.98)`
    static let panelExpand = Animation.timingCurve(
        0.52, 0.08, 0.3, 0.98,
        duration: 0.40
    )

    /// `kPlayerDragCancelDuration = 220ms`
    /// 起点是手指的续展 / 回弹：不能再用慢起步的 S 型，否则会有一次速度塌陷。
    /// `panelSettleEasing = Cubic(0.35, 0.1, 0.2, 1.0)`
    static let panelSettle = Animation.timingCurve(
        0.35, 0.1, 0.2, 1.0,
        duration: 0.22
    )

    /// `kPlayerCollapseDuration = 260ms`
    /// 面板收起：轻推起步、末端速度趋零。
    /// `panelCollapseEasing = Cubic(0.3, 0.2, 0.3, 1.0)`
    static let panelCollapse = Animation.timingCurve(
        0.3, 0.2, 0.3, 1.0,
        duration: 0.26
    )

    /// `kPlayerTapEntryOffsetRatio = 0.15`
    /// 点击进入时，抽屉上滑比例为屏幕高度的 15%。
    static let playerEntryOffsetRatio: CGFloat = 0.15

    // MARK: - 底栏 / 搜索栏显隐

    /// `chromeRiseEasing = Cubic(0.3, 0.0, 0.18, 1.0)`，260ms。
    static let chromeRise = Animation.timingCurve(
        0.3, 0.0, 0.18, 1.0,
        duration: 0.26
    )

    /// `chromeSinkEasing = Cubic(0.3, 0.2, 0.3, 1.0)`，260ms。
    static let chromeSink = Animation.timingCurve(
        0.3, 0.2, 0.3, 1.0,
        duration: 0.26
    )

    // MARK: - 底栏形态交棒

    /// `barFormMorphEasing = Cubic(0.2, 0.0, 0.0, 1.0)`。
    /// 可见形变前置完成，避免交棒那一刻还在动。
    static let barFormMorph = Animation.timingCurve(
        0.2, 0.0, 0.0, 1.0,
        duration: 0.26
    )
}
