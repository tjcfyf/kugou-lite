import SwiftUI
import UIKit

@main
struct KugouLiteApp: App {
    init() {
        UITableView.appearance().backgroundColor = .clear
        UITableView.appearance().separatorColor = .clear
        UIScrollView.appearance().backgroundColor = .clear

        // 导航栏改成 Apple Music 式的磨砂玻璃：保留背景模糊，但去掉
        // 系统默认的不透明黑底和分割线，滚动时内容从玻璃下面经过。
        let navigationAppearance = UINavigationBarAppearance()
        // iOS 27 的导航栏在顶部是透明的，只有内容滚到其下方时才出现渐变磨砂。
        // 真正的模糊由 GradientNavigationBlur 安装；这里不再叠一条永久材质带，
        // 否则大标题下面会始终有一条与纸面底色不同的 44pt 灰条。
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.backgroundEffect = nil
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
    // 播放页首次打开后常驻在视图树里，收起只隐藏不销毁。
    // 否则 snapshot 刚好落到迷你封面那一帧时，SwiftUI 会同步拆掉整页
    // 歌词/材质并重算 Root 布局，主线程被占住一帧，表现就是「卡一下，
    // 然后才变成圆形旋转」。常驻后收起结束不再有这次拆除。
    @State private var isPlayerOpen = false
    @State private var tab = 0
    // 播放页转场由 Root 统一驱动：Apple Music 式整页 sheet 上滑/下滑。
    @State private var playerProgress: CGFloat = 0
    @State private var isPlayerClosing = false
    // 快照收起期间只把播放页隐藏，不立即销毁；否则 SwiftUI 在动画第一帧
    // 同步拆除整页歌词/材质，会阻塞主线程，表现就是只跳几帧的 PPT 式收起。
    @State private var hidePlayerForCollapse = false
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

                searchTab
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(tab == 2 ? 1 : 0)
                    .allowsHitTesting(tab == 2)
                    .zIndex(tab == 2 ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 三个 tab 常驻，切换只做透明度交叉淡入。不要加 scale/offset：
            // NavigationView 缩放后上下会露出窗口黑底，切换那 0.5 秒就是两条黑边。
            .animation(Motion.tabSwitch, value: tab)

            AppleMusicFloatingChrome(tab: $tab, onOpenPlayer: { openPlayer() })
                .zIndex(10)

            // 播放页直接作为 Root 的覆盖层，不走 UIKit fullScreenCover。
            // 这样 tab 切换不会触发系统 presentation，也就不会闪一次播放页。
            //
            // Apple Music 式播放页：整页 sheet 从底部上滑；收起由整页快照
            // 下滑带出，不再从迷你封面长出来，也不做封面飞行。
            if showPlayer {
                PlayerSheetFrame(progress: playerProgress) {
                    NowPlayingView(
                        panelProgress: $playerProgress,
                        panelOrigin: .zero,
                        onClose: { closePlayer() },
                        onInteractiveDismissBegan: { self.beginInteractiveDismiss() },
                        onInteractiveDismissChanged: { progress in
                            self.updateInteractiveDismiss(progress)
                        },
                        onInteractiveDismissEnded: { shouldClose in
                            self.endInteractiveDismiss(shouldClose)
                        },
                        progressPublisher: PlayerEngine.shared.playbackProgress.$time.eraseToAnyPublisher(),
                        isVisible: isPlayerOpen
                    )
                }
                .opacity(hidePlayerForCollapse ? 0 : 1)
                .allowsHitTesting(isPlayerOpen && !isPlayerClosing)
                .zIndex(30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppBackground().ignoresSafeArea())
        .overlay(alignment: .top) {
            ToastOverlay()
        }
        .preferredColorScheme(resolvedScheme)
        .accentColor(Theme.accent)
        .background(
            SystemSchemeProbe(scheme: $systemScheme)
                .frame(width: 1, height: 1)
        )
        .onAppear { applyInterfaceStyle() }
        .onChange(of: tab) { value in
            if value != 2 {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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

    /// 播放页展开：Apple Music 式整页 sheet，从屏幕底部滑上来。
    private func openPlayer() {
        guard !isPlayerOpen, !isPlayerClosing else { return }
        playerProgress = 0
        isPlayerOpen = true
        // 首次打开才创建视图；之后的打开直接复用已经挂载的 NowPlayingView。
        if !showPlayer {
            showPlayer = true
        }
        hidePlayerForCollapse = false

        DispatchQueue.main.async {
            // 和 HalfSheet 共用同一组面板弹簧，连续开关时速度可以互相接续。
            withAnimation(M3Motion.panelExpand) {
                playerProgress = 1
            }
        }
    }

    /// 跟手拖动开始：用当前播放页的快照接管画面，SwiftUI 页面只隐藏不销毁。
    private func beginInteractiveDismiss() -> Bool {
        guard isPlayerOpen, showPlayer, !isPlayerClosing else { return false }
        let screen = UIScreen.main.bounds
        let fullRect = CGRect(origin: .zero, size: screen.size)
        guard PlayerCollapseTransition.shared.beginInteractive(
            from: fullRect,
            screen: screen.size
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
                    // 常驻视图：只把播放页藏起来，不销毁视图树。
                    // 这样落到底栏封面时不会因为 Root 拆除整页而卡一帧。
                    self.playerProgress = 0
                    self.hidePlayerForCollapse = true
                    self.isPlayerOpen = false
                    self.isPlayerClosing = false
                }
            )
            if !handled {
                PlayerCollapseTransition.shared.cancel()
                hidePlayerForCollapse = true
                isPlayerClosing = false
                isPlayerOpen = false
                playerProgress = 0
            }
        } else {
            let handled = PlayerCollapseTransition.shared.finishInteractive(
                to: 1,
                duration: 0.28,
                completion: {
                    self.hidePlayerForCollapse = false
                    self.playerProgress = 1
                    self.isPlayerOpen = true
                    self.isPlayerClosing = false
                }
            )
            if !handled {
                PlayerCollapseTransition.shared.cancel()
                hidePlayerForCollapse = false
                playerProgress = 1
                isPlayerOpen = true
                isPlayerClosing = false
            }
        }
    }

    /// 播放页收起：260ms panelCollapse，反向缩回底栏圆盘。
    /// NowPlaying 不再自己滑整页，Root 的窗口形变就是唯一的收起动画。
    private func closePlayer() {
        guard isPlayerOpen, showPlayer, !isPlayerClosing else { return }
        isPlayerClosing = true

        let screen = UIScreen.main.bounds
        let startRect = CGRect(origin: .zero, size: screen.size)

        // 关键：收起不再让 SwiftUI 逐帧重排整页。先裁一张当前面板快照，
        // 用 UIViewPropertyAnimator 只动这一层静态图片；SwiftUI 页面立即摘除。
        if PlayerCollapseTransition.shared.begin(
            from: startRect,
            duration: 0.30,
            completion: {
                // 播放页常驻视图树，收起结束只隐藏，不做同步销毁。
                self.playerProgress = 0
                self.hidePlayerForCollapse = true
                self.isPlayerOpen = false
                self.isPlayerClosing = false
            }
        ) {
            // 快照期间先把整页隐藏，SwiftUI 保留视图树和已渲染图层。
            hidePlayerForCollapse = true
            return
        }

        // 快照失败时回退到旧路径，至少保证功能可用。
        withAnimation(M3Motion.panelCollapse) {
            playerProgress = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            playerProgress = 0
            hidePlayerForCollapse = true
            isPlayerOpen = false
            isPlayerClosing = false
        }
    }

    private var discoverTab: some View {
        DiscoverTab(isSearching: .constant(false),
                    onOpenPlayer: { openPlayer() },
                    onOpenProfile: { tab = 1 })
            .background(AppBackground().ignoresSafeArea())
    }

    private var profileTab: some View {
        NavigationView {
            ProfileView(onOpenPlayer: { openPlayer() })
                .navigationTitle("资料库")
                .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
        .background(AppBackground().ignoresSafeArea())
    }

    private var searchTab: some View {
        SearchTab(onOpenPlayer: { openPlayer() })
            .background(AppBackground().ignoresSafeArea())
    }
}


private struct DiscoverTab: View {
    @Binding var isSearching: Bool
    let onOpenPlayer: () -> Void
    let onOpenProfile: () -> Void

    @StateObject private var model = SearchModel()
    @StateObject private var recommendModel = RecommendModel()
    @ObservedObject private var userProfile = UserProfileStore.shared

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
            .navigationTitle("主页")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onOpenProfile()
                    } label: {
                        UserAvatarView(url: userProfile.profile.flatMap { $0.avatarURL }.flatMap(URL.init(string:)),
                                       size: 30,
                                       borderWidth: 0.6)
                    }
                    .buttonStyle(AppleMusicPressStyle())
                    .accessibilityLabel("账号与资料库")
                }
            }
            .task { await recommendModel.load() }
            .task { await userProfile.refresh() }
        }
        .navigationViewStyle(.stack)
    }
}


private struct SearchTab: View {
    let onOpenPlayer: () -> Void
    @StateObject private var searchModel = SearchModel()

    var body: some View {
        NavigationView {
            SearchPageView(searchModel: searchModel) { song in
                PlayerEngine.shared.play(song, in: searchModel.songs)
                onOpenPlayer()
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }
}

private struct ToastOverlay: View {
    @State private var toast: String?

    var body: some View {
        Group {
            if let toast {
                ToastView(text: toast)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.98))
                        )
                    )
            }
        }
        .animation(Motion.standard, value: toast)
        .onAppear { toast = PlayerEngine.shared.toast }
        .onReceive(PlayerEngine.shared.$toast) { toast = $0 }
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
