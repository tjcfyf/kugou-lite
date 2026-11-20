import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var songs: [Song] = []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false

    private var searchTask: Task<Void, Never>?
    private var lastKeyword = ""
    private var page = 0

    func schedule() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        if keyword.isEmpty {
            songs = []
            message = nil
            isLoading = false
            lastKeyword = ""
            return
        }
        if keyword == lastKeyword { return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }
            await self?.run(keyword)
        }
    }

    func submit() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searchTask?.cancel()
        lastKeyword = keyword
        searchTask = Task { [weak self] in await self?.run(keyword) }
    }

    private func run(_ keyword: String) async {
        isLoading = true
        message = nil
        do {
            let result = try await KGService.search(keyword)
            guard !Task.isCancelled else { return }
            songs = result
            lastKeyword = keyword
            page = 1
            hasMore = result.count >= 30
            Preferences.addSearch(keyword)
            isLoading = false
            if result.isEmpty { message = "没有找到相关歌曲" }
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            songs = []
            message = (error as? LocalizedError)?.errorDescription ?? "搜索失败"
        }
    }

    func loadMore() {
        guard hasMore, !isLoading, !isLoadingMore, !lastKeyword.isEmpty else { return }
        isLoadingMore = true
        Task { [weak self] in
            guard let self = self else { return }
            let next = (try? await KGService.search(self.lastKeyword, page: self.page + 1)) ?? []
            self.isLoadingMore = false
            guard !next.isEmpty else {
                self.hasMore = false
                return
            }
            let existing = Set(self.songs.map { $0.FileHash })
            self.songs.append(contentsOf: next.filter { !existing.contains($0.FileHash) })
            self.page += 1
            self.hasMore = next.count >= 30
        }
    }
}

struct SearchView: View {
    @ObservedObject var model: SearchModel
    @EnvironmentObject private var player: PlayerEngine
    let onSelect: (Song) -> Void
    let onOpenPlayer: () -> Void
    @State private var hotKeywords: [String] = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    historyView
                }

                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .padding(.top, 40)
                }

                if let message = model.message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                }

                ForEach(model.songs) { song in
                    Button {
                        onSelect(song)
                    } label: {
                        SongRow(song: song)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                if model.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else if model.hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { model.loadMore() }
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
        .task {
            if hotKeywords.isEmpty { hotKeywords = (try? await KGService.hotSearch()) ?? [] }
        }
    }
}

extension SearchView {
    var historyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("最近搜索")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if !Preferences.searchHistory.isEmpty {
                    Button {
                        Preferences.searchHistory = []
                        model.query = ""
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }

            if Preferences.searchHistory.isEmpty {
                Text("搜歌手、歌名或专辑，点一首就能听")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Preferences.searchHistory, id: \.self) { word in
                        Button {
                            model.query = word
                            model.submit()
                        } label: {
                            Text(word)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !hotKeywords.isEmpty {
                Text("热门搜索")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 10)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(hotKeywords, id: \.self) { word in
                        Button {
                            model.query = word
                            model.submit()
                        } label: {
                            Text(word)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

struct MiniPlayer: View {
    let song: Song
    let onOpen: () -> Void

    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    CoverImage(url: song.coverURL, size: 38, radius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.SongName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                player.toggle()
            } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(
            ZStack {
                Color(red: 0.10, green: 0.10, blue: 0.13)
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
        }
    }
}
