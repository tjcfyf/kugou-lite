import SwiftUI
import UIKit

@main
struct KugouLiteApp: App {
    init() {
        UITableView.appearance().backgroundColor = .clear
        UITableView.appearance().separatorColor = .clear
        UIScrollView.appearance().backgroundColor = .clear

        // 导航栏改成透明，不再用系统不透明黑底；页面自己铺专辑色背景。
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.backgroundColor = .clear
        navigationAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
    }
    @StateObject private var player = PlayerEngine.shared
    @StateObject private var auth = AuthStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(auth)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var showPlayer = false
    @State private var showSettings = false
    @State private var tab = 0
    // 播放页转场由 Root 统一驱动：以底栏播放封面圆盘为起点，
    // 按 MD3Music 的 PlayerPanelFrame 几何展开/收回。
    @State private var miniPlayerFrame: CGRect = .zero
    @State private var playerOrigin: CGRect = .zero
    @State private var playerProgress: CGFloat = 0
    @State private var isPlayerClosing = false
    // 快照收起期间只把播放页隐藏，不立即销毁；否则 SwiftUI 在动画第一帧
    // 同步拆除整页歌词/材质，会阻塞主线程，表现就是只跳几帧的 PPT 式收起。
    @State private var hidePlayerForCollapse = false
    @State private var isSearching = false
    @AppStorage(Preferences.themeModeKey) private var themeRaw = AppTheme.system.rawValue
    @State private var systemScheme: ColorScheme = UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light

    private var resolvedScheme: ColorScheme? {
        switch AppTheme(rawValue: themeRaw) ?? .system {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // 常驻主题背景：两个 tab 交叉淡入时不会露出底层黑色。
            AppBackground()
                .allowsHitTesting(false)
                .zIndex(-1)

            ZStack {
                discoverTab
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(tab == 0 ? 1 : 0)
                    .allowsHitTesting(tab == 0)
                    .zIndex(tab == 0 ? 1 : 0)

                profileTab
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(tab == 1 ? 1 : 0)
                    .allowsHitTesting(tab == 1)
                    .zIndex(tab == 1 ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(M3Motion.expressive, value: tab)

            FloatingTabBar(tab: $tab, onOpenPlayer: { openPlayer() })
                .opacity(isSearching ? 0 : 1)
                .offset(y: isSearching ? 64 : 0)
                .scaleEffect(isSearching ? 0.94 : 1, anchor: .bottom)
                .allowsHitTesting(!isSearching)
                .animation(isSearching ? M3Motion.chromeSink : M3Motion.chromeRise, value: isSearching)

            // 播放页直接作为 Root 的覆盖层，不走 UIKit fullScreenCover。
            // 这样 tab 切换不会触发系统 presentation，也就不会闪一次播放页。
            //
            // 1:1 移植 MD3Music 的 DraggablePlayerRoute：
            // 以外层底栏播放封面圆盘为 originRect，整页按 400ms panelExpand
            // 从 56pt 圆角窗口长到全屏；收起 260ms panelCollapse 反向缩回。
            // 不做 15% 位移/淡入的退化，也不给播放页内部另叠一层入场动画。
            if showPlayer {
                PlayerPanelFrame(
                    progress: playerProgress,
                    originRect: playerOrigin,
                    originRadius: 28
                ) {
                    NowPlayingView(
                        panelProgress: $playerProgress,
                        panelOrigin: playerOrigin,
                        onClose: { closePlayer() },
                        onInteractiveDismissBegan: { self.beginInteractiveDismiss() },
                        onInteractiveDismissChanged: { progress in
                            self.updateInteractiveDismiss(progress)
                        },
                        onInteractiveDismissEnded: { shouldClose in
                            self.endInteractiveDismiss(shouldClose)
                        }
                    )
                }
                .opacity(hidePlayerForCollapse ? 0 : 1)
                .allowsHitTesting(!isPlayerClosing)
                .zIndex(30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground().ignoresSafeArea())
        .overlay(alignment: .top) {
            ToastOverlay()
        }
        .onPreferenceChange(MiniPlayerFramePreferenceKey.self) { rect in
            if rect.width > 1, rect.height > 1 {
                miniPlayerFrame = rect
            }
        }
        .preferredColorScheme(resolvedScheme)
        .accentColor(Theme.accent)
        .background(
            SystemSchemeProbe(scheme: $systemScheme)
                .frame(width: 1, height: 1)
        )
        .onAppear { applyInterfaceStyle() }
        .onChange(of: tab) { value in
            if value != 0 {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                isSearching = false
            }
        }
        .onChange(of: themeRaw) { _ in applyInterfaceStyle() }
        .onOpenURL { url in
            _ = QQSDKLogin.handleOpen(url)
        }
        .task(id: auth.isLoggedIn) {
            if auth.isLoggedIn {
                await LibraryStore.shared.refreshFavorites(force: true)
            } else {
                LibraryStore.shared.resetFavorites()
            }
        }
    }

    private func applyInterfaceStyle() {
        let style: UIUserInterfaceStyle
        switch AppTheme(rawValue: themeRaw) ?? .system {
        case .system: style = .unspecified
        case .dark: style = .dark
        case .light: style = .light
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
                window.rootViewController?.view.backgroundColor = .clear
                window.backgroundColor = UIColor(named: "Background")
            }
        }
    }

    /// 播放页展开：以底栏播放封面圆盘为起点，400ms 强 S 型曲线长到全屏。
    /// 不叠加 15% 位移/根层淡入；几何、页面淡入、封面飞行全部由
    /// PlayerPanelFrame + NowPlayingView 按同一 progress 驱动。
    private func openPlayer() {
        guard !showPlayer, !isPlayerClosing else { return }
        let screen = UIScreen.main.bounds
        let fallback = CGRect(
            x: screen.midX - 28,
            y: screen.maxY - 92,
            width: 56,
            height: 56
        )
        playerOrigin = (miniPlayerFrame.width > 1 && miniPlayerFrame.height > 1)
            ? miniPlayerFrame
            : fallback
        playerProgress = 0
        hidePlayerForCollapse = false
        showPlayer = true

        DispatchQueue.main.async {
            withAnimation(M3Motion.panelExpand) {
                playerProgress = 1
            }
        }
    }

    /// 跟手拖动开始：用当前播放页的快照接管画面，SwiftUI 页面只隐藏不销毁。
    private func beginInteractiveDismiss() -> Bool {
        guard showPlayer, !isPlayerClosing else { return false }
        let screen = UIScreen.main.bounds
        let origin = (playerOrigin.width > 1 && playerOrigin.height > 1)
            ? playerOrigin
            : CGRect(x: screen.midX - 28,
                     y: screen.maxY - 92,
                     width: 56,
                     height: 56)
        let fullRect = PlayerPanelGeometry.rect(progress: 1, origin: origin, screen: screen.size)
        guard PlayerCollapseTransition.shared.beginInteractive(
            from: fullRect,
            origin: origin,
            screen: screen.size,
            startRadius: 0
        ) else { return false }
        hidePlayerForCollapse = true
        return true
    }

    private func updateInteractiveDismiss(_ progress: CGFloat) {
        PlayerCollapseTransition.shared.updateInteractive(progress: progress)
    }

    /// 松手：shouldClose=true 送到迷你播放器；false 送回全屏并恢复实时页面。
    private func endInteractiveDismiss(_ shouldClose: Bool) {
        isPlayerClosing = true
        if shouldClose {
            let handled = PlayerCollapseTransition.shared.finishInteractive(
                to: 0,
                duration: 0.28,
                completion: {
                    self.showPlayer = false
                    self.playerProgress = 0
                    self.hidePlayerForCollapse = false
                    self.isPlayerClosing = false
                }
            )
            if !handled {
                PlayerCollapseTransition.shared.cancel()
                hidePlayerForCollapse = false
                isPlayerClosing = false
                closePlayer()
            }
        } else {
            let handled = PlayerCollapseTransition.shared.finishInteractive(
                to: 1,
                duration: 0.28,
                completion: {
                    self.hidePlayerForCollapse = false
                    self.playerProgress = 1
                    self.isPlayerClosing = false
                }
            )
            if !handled {
                PlayerCollapseTransition.shared.cancel()
                hidePlayerForCollapse = false
                playerProgress = 1
                isPlayerClosing = false
            }
        }
    }

    /// 播放页收起：260ms panelCollapse，反向缩回底栏圆盘。
    /// NowPlaying 不再自己滑整页，Root 的窗口形变就是唯一的收起动画。
    private func closePlayer() {
        guard showPlayer, !isPlayerClosing else { return }
        isPlayerClosing = true

        let screen = UIScreen.main.bounds
        let origin = (playerOrigin.width > 1 && playerOrigin.height > 1)
            ? playerOrigin
            : CGRect(x: screen.midX - 28,
                     y: screen.maxY - 92,
                     width: 56,
                     height: 56)
        let progress = min(max(playerProgress, 0), 1)
        let startRect = PlayerPanelGeometry.rect(progress: progress, origin: origin, screen: screen.size)
        let startRadius = max(0, 28 * (1 - progress))

        // 关键：收起不再让 SwiftUI 逐帧重排整页。先裁一张当前面板快照，
        // 用 UIViewPropertyAnimator 只动这一层静态图片；SwiftUI 页面立即摘除。
        if PlayerCollapseTransition.shared.begin(
            from: startRect,
            to: origin,
            startRadius: startRadius,
            duration: 0.28,
            completion: {
                // 快照动画已经结束，这时才拆播放页；拆除发生在动画之后，
                // 不会阻塞刚才那 280ms 的帧。
                self.showPlayer = false
                self.playerProgress = 0
                self.hidePlayerForCollapse = false
                self.isPlayerClosing = false
            }
        ) {
            // 不要在这里 showPlayer = false。先把整页隐藏，让 SwiftUI 保留
            // 视图树和已经渲染好的图层；快照动画结束后再销毁。
            hidePlayerForCollapse = true
            return
        }

        // 快照失败时回退到旧路径，至少保证功能可用。
        withAnimation(M3Motion.panelCollapse) {
            playerProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            showPlayer = false
            playerProgress = 0
            isPlayerClosing = false
        }
    }

    private var discoverTab: some View {
        DiscoverTab(isSearching: $isSearching, onOpenPlayer: { openPlayer() })
            .background(AppBackground().ignoresSafeArea())
    }

    private var profileTab: some View {
        NavigationView {
            ProfileView(onOpenPlayer: { openPlayer() })
                .navigationTitle("我的")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("设置")
                    }
                }
        }
        .navigationViewStyle(.stack)
        .background(AppBackground().ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(PlayerEngine.shared)
                .environmentObject(auth)
        }
    }
}


private struct DiscoverTab: View {
    @Binding var isSearching: Bool
    let onOpenPlayer: () -> Void

    @StateObject private var model = SearchModel()
    @StateObject private var recommendModel = RecommendModel()

    var body: some View {
        NavigationView {
            RecommendView(
                model: recommendModel,
                searchModel: model,
                isSearching: $isSearching,
                onSelect: { song, list in
                    PlayerEngine.shared.play(song, in: list)
                    onOpenPlayer()
                },
                onSelectSearch: { song in
                    PlayerEngine.shared.play(song, in: model.songs)
                    onOpenPlayer()
                },
                onOpenPlayer: onOpenPlayer
            )
            .navigationBarHidden(true)
            .task { await recommendModel.load() }
        }
        .navigationViewStyle(.stack)
    }
}

private struct ToastOverlay: View {
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        Group {
            if let toast = player.toast {
                ToastView(text: toast)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.98))
                        )
                    )
            }
        }
        .animation(.easeOut(duration: 0.24), value: player.toast)
    }
}

private final class SchemeProbeController: UIViewController {
    var onChange: ((UIUserInterfaceStyle) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        report()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        report()
    }

    private func report() {
        onChange?(traitCollection.userInterfaceStyle)
    }
}

private struct SystemSchemeProbe: UIViewControllerRepresentable {
    @Binding var scheme: ColorScheme

    final class Coordinator {
        var parent: SystemSchemeProbe
        init(parent: SystemSchemeProbe) { self.parent = parent }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> SchemeProbeController {
        let controller = SchemeProbeController()
        controller.onChange = { style in
            let value: ColorScheme = style == .dark ? .dark : .light
            DispatchQueue.main.async {
                if context.coordinator.parent.scheme != value {
                    context.coordinator.parent.scheme = value
                }
            }
        }
        return controller
    }

    func updateUIViewController(_ controller: SchemeProbeController, context: Context) {
        context.coordinator.parent = self
    }
}
