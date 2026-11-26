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

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                latestRelease
                topSongsSection
                essentialAlbums
                moreSongs
            }
            .padding(.bottom, 34)
        }
        .background(AppBackground())
        .overlay(alignment: .top) {
            HStack(spacing: 8) {
                IOS27GlassCircleButton(systemName: "chevron.left", size: 42) {
                    dismiss()
                }
                .accessibilityLabel("返回")
                Spacer()
                IOS27GlassCircleButton(systemName: "square.and.arrow.up", size: 42) {
                    showShare = true
                }
                .accessibilityLabel("分享")
                Menu {
                    Button { playAll(shuffled: false) } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    Button { playAll(shuffled: true) } label: {
                        Label("随机播放", systemImage: "shuffle")
                    }
                    Button {
                        guard let first = songs.first else { return }
                        PlayerEngine.shared.playNext(first)
                    } label: {
                        Label("下一首播放", systemImage: "forward.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.24), lineWidth: 0.6))
                }
                .accessibilityLabel("更多")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showShare) {
            ArtistShareSheet(items: ["\(target.name) · Sonora"])
        }
        .sheet(item: $albumTarget) { album in
            AlbumDetailSheet(target: album)
        }
        .task { await load() }
    }

    private var header: some View {
        ZStack(alignment: .bottom) {
            CollectionHero(coverURL: headerCover, height: 458)
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.24), Color.black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 458)

            VStack(spacing: 10) {
                CoverImage(url: headerCover, size: 88, radius: 44, showsBorder: false)
                    .frame(width: 88, height: 88)
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.30), radius: 18, y: 8)

                Text(target.name)
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.7)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 34)

                Text(loading ? "正在读取歌手作品…" : "歌手 · \(songs.count) 首作品")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.66))

                HStack(spacing: 22) {
                    Button {
                        guard !songs.isEmpty else { return }
                        PlayerEngine.shared.play(songs.randomElement() ?? songs[0], in: songs.shuffled())
                        dismiss()
                    } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(IOS27PressStyle(pressedOpacity: 0.50, pressedScale: 0.93))
                    .disabled(songs.isEmpty)

                    Button { playAll(shuffled: false) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 56, height: 56)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(IOS27PressStyle(pressedOpacity: 0.65, pressedScale: 0.94))
                    .disabled(songs.isEmpty)
                    .opacity(songs.isEmpty ? 0.55 : 1)

                    Button {
                        guard !songs.isEmpty else { return }
                        PlayerEngine.shared.play(songs[0], in: songs)
                        dismiss()
                    } label: {
                        Image(systemName: "heart")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(IOS27PressStyle(pressedOpacity: 0.50, pressedScale: 0.93))
                    .disabled(songs.isEmpty)
                }
                .padding(.top, 2)
            }
            .padding(.bottom, 26)
        }
        .frame(height: 458)
    }

    @ViewBuilder
    private var latestRelease: some View {
        if let album = albums.first {
            VStack(alignment: .leading, spacing: 8) {
                Text("最新发行")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .textCase(.uppercase)

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
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                            Text("专辑 · \(target.name)")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "plus.circle")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundColor(Theme.text)
                    }
                    .padding(.horizontal, IOS27.pagePadding)
                    .frame(height: 82)
                    .contentShape(Rectangle())
                }
                .buttonStyle(IOS27RowButtonStyle())
            }
            .padding(.top, 20)
        }
    }

    @ViewBuilder
    private var topSongsSection: some View {
        if !songs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                IOS27SectionHeader(title: "热门歌曲", subtitle: "TOP 5")

                ForEach(Array(topSongs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        PlayerEngine.shared.play(song, in: songs)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Theme.secondaryText)
                                .frame(width: 18, alignment: .leading)
                            CoverImage(url: song.coverURL, size: 48, radius: 7, showsBorder: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.SongName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.text)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.tertiaryText)
                                .frame(width: 20, height: 20)
                        }
                        .padding(.horizontal, IOS27.pagePadding)
                        .frame(height: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(IOS27RowButtonStyle())

                    if index < topSongs.count - 1 {
                        IOS27RowDivider(leading: 90)
                            .padding(.trailing, IOS27.pagePadding)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var essentialAlbums: some View {
        if albums.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                IOS27SectionHeader(title: "代表专辑")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(albums.dropFirst()) { album in
                            Button {
                                albumTarget = AlbumTarget(id: album.id,
                                                           name: album.name,
                                                           cover: album.cover,
                                                           artist: target.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    CoverImage(url: album.cover, size: 168, radius: 8, showsBorder: false)
                                    Text(album.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                        .frame(width: 168, alignment: .leading)
                                }
                            }
                            .buttonStyle(IOS27PressStyle(pressedOpacity: 0.62, pressedScale: 0.97))
                        }
                    }
                    .padding(.horizontal, IOS27.pagePadding)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var moreSongs: some View {
        if loading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                .frame(maxWidth: .infinity)
                .padding(.top, 34)
        } else if songs.isEmpty {
            VStack(spacing: 12) {
                Text(message ?? "暂时没有读取到这位歌手的作品")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await load() }
                } label: {
                    Text("重新加载")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(IOS27.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 34)
            .padding(.horizontal, 24)
        } else if hasMore {
            Button {
                Task { await loadMore() }
            } label: {
                HStack(spacing: 6) {
                    if loadingMore {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                    }
                    Text(loadingMore ? "正在加载…" : "显示全部作品")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(IOS27.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .buttonStyle(IOS27PressStyle(pressedOpacity: 0.55, pressedScale: 1))
        }
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

private struct ArtistShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
