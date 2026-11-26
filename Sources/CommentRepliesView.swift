import SwiftUI

/// 单条评论的楼中楼回复页。酷狗完整回复列表来自 `hot_replylist`，
/// 每页 30 条，和主评论列表一样支持继续加载。
struct CommentRepliesView: View {
    let song: Song
    let comment: SongComment

    @Environment(\.dismiss) private var dismiss
    @State private var replies: [CommentReply] = []
    @State private var total = 0
    @State private var page = 0
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let pageSize = 30

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                Divider().background(Theme.separator)
                content
            }
        }
        .task(id: comment.id) {
            await load(reset: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .frame(width: 36, height: 36)
                        .liquidGlass(cornerRadius: 18)
                }
                .buttonStyle(AppleMusicPressStyle())
                .accessibilityLabel("关闭回复")

                Spacer()

                if total > 0 {
                    Text("\(total) 条")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
            }

            Text("回复")
                .font(.system(size: 27, weight: .bold))
                .foregroundColor(Theme.text)
                .padding(.top, 6)

            Text(comment.userName + " · " + song.SongName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && replies.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                Text("正在加载回复…")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, replies.isEmpty {
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
                        .cornerRadius(12)
                }
                .buttonStyle(GlassPressButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if replies.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.tertiaryText)
                Text("还没有回复")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    originalComment

                    ForEach(replies) { reply in
                        replyRow(reply)
                        Divider()
                            .background(Theme.separator)
                            .padding(.leading, 62)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 13))
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
                                Text(isLoading ? "加载中…" : "查看更多回复")
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
                            .font(.system(size: 12))
                            .foregroundColor(Theme.tertiaryText)
                            .padding(.vertical, 18)
                    }
                }
            }
        }
    }

    private var originalComment: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                CommentAvatar(url: comment.avatarURL, name: comment.userName)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(comment.userName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Text(comment.timeText)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.tertiaryText)
                    }
                    Text(comment.content)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.text)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("全部回复")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
                .padding(.top, 3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.chip.opacity(0.55))
    }

    private func replyRow(_ reply: CommentReply) -> some View {
        HStack(alignment: .top, spacing: 10) {
            CommentAvatar(url: reply.avatarURL, name: reply.userName)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(reply.userName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(reply.timeText)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.tertiaryText)
                }
                Text(reply.content)
                    .font(.system(size: 14))
                    .foregroundColor(Theme.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if reply.replyCount > 0 {
                    Text("\(reply.replyCount) 条回复")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.tertiaryText)
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
            replies = []
            total = 0
            page = 0
            hasMore = true
        }
        defer { isLoading = false }

        let nextPage = reset ? 1 : page + 1
        do {
            let result = try await KGService.replies(for: song, comment: comment,
                                                     page: nextPage, pageSize: pageSize)
            if reset {
                replies = result.replies
            } else {
                let existing = Set(replies.map(\.id))
                replies.append(contentsOf: result.replies.filter { !existing.contains($0.id) })
            }
            total = result.total
            page = nextPage
            hasMore = result.hasMore
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "回复加载失败"
            hasMore = false
        }
    }
}
