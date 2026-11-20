import SwiftUI
import UIKit

@main
struct KugouLiteApp: App {
    init() {
        UITableView.appearance().backgroundColor = .clear
        UITableView.appearance().separatorColor = .clear
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
            .animation(.easeInOut(duration: 0.26), value: tab)

            FloatingTabBar(tab: $tab, onOpenPlayer: { showPlayer = true })
                .opacity(isSearching ? 0 : 1)
                .offset(y: isSearching ? 64 : 0)
                .allowsHitTesting(!isSearching)
                .animation(.easeInOut(duration: 0.2), value: isSearching)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showPlayer) {
            NowPlayingView()
                .environmentObject(PlayerEngine.shared)
        }
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
            }
        }
    }

    private var discoverTab: some View {
        DiscoverTab(isSearching: $isSearching, onOpenPlayer: { showPlayer = true })
    }

    private var profileTab: some View {
        NavigationView {
            ProfileView(onOpenPlayer: { showPlayer = true })
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
            }
        }
        .animation(.easeOut(duration: 0.22), value: player.toast)
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
