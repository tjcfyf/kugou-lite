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
    // 播放页转场由 Root 统一驱动：进入 400ms / 收起 260ms，与 MD3Music
    // 的 DraggablePlayerRoute 时长逐值对齐。
    @State private var playerOffset: CGFloat = 0
    @State private var playerOpacity: Double = 0
    @State private var isPlayerClosing = false
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
            // 转场复刻 MD3Music 的退化路径：点击进入时上滑 15% 屏高，
            // 400ms panelExpandEasing；收起 260ms panelCollapseEasing。
            // 不再叠 NowPlaying 内部的 entranceOffset，也不在根层再套
            // `.transition(.opacity)`，避免「位移 + 根层淡入 + 内容淡入」三层叠加。
            if showPlayer {
                NowPlayingView(onClose: { closePlayer() })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: playerOffset)
                    .opacity(playerOpacity)
                    .allowsHitTesting(!isPlayerClosing)
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
            if value != 0 {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                isSearching = false
            }
        }
        .onChange(of: themeRaw) { _ in applyInterfaceStyle() }
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

    /// 播放页展开：从屏幕下方 15% 处上滑，400ms 强 S 型曲线。
    /// 只让 Root 这一层做位移 + 淡入，NowPlaying 内部不再叠第二层 entranceOffset。
    private func openPlayer() {
        guard !showPlayer, !isPlayerClosing else { return }
        let height = UIScreen.main.bounds.height
        playerOpacity = 0
        playerOffset = height * M3Motion.playerEntryOffsetRatio
        showPlayer = true

        // 先让第一帧以 0 透明度、15% 下移落位，再启动补间，
        // 避免 SwiftUI 把插入瞬间和动画合并成一帧造成闪跳。
        DispatchQueue.main.async {
            withAnimation(M3Motion.panelExpand) {
                playerOffset = 0
                playerOpacity = 1
            }
        }
    }

    /// 播放页收起：260ms panelCollapse。NowPlaying 内部只负责前景下滑，
    /// Root 这一层同步把整页淡出并在 260ms 后移除，避免背景磨砂层突然消失闪一下。
    private func closePlayer() {
        guard showPlayer, !isPlayerClosing else { return }
        isPlayerClosing = true
        withAnimation(M3Motion.panelCollapse) {
            playerOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            showPlayer = false
            playerOffset = 0
            playerOpacity = 0
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
