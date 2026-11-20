import SwiftUI

/// 当前歌曲的歌词候选。KRC 候选会带“逐字”标记，选择后立即重载，不打断播放。
struct LyricSourceSheet: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if player.lyricCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("还没有候选歌词")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.text)
                            Text("先播放一首歌，或稍后点“重新获取”。酷狗歌词接口偶尔会返回空候选。")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                player.reloadLyric()
                            } label: {
                                Text("重新获取")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Theme.accent)
                                    .cornerRadius(9)
                            }
                            .buttonStyle(GlassPressButtonStyle())
                        }
                        .padding(14)
                        .appSurface(cornerRadius: 12)
                    } else {
                        ForEach(player.lyricCandidates) { candidate in
                            Button {
                                player.selectLyricSource(candidate)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(candidate.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(Theme.text)
                                            .lineLimit(2)
                                        if !candidate.subtitle.isEmpty {
                                            Text(candidate.subtitle)
                                                .font(.system(size: 11))
                                                .foregroundColor(Theme.secondaryText)
                                                .lineLimit(1)
                                        }
                                        Text("歌词 ID \(candidate.id)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(Theme.tertiaryText)
                                    }
                                    Spacer(minLength: 8)
                                    if player.lyricSourceID == candidate.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(Theme.accent)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Theme.tertiaryText)
                                            .padding(.top, 4)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .appSurface(cornerRadius: 12)
                            }
                            .buttonStyle(GlassPressButtonStyle())
                        }
                    }
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("歌词来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
