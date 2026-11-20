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
        if keyword.isEmpty {
            searchTask?.cancel()
            songs = []
            message = nil
            isLoading = false
            lastKeyword = ""
            return
        }
        // 点历史/热门词时 submit 已经发起同一个关键词的请求，
        // 这里不能再取消它，否则快捷搜索会一直加载不出来。
        if keyword == lastKeyword { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }
            await self?.run(keyword)
        }
    }

    func submit(_ keyword: String? = nil) {
        let raw = keyword ?? query
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        lastKeyword = trimmed
        if query != trimmed { query = trimmed }
        searchTask = Task { [weak self] in await self?.run(trimmed) }
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
    @State private var historyWords: [String] = Preferences.searchHistory

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    historyView
                }

                if model.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
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
                    SongRowWithMenu(song: song) {
                        onSelect(song)
                    }
                    .padding(.horizontal, 16)
                }

                if model.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
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
        .background(AppBackground())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let song = player.current {
                MiniPlayer(song: song, onOpen: onOpenPlayer)
            }
        }
        .task {
            historyWords = Preferences.searchHistory
            if hotKeywords.isEmpty { hotKeywords = (try? await KGService.hotSearch()) ?? [] }
        }
        .onChange(of: model.query) { value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                historyWords = Preferences.searchHistory
            }
        }
    }
}

extension SearchView {
    var historyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("最近搜索")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                if !historyWords.isEmpty {
                    Button {
                        Preferences.searchHistory = []
                        historyWords = []
                        model.query = ""
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }

            if historyWords.isEmpty {
                Text("搜歌手、歌名或专辑，点一首就能听")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(historyWords, id: \.self) { word in
                        HStack(spacing: 8) {
                            Button {
                                model.submit(word)
                            } label: {
                                Text(word)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.text.opacity(0.85))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(GlassPressButtonStyle())

                            Button {
                                Preferences.removeSearch(word)
                                historyWords = Preferences.searchHistory
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Theme.secondaryText)
                                    .frame(width: 24, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(GlassPressButtonStyle())
                        }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        .appChip(cornerRadius: 10)
                    }
                }
            }

            if !hotKeywords.isEmpty {
                Text("热门搜索")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .padding(.top, 10)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(hotKeywords, id: \.self) { word in
                        Button {
                            model.submit(word)
                        } label: {
                            Text(word)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.text.opacity(0.85))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .appChip(cornerRadius: 10)
                        }
                        .buttonStyle(GlassPressButtonStyle())
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
                    CoverImage(url: song.coverURL, size: 44, radius: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(song.SongName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.text)
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
            .buttonStyle(GlassPressButtonStyle())

            Button {
                player.toggle()
            } label: {
                Group {
                    if player.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 38, height: 38)
                .background(Theme.accent)
                .clipShape(Circle())
            }
            .buttonStyle(GlassPressButtonStyle())

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.text.opacity(0.75))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(GlassPressButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Theme.card.opacity(0.35)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.separator, lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}
