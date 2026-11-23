import SwiftUI

/// 全局动效常量。应用整体按 Apple Music 的手感走：
/// 交互使用短弹簧，页面使用中长弹簧，收起使用略快的减速弹簧。
/// 原来的 Material 3 三次贝塞尔曲线全部替换掉，避免“先慢后快再停”的机械感。
enum M3Motion {
    /// 通用内容显隐、tab 图标颜色。
    static let expressive = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// 大块内容切换、页面级状态变化。
    static let emphasized = Animation.spring(response: 0.52, dampingFraction: 0.90)

    /// 播放页展开：从底部整页上滑，末端只留极小回弹。
    static let panelExpand = Animation.spring(response: 0.46, dampingFraction: 0.90)
    /// 拖拽取消/回弹：跟手结束后快速归位，不能有二次速度塌陷。
    static let panelSettle = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// 播放页收起：比展开略快，避免整页下滑拖泥带水。
    static let panelCollapse = Animation.spring(response: 0.36, dampingFraction: 0.90)

    /// 底栏显隐。
    static let chromeRise = Animation.spring(response: 0.34, dampingFraction: 0.88)
    static let chromeSink = Animation.spring(response: 0.34, dampingFraction: 0.92)

    /// 底栏形态交棒。
    static let barFormMorph = Animation.spring(response: 0.32, dampingFraction: 0.90)
}

/// 常用交互弹簧，按场景拆分，避免每个页面各写一套 duration。
enum Motion {
    /// 按压反馈，手指按下/抬起必须立刻有回应。
    static let tap = Animation.interactiveSpring(response: 0.22, dampingFraction: 0.80)
    /// 小范围状态变化：收藏、播放/暂停图标、搜索框聚焦。
    static let quick = Animation.spring(response: 0.30, dampingFraction: 0.86)
    /// 列表增删、卡片展开、模式切换。
    static let standard = Animation.spring(response: 0.40, dampingFraction: 0.88)
    /// 封面/大面积颜色过渡。
    static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.92)
    /// 底栏 tab 图标选中态。
    static let tab = Animation.spring(response: 0.30, dampingFraction: 0.78)
}
