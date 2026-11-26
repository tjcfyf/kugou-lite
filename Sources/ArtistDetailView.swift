import SwiftUI
import UIKit

struct ArtistTarget: Identifiable {
    let name: String
    let authorID: Int?
    let cover: URL?

    var id: String { "\(authorID ?? 0)-\(name)" }
}

private struct ArtistAlbumGroup: Identifiable {
    let id: Int
    let name: String
    let cover: URL?
}

/// iOS 27 Apple Music 的歌手页：整页跟随头图主色变暗，内容全部为高对比白色；
/// 艺人名用大号字标式的字重/字距排版，控制行固定为 信息 / 播放 / 收藏。
struct ArtistDetailSheet: View {
    let target: ArtistTarget
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var message: String?
    @State private var resolvedAuthorID: Int?
    @State private var page = 1
    @State private var hasMore = false
    @State private var loadingMore = false
    @State private var usingSearchFallback = false
    @State private var showShare = false
    @State private var showInfo = false
    @State private var showAllSongs = false
    @State private var albumTarget: AlbumTarget?

    private var headerCover: URL? {
        songs.first?.coverURL ?? target.cover
    }

    private var albums: [ArtistAlbumGroup] {
        var seen = Set<Int>()
        var result: [ArtistAlbumGroup] = []
        for song in songs {
            guard let id = song.AlbumID, id > 0,
                  let name = song.AlbumName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  seen.insert(id).inserted else { continue }
            result.append(ArtistAlbumGroup(id: id, name: name, cover: song.coverURL))
        }
        return Array(result.prefix(10))
    }

    private var topSongs: [Song] { Array(songs.prefix(5)) }
    private var remainingSongs: [Song] { Array(songs.dropFirst(5)) }

    var body: some View {
        ZStack {
            TintedCoverBackdrop(coverURL: headerCover)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    hero
                    latestRelease
                    topSongsSection
                    essentialAlbums
                    moreSongs
                }
                .padding(.bottom, 40)
            }
        }
        .ignoresSafeArea(edges: .top)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            topControls
        }
        .sheet(isPresented: $showShare) {
            ArtistShareSheet(items: ["\(target.name) · Sonora"])
        }
        .sheet(isPresented: $showInfo) {
            ArtistInfoSheet(name: target.name, count: songs.count)
        }
        .sheet(item: $albumTarget) { album in
            AlbumDetailSheet(target: album)
        }
        .task { await load() }
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial)
                    .background(Color.black.opacity(0.18))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 0.6))
            }
            .buttonStyle(IOS27PressStyle(pressedOpacity: 0.52, pressedScale: 0.94))
            .accessibilityLabel("返回")

            Spacer()

            HStack(spacing: 0) {
                Button { showShare = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 45, height: 42)
                }
                .buttonStyle(IOS27PressStyle(pressedOpacity: 0.45, pressedScale: 0.95))

                Menu {
                    Button { playAll(shuffled: true) } label: {
                        Label("随机播放", systemImage: "shuffle")
                    }
                    Button { playAll(shuffled: false) } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    if let first = songs.first {
                        Button { PlayerEngine.shared.playNext(first) } label: {
                            Label("下一首播放", systemImage: "forward.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 45, height: 42)
                }
            }
            .background(.ultraThinMaterial)
            .background(Color.black.opacity(0.18))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.6))
        }
        .padding(.horizontal, 16)
        .padding(.top, 58)
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                CoverImage(url: headerCover, size: max(geo.size.width, 560), radius: 0, showsBorder: false)
                    .frame(width: geo.size.width, height: 520)
                    .clipped()
            }
            .frame(height: 520)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.18),
                    .init(color: Color.black.opacity(0.18), location: 0.48),
                    .init(color: Color.black.opacity(0.66), location: 0.78),
                    .init(color: Color.black.opacity(0.96), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                Text("歌手")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2.2)
                    .foregroundColor(.white.opacity(0.72))
                    .textCase(.uppercase)

                Text(target.name.uppercased())
                    .font(.system(size: target.name.count > 12 ? 34 : 40, weight: .black))
                    .tracking(1.8)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 24)
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)

                HStack(spacing: 24) {
                    Button { showInfo = true } label: {
                        Image(systemName: "info")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial)
                            .background(Color.black.opacity(0.16))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                    }
                    .buttonStyle(IOS27PressStyle(pressedOpacity: 0.50, pressedScale: 0.94))

                    Button { playAll(shuffled: false) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 58, height: 58)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(IOS27PressStyle(pressedOpacity: 0.68, pressedScale: 0.93))
                    .disabled(songs.isEmpty)
                    .opacity(songs.isEmpty ? 0.55 : 1)
                    .accessibilityLabel("播放")

                    Button {
                        guard let song = songs.first else { return }
                        Task {
                            let added = await LibraryStore.shared.toggleFavorite(song)
                            if let added = added { PlayerEngine.shared.showToast(added ? "已收藏" : "已取消收藏") }
                        }
                    } label: {
                        Image(systemName: "star")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial)
                            .background(Color.black.opacity(0.16))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                    }
                    .buttonStyle(IOS27PressStyle(pressedOpacity: 0.50, pressedScale: 0.94))
                    .disabled(songs.isEmpty)
                }
                .padding(.top, 2)
            }
            .padding(.bottom, 26)
        }
        .frame(height: 520)
    }

    @ViewBuilder
    private var latestRelease: some View {
        if let album = albums.first {
            VStack(alignment: .leading, spacing: 8) {
                Text("最新发行")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.68))
                    .textCase(.uppercase)
                    .padding(.horizontal, IOS27.pagePadding)

                Button {
                    albumTarget = AlbumTarget(id: album.id,
                                               name: album.name,
                                               cover: album.cover,
                                               artist: target.name)
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(url: album.cover, size: 64, radius: 8, showsBorder: false)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(album.name)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(2)
                            Text("专辑 · \(songs.count) 首作品")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    .padding(.horizontal, IOS27.pagePadding)
                }
                .buttonStyle(IOS27PressStyle(pressedOpacity: 0.70, pressedScale: 0.985))
            }
            .padding(.top, 4)
        }
    }

    private var topSongsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("热门歌曲")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.25)
                    .foregroundColor(.white)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.top, 2)
                Spacer()
            }
            .padding(.horizontal, IOS27.pagePadding)
            .padding(.top, 30)
            .padding(.bottom, 10)

            if loading && songs.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            } else if songs.isEmpty {
                Text(message ?? "暂时没有读取到这位歌手的作品")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.64))
                    .padding(.horizontal, IOS27.pagePadding)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(topSongs.enumerated()), id: \.element.id) { index, song in
                    artistSongRow(song)
                    if index < topSongs.count - 1 {
                        artistDivider
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var essentialAlbums: some View {
        if albums.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("代表专辑")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.25)
                        .foregroundColor(.white)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                    Spacer()
                }
                .padding(.horizontal, IOS27.pagePadding)
                .padding(.top, 32)
                .padding(.bottom, 12)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { album in
                            Button {
                                albumTarget = AlbumTarget(id: album.id,
                                                           name: album.name,
                                                           cover: album.cover,
                                                           artist: target.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    CoverImage(url: album.cover, size: 168, radius: 8, showsBorder: false)
                                    Text(album.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .frame(width: 168, alignment: .leading)
                                }
                            }
                            .buttonStyle(IOS27PressStyle(pressedOpacity: 0.62, pressedScale: 0.97))
                        }
                    }
                    .padding(.horizontal, IOS27.pagePadding)
                }
            }
        }
    }

    @ViewBuilder
    private var moreSongs: some View {
        if !songs.isEmpty {
            if !showAllSongs && songs.count > 5 {
                Button {
                    withAnimation(Motion.standard) { showAllSongs = true }
                } label: {
                    HStack(spacing: 4) {
                        Text("查看全部 \(songs.count) 首歌曲")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(IOS27.accent)
                    .padding(.horizontal, IOS27.pagePadding)
                    .padding(.vertical, 20)
                }
                .buttonStyle(IOS27PressStyle(pressedOpacity: 0.55, pressedScale: 1))
            }

            if showAllSongs && !remainingSongs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(remainingSongs.enumerated()), id: \.element.id) { index, song in
                        artistSongRow(song)
                        if index < remainingSongs.count - 1 { artistDivider }
                    }
                }
                .padding(.top, 8)
            }

            if showAllSongs && hasMore {
                Button {
                    Task { await loadMore() }
                } label: {
                    HStack(spacing: 6) {
                        if loadingMore {
                            ProgressView().tint(.white)
                        }
                        Text(loadingMore ? "正在加载…" : "加载更多")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                }
                .buttonStyle(IOS27PressStyle(pressedOpacity: 0.55, pressedScale: 1))
            }
        }
    }

    private func artistSongRow(_ song: Song) -> some View {
        HStack(spacing: 6) {
            Button {
                PlayerEngine.shared.play(song, in: songs)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    CoverImage(url: song.coverURL, size: 44, radius: 6, showsBorder: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.SongName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text([song.artist, song.AlbumName ?? ""]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.leading, IOS27.pagePadding)
                .frame(height: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(IOS27RowButtonStyle())

            SongMoreMenu(song: song)
                .padding(.trailing, IOS27.pagePadding - 4)
        }
    }

    private var artistDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 0.5)
            .padding(.leading, 76)
            .padding(.trailing, IOS27.pagePadding)
    }


    private func playAll(shuffled: Bool) {
        guard !songs.isEmpty else { return }
        let list = shuffled ? songs.shuffled() : songs
        PlayerEngine.shared.play(list[0], in: list)
        dismiss()
    }

    private func load() async {
        loading = true
        message = nil
        page = 1
        hasMore = false
        usingSearchFallback = false

        var authorID = target.authorID
        if authorID == nil {
            authorID = try? await KGService.artistID(named: target.name)
        }

        if let authorID = authorID {
            resolvedAuthorID = authorID
            do {
                let list = try await KGService.artistSongs(authorID: authorID, page: 1, pageSize: 30)
                songs = list
                hasMore = list.count >= 30
                loading = false
                if list.isEmpty { message = "这位歌手暂时没有可播放的作品" }
                return
            } catch {
                message = (error as? LocalizedError)?.errorDescription
            }
        }

        do {
            let list = try await KGService.search(target.name, page: 1, pageSize: 30)
            let filtered = list.filter { matchesArtist($0) }
            songs = filtered.isEmpty ? list : filtered
            usingSearchFallback = true
            hasMore = list.count >= 30
            loading = false
            if songs.isEmpty { message = "暂时没有读取到这位歌手的作品" }
        } catch {
            loading = false
            songs = []
            message = (error as? LocalizedError)?.errorDescription ?? "歌手作品读取失败"
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }

        if !usingSearchFallback, let authorID = resolvedAuthorID {
            let next = (try? await KGService.artistSongs(authorID: authorID, page: page + 1, pageSize: 30)) ?? []
            guard !next.isEmpty else {
                hasMore = false
                return
            }
            append(next)
            page += 1
            hasMore = next.count >= 30
            return
        }

        let nextPage = try? await KGService.search(target.name, page: page + 1, pageSize: 30)
        guard let list = nextPage, !list.isEmpty else {
            hasMore = false
            return
        }
        let filtered = list.filter { matchesArtist($0) }
        append(filtered.isEmpty ? list : filtered)
        page += 1
        hasMore = list.count >= 30
    }

    private func append(_ next: [Song]) {
        let existing = Set(songs.map { $0.FileHash })
        songs.append(contentsOf: next.filter { !existing.contains($0.FileHash) })
    }

    private func matchesArtist(_ song: Song) -> Bool {
        let targetName = target.name.replacingOccurrences(of: " / ", with: "、")
        return song.SingerName.contains(targetName) || targetName.contains(song.SingerName)
    }
}

struct TintedCoverBackdrop: View {
    let coverURL: URL?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let coverURL {
                    CoverImage(url: coverURL, size: max(geo.size.width, geo.size.height), radius: 0, showsBorder: false)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.22)
                        .blur(radius: 54)
                        .clipped()
                } else {
                    Color.black
                }

                Color.black.opacity(0.26)

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.04), location: 0),
                        .init(color: Color.black.opacity(0.38), location: 0.38),
                        .init(color: Color.black.opacity(0.86), location: 0.72),
                        .init(color: Color.black, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .drawingGroup()
        }
        .ignoresSafeArea()
    }
}

private struct ArtistInfoSheet: View {
    let name: String
    let count: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.text)
                    Text("Sonora 从酷狗音乐读取到的歌手资料。当前页共收录 \(count) 首可播放作品。")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.secondaryText)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(AppBackground())
            .navigationTitle("关于歌手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(IOS27.accent)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct ArtistShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
