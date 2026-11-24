import SwiftUI

/// 独立搜索页。它和「现在就听」使用两棵独立的 NavigationView 视图树，
/// 点底栏搜索时直接挂这个页面，不会再先渲染首页再切内容。
struct SearchPageView: View {
    @ObservedObject var searchModel: SearchModel
    let onSelect: (Song) -> Void

    @State private var historyWords: [String] = Preferences.searchHistory
    @State private var hotKeywords: [String] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            searchBody
        }
        .background(AppBackground())
        .gradientNavigationBlur()
        .task {
            historyWords = Preferences.searchHistory
            if hotKeywords.isEmpty {
                hotKeywords = (try? await KGService.hotSearch()) ?? []
            }
        }
        .onChange(of: searchModel.query) { _ in
            searchModel.schedule()
        }
        .onDisappear {
            searchFocused = false
        }
        .onChange(of: searchFocused) { focused in
            if !focused {
                // 失焦时不要清空搜索词，Apple Music 会保留刚搜过的内容。
                historyWords = Preferences.searchHistory
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                TextField("搜索歌曲、歌手", text: $searchModel.query)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { searchModel.submit() }
                if !searchModel.query.isEmpty {
                    Button {
                        searchModel.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Theme.secondaryText)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 38)
            .appSearchField(cornerRadius: 10)

            if searchFocused {
                Button {
                    searchFocused = false
                } label: {
                    Text("取消")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.accent)
                        .frame(height: 38)
                }
                .buttonStyle(GlassPressButtonStyle())
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(Motion.quick, value: searchFocused)
    }

    private var searchBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchHistory
                }

                if searchModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                }

                if let message = searchModel.message {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 36)
                }

                if !searchModel.songs.isEmpty {
                    Text("歌曲")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 2)
                }

                ForEach(searchModel.songs) { song in
                    SongRowWithMenu(song: song) {
                        searchFocused = false
                        onSelect(song)
                    }
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if searchModel.isLoadingMore {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else if searchModel.hasMore {
                    Color.clear
                        .frame(height: 1)
                        .onAppear { searchModel.loadMore() }
                }
            }
            .padding(.bottom, 132)
            .animation(Motion.standard, value: searchModel.songs.count)
        }
    }

    private var searchHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("最近搜索")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                    Spacer()
                    if !historyWords.isEmpty {
                        Button {
                            Preferences.searchHistory = []
                            historyWords = []
                            searchModel.query = ""
                        } label: {
                            Text("清除")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.accent)
                                .frame(height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(GlassPressButtonStyle())
                    }
                }

                if historyWords.isEmpty {
                    Text("搜歌手、歌名或专辑，点一首就能听")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .appSurface(cornerRadius: 10)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(historyWords.enumerated()), id: \.element) { index, word in
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.tertiaryText)
                                    .frame(width: 18)

                                Button {
                                    searchModel.submit(word)
                                } label: {
                                    Text(word)
                                        .font(.system(size: 14))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(GlassPressButtonStyle())

                                Button {
                                    Preferences.removeSearch(word)
                                    historyWords = Preferences.searchHistory
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Theme.tertiaryText)
                                        .frame(width: 30, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(GlassPressButtonStyle())
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)

                            if index < historyWords.count - 1 {
                                Divider()
                                    .background(Theme.separator)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                    .appSurface(cornerRadius: 10)
                }
            }

            if !hotKeywords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("热门搜索")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        alignment: .leading,
                        spacing: 0
                    ) {
                        ForEach(Array(hotKeywords.prefix(10).enumerated()), id: \.element) { index, word in
                            Button {
                                searchModel.submit(word)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(index < 3 ? Theme.accent : Theme.tertiaryText)
                                        .frame(width: 16, alignment: .leading)
                                    Text(word)
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .frame(height: 40)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(GlassPressButtonStyle())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 2)
                    .appSurface(cornerRadius: 10)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}
