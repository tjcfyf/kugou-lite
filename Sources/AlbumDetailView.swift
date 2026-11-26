import SwiftUI

struct AlbumTarget: Identifiable, Equatable {
    let id: Int
    let name: String
    let cover: URL?
    let artist: String
}

struct AlbumDetailSheet: View {
    let target: AlbumTarget
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                trackList
                loadMoreFooter
            }
            .padding(.bottom, 30)
        }
        .background(AppBackground())
        .overlay(alignment: .topLeading) {
            IOS27GlassCircleButton(systemName: "chevron.left", size: 42) {
                dismiss()
            }
            .padding(.top, 8)
            .padding(.leading, 16)
            .accessibilityLabel("返回")
        }
        .task { await load() }
    }

    private var header: some View {
        ZStack(alignment: .bottom) {
            CollectionHero(coverURL: headerCover, height: 486)
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.16), Color.black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 486)

            VStack(spacing: 9) {
                CoverImage(url: headerCover, size: 210, radius: 10, showsBorder: false)
                    .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 12)

                Text(target.name)
                    .font(.system(size: 27, weight: .bold))
                    .tracking(-0.45)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 28)

                if !headerArtist.isEmpty {
                    Text(headerArtist)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                }

                Text(loading ? "正在读取专辑…" : "专辑 · \(songs.count) 首")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.54))

                HStack(spacing: 22) {
                    Button { play(shuffled: true) } label: {
                        Image(systemName: "shuffle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(IOS27PressStyle(pressedOpacity: 0.50, pressedScale: 0.93))
                    .disabled(songs.isEmpty)

                    Button { play(shuffled: false) } label: {
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
                        PlayerEngine.shared.playNext(songs[0])
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white.opacity(0.92))
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(IOS27PressStyle(pressedOpacity: 0.50, pressedScale: 0.93))
                    .disabled(songs.isEmpty)
                }
                .padding(.top, 2)
            }
            .padding(.bottom, 24)
        }
        .frame(height: 486)
    }

    @ViewBuilder
    private var trackList: some View {
        if loading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                .frame(maxWidth: .infinity)
                .padding(.top, 34)
        } else if songs.isEmpty {
            VStack(spacing: 12) {
                Text(message ?? "这张专辑暂时没有可播放的歌曲")
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
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !headerArtist.isEmpty {
                    HStack(spacing: 6) {
                        Text("\(songs.count) 首歌曲")
                        Text("·")
                        Text(headerArtist)
                        Spacer()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .padding(.horizontal, IOS27.pagePadding)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                }

                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    HStack(spacing: 8) {
                        Button {
                            PlayerEngine.shared.play(song, in: songs)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Group {
                                    if playerIsCurrent(song) {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(IOS27.accent)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(Theme.secondaryText)
                                    }
                                }
                                .frame(width: 22, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.SongName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    if song.artist != headerArtist {
                                        Text(song.artist)
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(durationText(song.Duration))
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Theme.tertiaryText)
                            }
                            .padding(.leading, IOS27.pagePadding)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(IOS27RowButtonStyle())

                        SongMoreMenu(song: song)
                            .padding(.trailing, IOS27.pagePadding)
                    }

                    if index < songs.count - 1 {
                        IOS27RowDivider(leading: 52)
                            .padding(.trailing, IOS27.pagePadding)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if hasMore && !songs.isEmpty {
            Button {
                Task { await loadMore() }
            } label: {
                HStack(spacing: 6) {
                    if loadingMore {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                    }
                    Text(loadingMore ? "正在加载…" : "加载更多")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(IOS27.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            }
            .buttonStyle(IOS27PressStyle(pressedOpacity: 0.55, pressedScale: 1))
            .onAppear {
                guard !loadingMore else { return }
                Task { await loadMore() }
            }
        }
    }

    private func play(shuffled: Bool) {
        guard !songs.isEmpty else { return }
        let list = shuffled ? songs.shuffled() : songs
        PlayerEngine.shared.play(list[0], in: list)
        dismiss()
    }

    private func durationText(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func playerIsCurrent(_ song: Song) -> Bool {
        PlayerEngine.shared.current?.FileHash == song.FileHash
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
