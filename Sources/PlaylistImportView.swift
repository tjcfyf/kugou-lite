import SwiftUI

struct PlaylistImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var source: PlaylistImportSource = .netease
    @State private var input = ""
    @State private var isImporting = false
    @State private var progressText = ""
    @State private var errorText = ""
    @State private var result: ImportedPlaylist?
    @FocusState private var inputFocused: Bool

    var onImported: (ImportedPlaylist) -> Void = { _ in }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    sourcePicker
                    inputCard
                    if !errorText.isEmpty { errorCard }
                    if let result { resultCard(result) }
                    actionButton
                    footnote
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("导入歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("来源")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.secondaryText)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(PlaylistImportSource.allCases) { item in
                    Button {
                        source = item
                        errorText = ""
                        result = nil
                    } label: {
                        HStack(spacing: 9) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                            Text(item.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.text)
                            Spacer(minLength: 0)
                            if source == item {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 46)
                        .appSurface(cornerRadius: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(source == item ? Theme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(source == .soda ? "歌单链接或歌曲列表" : "歌单链接 / ID")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.secondaryText)

            ZStack(alignment: .topLeading) {
                if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(source.placeholder)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.tertiaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $input)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .frame(minHeight: 118)
                    .padding(7)
                    .background(Color.clear)
                    .focused($inputFocused)
            }
            .appSearchField(cornerRadius: 10)

            Text(source == .soda
                 ? "汽水音乐目前没有公开的歌单接口。把歌单里的歌曲按每行「歌名 - 歌手」粘贴进来，Sonora 会自动匹配酷狗曲库。"
                 : "支持直接粘贴公开歌单链接；如果链接失效，也可以粘贴歌曲列表，每行「歌名 - 歌手」。")
                .font(.system(size: 11))
                .foregroundColor(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var errorCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundColor(Theme.accent)
            Text(errorText)
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .appSurface(cornerRadius: 10)
    }

    private func resultCard(_ playlist: ImportedPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                artwork(url: playlist.coverURL)
                    .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                    Text("已导入 \(playlist.songs.count) 首 · \(playlist.source)")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.accent)
                    )
            }
            .buttonStyle(GlassPressButtonStyle())
        }
        .padding(14)
        .appSurface(cornerRadius: 12)
    }

    private var actionButton: some View {
        Button {
            Task { await startImport() }
        } label: {
            HStack(spacing: 8) {
                if isImporting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.onAccent))
                        .scaleEffect(0.8)
                }
                Text(isImporting ? (progressText.isEmpty ? "正在读取歌单…" : progressText) : "开始导入")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.onAccent)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.secondaryText.opacity(0.35) : Theme.accent)
            )
        }
        .buttonStyle(GlassPressButtonStyle())
        .disabled(isImporting || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var footnote: some View {
        Text("导入只会保存到本机资料库，不改动你的酷狗账号歌单。曲目会按「歌名 + 歌手」匹配酷狗曲库，匹配不到的曲目不会写入。")
            .font(.system(size: 11))
            .foregroundColor(Theme.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    private func startImport() async {
        inputFocused = false
        errorText = ""
        result = nil
        progressText = "正在读取歌单…"
        isImporting = true
        defer { isImporting = false }

        do {
            let external = try await ExternalPlaylistService.fetch(source: source, input: input)
            progressText = "正在匹配 0/\(external.tracks.count)"
            let songs = await PlaylistMatcher.match(external.tracks) { done, total in
                progressText = "正在匹配 \(done)/\(total)"
            }
            guard !songs.isEmpty else {
                throw PlaylistImportError.empty("没有一首匹配到酷狗曲库，请换一个歌单或检查歌曲列表格式")
            }
            let playlist = ImportedPlaylist(
                name: external.name,
                source: source.shortTitle,
                coverURL: external.coverURL ?? songs.first?.coverURL,
                songs: songs
            )
            ImportedPlaylistStore.shared.add(playlist)
            onImported(playlist)
            result = playlist
            progressText = ""
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? "导入失败：\(error.localizedDescription)"
            progressText = ""
        }
    }

    private func artwork(url: URL?) -> some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    artworkPlaceholder
                }
            } else {
                artworkPlaceholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Theme.card
            Image(systemName: "music.note")
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(Theme.secondaryText)
        }
    }
}

private extension PlaylistImportSource {
    var color: Color {
        switch self {
        case .netease: return Color(red: 0.90, green: 0.00, blue: 0.15)
        case .qq: return Color(red: 0.19, green: 0.76, blue: 0.49)
        case .kugou: return Color(red: 0.18, green: 0.55, blue: 0.94)
        case .soda: return Color(red: 1.00, green: 0.30, blue: 0.40)
        }
    }
}
