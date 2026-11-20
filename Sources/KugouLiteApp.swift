import SwiftUI
import UIKit

@main
struct KugouLiteApp: App {
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
    @StateObject private var model = SearchModel()
    @StateObject private var recommendModel = RecommendModel()
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var auth: AuthStore
    @State private var showPlayer = false
    @State private var tab = 0
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
        TabView(selection: $tab) {
            profileTab
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .tag(0)

            recommendTab
                .tabItem { Label("发现", systemImage: "sparkles") }
                .tag(1)

            searchTab
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(2)
        }
        .accentColor(Theme.accent)
        .sheet(isPresented: $showPlayer) {
            NowPlayingView()
                .environmentObject(player)
        }
        .overlay(alignment: .top) {
            if let toast = player.toast {
                ToastView(text: toast)
            }
        }
        .animation(.easeOut(duration: 0.22), value: player.toast)
        .preferredColorScheme(resolvedScheme)
        .background(
            SystemSchemeProbe(scheme: $systemScheme)
                .frame(width: 1, height: 1)
        )
        .onAppear { applyInterfaceStyle() }
        .onChange(of: themeRaw) { _ in applyInterfaceStyle() }
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

    private var searchTab: some View {
        NavigationView {
            SearchView(
                model: model,
                onSelect: { song in
                    player.play(song, in: model.songs)
                    showPlayer = true
                },
                onOpenPlayer: { showPlayer = true }
            )
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索歌曲、歌手"
            )
            .onChange(of: model.query) { _ in model.schedule() }
            .onSubmit(of: .search) { model.submit() }
        }
        .navigationViewStyle(.stack)
    }

    private var recommendTab: some View {
        NavigationView {
            RecommendView(
                model: recommendModel,
                onSelect: { song, list in
                    player.play(song, in: list)
                    showPlayer = true
                },
                onOpenPlayer: { showPlayer = true }
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
            .task { await recommendModel.load() }
        }
        .navigationViewStyle(.stack)
    }

    private var profileTab: some View {
        NavigationView {
            ProfileView(onOpenPlayer: { showPlayer = true })
                .navigationTitle("我的")
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
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
