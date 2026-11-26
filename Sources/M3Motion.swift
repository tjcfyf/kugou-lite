import SwiftUI

/// 全局动效常量。按 Emil Kowalski 的规范收敛为三档：
/// 1. 交互反馈：只动 transform / opacity，100–160ms；
/// 2. 页面内状态：critically damped 弹簧，无过冲；
/// 3. 全屏 sheet：0.38–0.46s，只在用户拖拽释放时保留极轻的动量。
///
/// 不再使用响应 0.5s 以上、阻尼 0.8 以下的弹簧；这类参数会让每次
/// 页面切换都像在“表演”，连续操作时会显得慢且不可中断。
enum M3Motion {
    /// 通用内容显隐、tab 图标颜色。
    static let expressive = Animation.spring(response: 0.32, dampingFraction: 1.0, blendDuration: 0.08)
    /// 大块内容切换、页面级状态变化。
    static let emphasized = Animation.spring(response: 0.40, dampingFraction: 1.0, blendDuration: 0.10)

    /// 播放页展开：从底部整页上滑，临界阻尼，不做过冲。
    static let panelExpand = Animation.spring(response: 0.42, dampingFraction: 1.0, blendDuration: 0.10)
    /// 拖拽取消/回弹：跟手结束后快速归位。
    static let panelSettle = Animation.spring(response: 0.28, dampingFraction: 0.92, blendDuration: 0.08)
    /// 播放页收起：比展开略快，避免整页下滑拖泥带水。
    static let panelCollapse = Animation.spring(response: 0.34, dampingFraction: 1.0, blendDuration: 0.08)

    /// 底栏显隐。
    static let chromeRise = Animation.spring(response: 0.30, dampingFraction: 1.0, blendDuration: 0.08)
    static let chromeSink = Animation.spring(response: 0.30, dampingFraction: 1.0, blendDuration: 0.08)

    /// 底栏形态交棒。
    static let barFormMorph = Animation.spring(response: 0.30, dampingFraction: 1.0, blendDuration: 0.08)
}

/// 常用交互弹簧，按场景拆分，避免每个页面各写一套 duration。
enum Motion {
    /// 按压反馈，手指按下/抬起必须立刻有回应。
    static let tap = Animation.easeOut(duration: 0.12)
    /// 小范围状态变化：收藏、播放/暂停图标、搜索框聚焦。
    static let quick = Animation.spring(response: 0.26, dampingFraction: 1.0, blendDuration: 0.06)
    /// 列表增删、卡片展开、模式切换。
    static let standard = Animation.spring(response: 0.34, dampingFraction: 1.0, blendDuration: 0.08)
    /// 封面/大面积颜色过渡。
    static let gentle = Animation.easeInOut(duration: 0.32)
    /// 底栏 tab 图标选中态。
    static let tab = Animation.spring(response: 0.28, dampingFraction: 0.94, blendDuration: 0.06)

    /// 整页级交叉淡入。两个视图同时存在时必须只动透明度，
    /// 否则 NavigationView 的边界会在过渡中露出窗口黑底。
    static let silky = Animation.easeOut(duration: 0.22)

    /// Apple Music 的 tab 切换是短促的交叉淡入，不做整页弹簧。
    static let tabSwitch = Animation.easeOut(duration: 0.18)
    /// 浮动底栏展开/收起的胶囊形变；比整页弹簧快一档。
    static let chromeMorph = Animation.spring(response: 0.30, dampingFraction: 1.0, blendDuration: 0.08)
    /// 全屏详情页从卡片/底部进入时的统一步调。
    static let pagePresent = Animation.spring(response: 0.38, dampingFraction: 1.0, blendDuration: 0.10)
}
