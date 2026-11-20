import SwiftUI

/// 播放页右上角菜单里的睡眠模式；复用 PlayerEngine 已有的睡眠定时。
struct SleepTimerSheet: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    private let options = [15, 30, 60]

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header

                VStack(spacing: 18) {
                    statusCard
                    quickOptions
                    waitCard
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
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

            Text("睡眠模式")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.text)

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
    }

    private var statusCard: some View {
        VStack(spacing: 8) {
            SleepCountdownText(deadline: player.sleepDeadline, fontSize: 28)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.card.opacity(0.72))
        .cornerRadius(18)
    }

    private var statusText: String {
        if player.sleepAfterCurrent { return "定时已到，播完本首后暂停" }
        guard player.sleepDeadline != nil else { return "尚未设置睡眠定时" }
        return player.sleepWaitForTrackEnd ? "到点后等本首播完再暂停" : "到点立即暂停"
    }

    private var quickOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("定时关闭")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.text)

            HStack(spacing: 8) {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        player.setSleepTimer(minutes: minutes)
                        player.showToast("已设置 \(minutes) 分钟睡眠定时")
                        dismiss()
                    } label: {
                        Text("\(minutes) 分钟")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.chip)
                            .cornerRadius(10)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }

            Button {
                player.setSleepTimer(minutes: nil)
                player.showToast("已关闭睡眠定时")
                dismiss()
            } label: {
                Text("关闭睡眠定时")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.chip.opacity(0.72))
                    .cornerRadius(10)
            }
            .buttonStyle(GlassPressButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var waitCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SleepWaitForTrackEndToggle()
        }
        .padding(14)
        .background(Theme.card.opacity(0.72))
        .cornerRadius(18)
    }
}
