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
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Theme.secondaryText)
                TextField("搜索歌曲、歌手", text: $searchModel.query)
                    .font(.system(size: 16, weight: .regular))
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
            .frame(height: 44)
            .background(.ultraThinMaterial)
            .background(Theme.background.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Theme.text.opacity(0.10), lineWidth: 0.5)
            )

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
                    IOS27SectionHeader(title: "歌曲", subtitle: searchModel.songs.count > 0 ? "\(searchModel.songs.count) 首" : nil)
                }

                ForEach(Array(searchModel.songs.enumerated()), id: \.element.id) { index, song in
                    SongRowWithMenu(song: song) {
                        searchFocused = false
                        onSelect(song)
                    }
                    .padding(.horizontal, IOS27.pagePadding)

                    if index < searchModel.songs.count - 1 {
                        IOS27RowDivider(leading: 64)
                            .padding(.trailing, IOS27.pagePadding)
                    }
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
                        .font(IOS27.sectionTitle)
                        .tracking(IOS27.sectionTracking)
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
                .padding(.horizontal, IOS27.pagePadding)

                if historyWords.isEmpty {
                    Text("搜歌手、歌名或专辑，点一首就能听")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, IOS27.pagePadding)
                        .padding(.vertical, 12)
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
                                        .font(.system(size: 16, weight: .regular))
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
                            .padding(.horizontal, IOS27.pagePadding)
                            .frame(minHeight: 46)

                            if index < historyWords.count - 1 {
                                IOS27RowDivider(leading: 44)
                                    .padding(.trailing, IOS27.pagePadding)
                            }
                        }
                    }
                    .background(Theme.background)
                }
            }

            if !hotKeywords.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("热门搜索")
                            .font(IOS27.sectionTitle)
                            .tracking(IOS27.sectionTracking)
                            .foregroundColor(Theme.text)
                        Text("大家都在搜")
                            .font(IOS27.caption)
                            .foregroundColor(Theme.secondaryText)
                        Spacer()
                    }
                    .padding(.horizontal, IOS27.pagePadding)

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
                    .padding(.horizontal, IOS27.pagePadding)
                }
            }
        }
        .padding(.horizontal, 0)
        .padding(.top, 4)
    }
}


private struct SearchCategoryTile: View {
    let word: String
    let index: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.chip)

                Image(systemName: index < 3 ? "arrow.up.right" : "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.tertiaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(word)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(index < 3 ? "热门 TOP \(index + 1)" : "热门搜索")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Theme.secondaryText)
                }
                .padding(12)
            }
            .frame(height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.text.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(IOS27PressStyle(pressedOpacity: 0.62, pressedScale: 0.98))
    }
}
