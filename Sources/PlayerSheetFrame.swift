import SwiftUI

/// Apple Music 式全屏 sheet：整页从屏幕底部上滑，顶部圆角在打开过程中
/// 从 14pt 收到 0；收起时由 PlayerCollapseTransition 的整页快照反向滑出。
struct PlayerSheetFrame<Content: View>: View, Animatable {
    var progress: CGFloat
    let content: Content

    init(progress: CGFloat, @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.content = content()
    }

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let p = min(max(progress, 0), 1)
            let height = max(geo.size.height, 1)
            content
                .frame(width: geo.size.width, height: height)
                .environment(\.playerPanelProgress, p)
                .clipShape(RoundedRectangle(cornerRadius: 14 * (1 - p), style: .continuous))
                .offset(y: (1 - p) * height)
                .shadow(color: .black.opacity(0.24), radius: 18 * (1 - p), x: 0, y: -4)
        }
        .ignoresSafeArea()
    }
}
