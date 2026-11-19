import SwiftUI

@MainActor
final class RecommendModel: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?

    func load(force: Bool = false) async {
        if !force, !songs.isEmpty { return }
        isLoading = true
        message = nil
        do {
            let list = try await KGService.recommend()
            songs = list
            isLoading = false
            if list.isEmpty { message = "今天还没有推荐，登录后再试" }
        } catch {
            isLoading = false
            message = (error as? LocalizedError)?.errorDescription ?? "推荐加载失败"
        }
    }
}

struct RecommendView: View {
    @ObservedObject var model: RecommendModel
    @EnvironmentObject private var player: PlayerEngine
    let onSelect: (Song, [Song]) -> Void
    let onOpenPlayer: () -> Void

    @State private var recent: [Song] = Preferences.recentSongs
    @State private var favorites: [Song] = Preferences.favorites
    @State private var playlists: [CloudPlaylist] = []
    @State private var playlistTarget: CloudPlaylist?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }

                if let message = model.message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                }

                if !playlists.isEmpty {
                    SectionTitle(title: "我的歌单", subtitle: "\(playlists.count) 个")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(playlists) { playlist in
                                Button { playlistTarget = playlist } label: {
                                    PlaylistCard(playlist: playlist)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                    }
                }

                if !model.songs.isEmpty {
                    SectionTitle(title: "每日推荐", subtitle: "\(model.songs.count) 首")
                    ForEach(model.songs) { song in
                        Button {
                            onSelect(song, model.songs)
                        } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }

                if !favorites.isEmpty {
                    SectionTitle(title: "我的收藏", subtitle: nil)
                    ForEach(favorites) { song in
                        Button {
                            onSelect(song, favorites)
                        } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }

                if !recent.isEmpty {
                    SectionTitle(title: "最近播放", subtitle: nil)
                    ForEach(recent) { song in
                        Button {
                            onSelect(song, recent)
                        } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let song = player.current {
                MiniPlayer(song: song, onOpen: onOpenPlayer)
            }
        }
        .onAppear {
            recent = Preferences.recentSongs
            favorites = Preferences.favorites
        }
        .onReceive(NotificationCenter.default.publisher(for: .kgRecentChanged)) { _ in
            recent = Preferences.recentSongs
            favorites = Preferences.favorites
        }
        .task {
            guard playlists.isEmpty, AuthStore.shared.isLoggedIn else { return }
            playlists = (try? await KGService.playlists()) ?? []
        }
        .sheet(item: $playlistTarget) { playlist in
            PlaylistDetailSheet(playlist: playlist) { song, list in
                playlistTarget = nil
                onSelect(song, list)
                onOpenPlayer()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("发现")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                Text("每天一组，按你的口味来")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            if let first = model.songs.first {
                Button {
                    onSelect(first, model.songs)
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.accent)
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
            }
            Button {
                Task { await model.load(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct PlaylistCard: View {
    let playlist: CloudPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Theme.card)
                if let url = playlist.cover.flatMap(URL.init(string:)) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .frame(width: 108, height: 108)
            Text(playlist.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 108, alignment: .leading)
            Text("\(playlist.count) 首")
                .font(.system(size: 10))
                .foregroundColor(Theme.secondaryText)
        }
    }
}

struct PlaylistDetailSheet: View {
    let playlist: CloudPlaylist
    let onSelect: (Song, [Song]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var message = ""

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if loading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).padding(.top, 30)
                    } else if !message.isEmpty {
                        Text(message).font(.system(size: 13)).foregroundColor(Theme.secondaryText).padding(.top, 24)
                    }
                    ForEach(songs) { song in
                        Button {
                            dismiss()
                            onSelect(song, songs)
                        } label: {
                            SongRow(song: song)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(playlist.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !songs.isEmpty {
                        Button {
                            dismiss()
                            onSelect(songs[0], songs)
                        } label: { Label("播放全部", systemImage: "play.fill") }
                    }
                }
            }
        }
        .task {
            do {
                songs = try await KGService.playlistSongs(id: playlist.id)
                loading = false
                if songs.isEmpty { message = "这个歌单是空的，或者没有读取权限" }
            } catch {
                loading = false
                message = (error as? LocalizedError)?.errorDescription ?? "歌单加载失败"
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerEngine
    @State private var quality: AudioQuality = Preferences.quality
    @State private var showLogin = false
    @State private var showDiagnostics = false
    @State private var toast = ""
    @State private var sleepText = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                accountCard
                qualityCard
                sleepCard
            toolsCard
                Text("KugouLite · iOS 15 精简版")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .padding(.top, 8)
            }
            .padding(16)
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showLogin) {
            LoginView().environmentObject(player).environmentObject(auth)
        }
        .overlay(alignment: .top) {
            if !toast.isEmpty { ToastView(text: toast) }
        }
    }

    private var accountCard: some View {
        VStack(spacing: 10) {
            Image(systemName: auth.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.system(size: 40))
                .foregroundColor(Theme.accent)
            Text(auth.isLoggedIn ? "已登录" : "未登录")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            if auth.isLoggedIn {
                Text("UID \(auth.userid)")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
            Button {
                showLogin = true
            } label: {
                Text(auth.isLoggedIn ? "查看账号 / 会员状态" : "扫码登录酷狗概念版")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Theme.accent)
                    .cornerRadius(18)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.card)
        .cornerRadius(16)
    }

    private var qualityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放音质")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            ForEach(AudioQuality.allCases) { item in
                Button {
                    quality = item
                    Preferences.quality = item
                    toast = "已切换为\(item.title)"
                    Task { try? await Task.sleep(nanoseconds: 1_200_000_000); toast = "" }
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        Spacer()
                        if quality == item {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            Text("取不到高音质时会自动降到下一档")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .cornerRadius(14)
    }

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("睡眠定时")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                if !sleepText.isEmpty {
                    Text(sleepText)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                }
            }
            HStack(spacing: 8) {
                ForEach([0, 15, 30, 60], id: \.self) { minutes in
                    Button {
                        player.setSleepTimer(minutes: minutes == 0 ? nil : minutes)
                        toast = minutes == 0 ? "已关闭睡眠定时" : "\(minutes) 分钟后暂停"
                        Task { try? await Task.sleep(nanoseconds: 1_400_000_000); toast = "" }
                    } label: {
                        Text(minutes == 0 ? "关闭" : "\(minutes) 分")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .cornerRadius(14)
        .onReceive(timer) { _ in
            guard let deadline = player.sleepDeadline else { sleepText = ""; return }
            let remain = Int(deadline.timeIntervalSinceNow)
            if remain <= 0 { sleepText = ""; return }
            sleepText = String(format: "剩余 %02d:%02d", remain / 60, remain % 60)
        }
    }

    private var toolsCard: some View {
        VStack(spacing: 0) {
            Button {
                Preferences.recentSongs = []
                Preferences.searchHistory = []
                toast = "已清空搜索与最近播放"
                Task { try? await Task.sleep(nanoseconds: 1_400_000_000); toast = "" }
            } label: {
                row(title: "清空本地记录", icon: "trash")
            }
            .buttonStyle(.plain)
            Divider().background(Color.white.opacity(0.08))
            Button {
                showDiagnostics = true
            } label: {
                row(title: "会员领取诊断", icon: "stethoscope")
            }
            .buttonStyle(.plain)
            Divider().background(Color.white.opacity(0.08))
            Button {
                if auth.isLoggedIn {
                    auth.signOut()
                    toast = "已退出登录"
                    Task { try? await Task.sleep(nanoseconds: 1_200_000_000); toast = "" }
                }
            } label: {
                row(title: auth.isLoggedIn ? "退出登录" : "未登录", icon: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.plain)
        }
        .background(Theme.card)
        .cornerRadius(14)
    }

    private func row(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(player.queueSongs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        player.jump(to: index)
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.secondaryText)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.SongName)
                                    .font(.system(size: 14, weight: player.currentIndex == index ? .semibold : .regular))
                                    .foregroundColor(player.currentIndex == index ? Theme.accent : .white)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                }
            }
            .listStyle(.plain)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }
}
