import SwiftUI

/// 当前歌曲的评论页。只读展示酷狗评论，不提供发表入口。
struct CommentsView: View {
    let song: Song

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [SongComment] = []
    @State private var total = 0
    @State private var page = 0
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var replyTarget: SongComment?

    private let pageSize = 20

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                Divider().background(Theme.separator)
                content
            }
        }
        .task(id: song.FileHash) {
            await load(reset: true)
        }
        .sheet(item: $replyTarget) { comment in
            CommentRepliesView(song: song, comment: comment)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())

            Spacer()

            VStack(spacing: 2) {
                Text("评论")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(song.SongName)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: 190)
            }

            Spacer()

            Text(total > 0 ? "\(total)" : "")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && comments.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                Text("正在加载评论…")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, comments.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.tertiaryText)
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    Task { await load(reset: true) }
                } label: {
                    Text("重新加载")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.onAccent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Theme.accentGradient)
                        .cornerRadius(10)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if comments.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.tertiaryText)
                Text("还没有评论")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text)
                Text("去听歌，等第一条评论出现")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(comments) { comment in
                        commentRow(comment)
                        Divider()
                            .background(Theme.separator)
                            .padding(.leading, 62)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.secondaryText)
                            .padding(.vertical, 12)
                    }

                    if hasMore {
                        Button {
                            Task { await load(reset: false) }
                        } label: {
                            HStack(spacing: 7) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                                }
                                Text(isLoading ? "加载中…" : "查看更多评论")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(GlassPressButtonStyle())
                        .disabled(isLoading)
                    } else {
                        Text("已经到底了")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.tertiaryText)
                            .padding(.vertical, 18)
                    }
                }
            }
        }
    }

    private func commentRow(_ comment: SongComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(url: comment.avatarURL, name: comment.userName)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(comment.userName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(comment.timeText)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.tertiaryText)
                }

                Text(comment.content)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if comment.replyCount > 0 {
                    Button {
                        if comment.canOpenReplies { replyTarget = comment }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 9))
                            Text("\(comment.replyCount) 条回复")
                                .font(.system(size: 10))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(comment.canOpenReplies ? Theme.accent : Theme.tertiaryText)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(GlassPressButtonStyle())
                    .disabled(!comment.canOpenReplies)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        if reset {
            errorMessage = nil
            comments = []
            total = 0
            page = 0
            hasMore = true
        }
        defer { isLoading = false }

        let nextPage = reset ? 1 : page + 1
        do {
            let result = try await KGService.comments(for: song, page: nextPage, pageSize: pageSize)
            if reset {
                comments = result.comments
            } else {
                let existing = Set(comments.map(\.id))
                comments.append(contentsOf: result.comments.filter { !existing.contains($0.id) })
            }
            total = result.total
            page = nextPage
            hasMore = result.hasMore
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "评论加载失败"
            hasMore = false
        }
    }
}

private struct CommentAvatar: View {
    let url: URL?
    let name: String

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.separator, lineWidth: 0.5))
    }

    private var placeholder: some View {
        ZStack {
            Theme.chip
            Text(String(name.prefix(1)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
        }
    }
}
