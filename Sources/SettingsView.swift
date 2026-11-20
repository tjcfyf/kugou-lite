import SwiftUI

/// 每秒刷新的睡眠倒计时，不依赖 Timer 状态。
struct SleepCountdownText: View {
    let deadline: Date?
    var fontSize: CGFloat = 24

    var body: some View {
        Group {
            if let deadline = deadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remain = max(0, Int(deadline.timeIntervalSince(context.date)))
                    Text(String(format: "%02d:%02d", remain / 60, remain % 60))
                        .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
            } else {
                Text("未开启")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Preferences.themeModeKey) private var themeRaw = AppTheme.system.rawValue
    @State private var quality: AudioQuality = Preferences.quality
    @State private var lyricSize: LyricTextSize = Preferences.lyricSize
    @State private var customMinutes = 45
    @State private var toast = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    appearanceCard
                    playModeCard
                    speedCard
                    qualityCard
                    lyricCard
                    sleepCard
                    storageCard

                    Text("KugouLite · iOS 15 精简版")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.top, 6)
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .overlay(alignment: .top) {
                if !toast.isEmpty { ToastView(text: toast) }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var appearanceCard: some View {
        card(title: "外观") {
            HStack(spacing: 8) {
                ForEach(AppTheme.allCases) { mode in
                    Button {
                        themeRaw = mode.rawValue
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(themeRaw == mode.rawValue ? .white : Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(themeRaw == mode.rawValue ? Theme.accent : Theme.chip)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var playModeCard: some View {
        card(title: "播放模式") {
            HStack(spacing: 8) {
                ForEach(PlayMode.allCases) { mode in
                    Button {
                        player.setPlayMode(mode)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 15, weight: .semibold))
                            Text(mode.title)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(player.playMode == mode ? .white : Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(player.playMode == mode ? Theme.accent : Theme.chip)
                        .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var speedCard: some View {
        card(title: "播放速度") {
            HStack(spacing: 8) {
                ForEach(PlaybackSpeed.allCases) { item in
                    Button {
                        player.setPlaybackRate(item.rawValue)
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12, weight: player.playbackRate == item.rawValue ? .semibold : .medium))
                            .foregroundColor(player.playbackRate == item.rawValue ? .white : Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(player.playbackRate == item.rawValue ? Theme.accent : Theme.chip)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("切换后立即生效，人声不会变调")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
        }
    }

    private var qualityCard: some View {
        card(title: "播放音质") {
            ForEach(AudioQuality.allCases) { item in
                Button {
                    quality = item
                    Preferences.quality = item
                    player.clearURLCache()
                    if player.current != nil {
                        player.reloadCurrentAfterQualityChange()
                        toast = "已切换为\(item.title)，正在重载当前歌曲"
                    } else {
                        toast = "已切换为\(item.title)"
                    }
                    flashToast()
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.text)
                        Spacer()
                        if quality == item {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("取不到高音质时会自动降到下一档")
                .font(.system(size: 11))
                .foregroundColor(Theme.secondaryText)
        }
    }

    private var lyricCard: some View {
        card(title: "歌词字号") {
            HStack(spacing: 8) {
                ForEach(LyricTextSize.allCases) { item in
                    Button {
                        lyricSize = item
                        Preferences.lyricSize = item
                    } label: {
                        VStack(spacing: 4) {
                            Text("Aa")
                                .font(.system(size: CGFloat(12 + item.rawValue * 2), weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(lyricSize == item ? .white : Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(lyricSize == item ? Theme.accent : Theme.chip)
                        .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var sleepCard: some View {
        card(title: "睡眠定时") {
            HStack {
                SleepCountdownText(deadline: player.sleepDeadline)
                Spacer()
                Text(player.sleepDeadline == nil ? "到点自动暂停" : "每秒刷新")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            HStack(spacing: 8) {
                ForEach([0, 5, 15, 30, 60], id: \.self) { minutes in
                    Button {
                        player.setSleepTimer(minutes: minutes == 0 ? nil : minutes)
                    } label: {
                        Text(minutes == 0 ? "关闭" : "\(minutes) 分")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Theme.chip)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                Stepper(value: $customMinutes, in: 1...180) {
                    Text("自定义 \(customMinutes) 分钟")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text.opacity(0.85))
                }
                Button {
                    player.setSleepTimer(minutes: customMinutes)
                    toast = "\(customMinutes) 分钟后自动暂停"
                    flashToast()
                } label: {
                    Text("开始")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.accent)
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var storageCard: some View {
        card(title: "存储") {
            Button {
                LibraryStore.shared.clear()
                toast = "已清空搜索与最近播放"
                flashToast()
            } label: {
                settingRow(title: "清空本地记录", icon: "trash")
            }
            .buttonStyle(.plain)

            Divider().background(Theme.separator)

            Button {
                player.clearURLCache()
                toast = "已清空播放缓存"
                flashToast()
            } label: {
                settingRow(title: "清空播放缓存", icon: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plain)
        }
    }

    private func settingRow(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(Theme.text)
            Spacer()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .cornerRadius(14)
    }

    private func flashToast() {
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            toast = ""
        }
    }
}

/// 播放页右上角齿轮进入的快捷设置，只放和当前播放相关的东西。
struct PlayerSettingsView: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss

    @State private var quality: AudioQuality = Preferences.quality
    @State private var lyricSize: LyricTextSize = Preferences.lyricSize
    @State private var customMinutes = 30

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    sleepCard
                    speedCard
                    lyricCard
                    qualityCard
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var sleepCard: some View {
        card(title: "睡眠定时") {
            HStack {
                SleepCountdownText(deadline: player.sleepDeadline)
                Spacer()
                Text(player.sleepDeadline == nil ? "到点自动暂停" : "实时倒计时")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
            }
            HStack(spacing: 8) {
                ForEach([0, 5, 15, 30, 60], id: \.self) { minutes in
                    Button {
                        player.setSleepTimer(minutes: minutes == 0 ? nil : minutes)
                    } label: {
                        Text(minutes == 0 ? "关闭" : "\(minutes) 分")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Theme.chip)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                Stepper(value: $customMinutes, in: 1...180) {
                    Text("自定义 \(customMinutes) 分钟")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text.opacity(0.85))
                }
                Button {
                    player.setSleepTimer(minutes: customMinutes)
                } label: {
                    Text("开始")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.accent)
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var speedCard: some View {
        card(title: "播放速度") {
            HStack(spacing: 8) {
                ForEach(PlaybackSpeed.allCases) { item in
                    Button {
                        player.setPlaybackRate(item.rawValue)
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12, weight: player.playbackRate == item.rawValue ? .semibold : .medium))
                            .foregroundColor(player.playbackRate == item.rawValue ? .white : Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(player.playbackRate == item.rawValue ? Theme.accent : Theme.chip)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lyricCard: some View {
        card(title: "歌词字号") {
            HStack(spacing: 8) {
                ForEach(LyricTextSize.allCases) { item in
                    Button {
                        lyricSize = item
                        Preferences.lyricSize = item
                    } label: {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(lyricSize == item ? .white : Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(lyricSize == item ? Theme.accent : Theme.chip)
                            .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var qualityCard: some View {
        card(title: "播放音质") {
            ForEach(AudioQuality.allCases) { item in
                Button {
                    quality = item
                    Preferences.quality = item
                    player.clearURLCache()
                    if player.current != nil {
                        player.reloadCurrentAfterQualityChange()
                    }
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.text)
                        Spacer()
                        if quality == item {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .cornerRadius(18)
    }
}
