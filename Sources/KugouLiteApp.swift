import SwiftUI

@main
struct KugouLiteApp: App {
    @StateObject private var player = PlayerEngine.shared
    @StateObject private var auth = AuthStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .environmentObject(auth)
                .preferredColorScheme(.dark)
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

    var body: some View {
        TabView(selection: $tab) {
            searchTab
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                .tag(0)

            recommendTab
                .tabItem { Label("发现", systemImage: "sparkles") }
                .tag(1)

            profileTab
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
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
            ProfileView()
                .navigationTitle("我的")
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
