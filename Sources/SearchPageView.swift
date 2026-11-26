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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                TextField("搜索歌曲、歌手", text: $searchModel.query)
                    .font(.system(size: 15))
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
            .padding(.horizontal, 14)
            .frame(height: 46)
            .appSearchField(cornerRadius: 23)

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
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 16)
                        .padding(.top, 18)
                        .padding(.bottom, 2)
                }

                ForEach(searchModel.songs) { song in
                    SongRowWithMenu(song: song) {
                        searchFocused = false
                        onSelect(song)
                    }
                    .padding(.horizontal, 18)
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
            .padding(.bottom, 178)
            .chromeScrollTracking()
            .animation(Motion.standard, value: searchModel.songs.count)
        }
        .coordinateSpace(name: ChromeScrollSpace.name)
    }

    private var searchHistory: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("最近搜索")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Theme.text)
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
                        .appSurface(cornerRadius: 18)
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
                    .appSurface(cornerRadius: 18)
                }
            }

            if !hotKeywords.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("热门搜索")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.text)
                        Text("大家都在听")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                        Spacer()
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(Array(hotKeywords.prefix(8).enumerated()), id: \.element) { index, word in
                            SearchCategoryTile(word: word, index: index) {
                                searchModel.submit(word)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }
}


private struct SearchCategoryTile: View {
    let word: String
    let index: Int
    let action: () -> Void

    private static let palettes: [[Color]] = [
        [Color(red: 0.94, green: 0.18, blue: 0.30), Color(red: 0.99, green: 0.45, blue: 0.34)],
        [Color(red: 0.30, green: 0.46, blue: 0.98), Color(red: 0.48, green: 0.72, blue: 1.00)],
        [Color(red: 0.42, green: 0.22, blue: 0.82), Color(red: 0.72, green: 0.46, blue: 0.98)],
        [Color(red: 0.16, green: 0.62, blue: 0.50), Color(red: 0.42, green: 0.86, blue: 0.68)],
        [Color(red: 0.92, green: 0.48, blue: 0.12), Color(red: 1.00, green: 0.72, blue: 0.26)],
        [Color(red: 0.18, green: 0.62, blue: 0.84), Color(red: 0.44, green: 0.86, blue: 0.96)],
        [Color(red: 0.66, green: 0.20, blue: 0.52), Color(red: 0.94, green: 0.44, blue: 0.70)],
        [Color(red: 0.34, green: 0.36, blue: 0.44), Color(red: 0.62, green: 0.64, blue: 0.72)]
    ]

    private var palette: [Color] {
        Self.palettes[index % Self.palettes.count]
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: palette,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)

                Image(systemName: index < 3 ? "chart.line.uptrend.xyaxis" : "music.note")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white.opacity(0.20))
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                VStack(alignment: .leading, spacing: 3) {
                    Text(word)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(index < 3 ? "热门 TOP \(index + 1)" : "热门搜索")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.66))
                }
                .padding(14)
            }
            .frame(height: 98)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            )
            .shadow(color: palette[0].opacity(0.22), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(GlassPressButtonStyle())
    }
}
