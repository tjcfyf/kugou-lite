import SwiftUI

struct AlbumTarget: Identifiable, Equatable {
    let id: Int
    let name: String
    let cover: URL?
    let artist: String
}

struct AlbumDetailSheet: View {
    let target: AlbumTarget
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var message: String?
    @State private var page = 1
    @State private var hasMore = false
    @State private var loadingMore = false

    private var headerCover: URL? {
        songs.first?.coverURL ?? target.cover
    }

    private var headerArtist: String {
        songs.first?.artist ?? target.artist
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
            .navigationTitle("专辑")
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
            CoverImage(url: headerCover, size: 150, radius: 22)
                .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 10)

            Text(target.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 28)

            if !headerArtist.isEmpty {
                Text(headerArtist)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }

            Text(loading ? "正在读取专辑…" : "\(songs.count) 首歌曲")
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
                Text(message ?? "这张专辑暂时没有可播放的歌曲")
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
                SongRowWithMenu(song: song, index: index + 1) {
                    player.play(song, in: songs)
                    dismiss()
                }
                .padding(.horizontal, 16)
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
                .id("album-more-\(songs.count)")
                .onAppear {
                    Task { await loadMore() }
                }
            }
        }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let next = (try? await KGService.albumSongs(albumID: target.id, page: page + 1, pageSize: 30)) ?? []
        guard !next.isEmpty else {
            hasMore = false
            return
        }
        let existing = Set(songs.map { $0.FileHash })
        songs.append(contentsOf: next.filter { !existing.contains($0.FileHash) })
        page += 1
        hasMore = next.count >= 30
    }

    private func load() async {
        loading = true
        message = nil
        do {
            let list = try await KGService.albumSongs(albumID: target.id, page: 1, pageSize: 30)
            songs = list
            page = 1
            hasMore = list.count >= 30
            loading = false
            if list.isEmpty { message = "这张专辑暂时没有可播放的歌曲" }
        } catch {
            loading = false
            message = (error as? LocalizedError)?.errorDescription ?? "专辑读取失败"
        }
    }
}
