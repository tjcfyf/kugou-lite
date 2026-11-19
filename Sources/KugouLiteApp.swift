import SwiftUI

@main
struct KugouLiteApp: App {
    @StateObject private var player = PlayerEngine.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(player)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @StateObject private var model = SearchModel()
    @EnvironmentObject private var player: PlayerEngine
    @State private var showPlayer = false

    var body: some View {
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
}
