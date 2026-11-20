import SwiftUI

struct ArtistTarget: Identifiable {
    let name: String
    let authorID: Int?
    let cover: URL?

    var id: String { "\(authorID ?? 0)-\(name)" }
}

struct ArtistDetailSheet: View {
    let target: ArtistTarget
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var message: String?
    @State private var resolvedAuthorID: Int?
    @State private var page = 1
    @State private var hasMore = false
    @State private var loadingMore = false
    @State private var usingSearchFallback = false

    private var headerCover: URL? {
        songs.first?.coverURL ?? target.cover
    }

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    header
                    content
                }
                .padding(.bottom, 28)
            }
            .background(AppBackground())
            .navigationTitle("歌手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        guard let first = songs.first else { return }
                        player.play(first, in: songs)
                        dismiss()
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                    .disabled(songs.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            CoverImage(url: headerCover, size: 118, radius: 59)
                .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 8)

            Text(target.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 28)

            Text(loading ? "正在读取歌手作品…" : "\(songs.count) 首作品")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            LinearGradient(
                colors: [Theme.accent.opacity(0.12), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                .frame(maxWidth: .infinity)
                .padding(.top, 36)
        } else if songs.isEmpty {
            VStack(spacing: 12) {
                Text(message ?? "暂时没有读取到这位歌手的作品")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await load() }
                } label: {
                    Text("重新加载")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 36)
            .padding(.horizontal, 24)
        } else {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                Button {
                    player.play(song, in: songs)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                            .frame(width: 22, alignment: .leading)
                        SongRow(song: song)
                    }
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }

            if hasMore {
                Button {
                    Task { await loadMore() }
                } label: {
                    HStack(spacing: 8) {
                        if loadingMore {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                        } else {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        Text(loadingMore ? "正在加载更多…" : "加载更多（已显示 \(songs.count) 首）")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id("artist-more-\(songs.count)")
                .onAppear {
                    Task { await loadMore() }
                }
            }
        }
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
                // 作品接口失败时退回到按歌手名搜索，至少保证页面可用。
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
