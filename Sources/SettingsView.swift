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

struct SleepWaitForTrackEndToggle: View {
    @EnvironmentObject private var player: PlayerEngine

    var body: some View {
        Toggle(isOn: Binding(
            get: { player.sleepWaitForTrackEnd },
            set: { player.setSleepWaitForTrackEnd($0) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text("定时到点后，等本首播完再暂停")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text)
                Text(player.sleepWaitForTrackEnd ? "到点不会立刻切停，播完当前歌曲再暂停" : "关闭时到点立即暂停")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
    }
}

struct GestureSettingsCard: View {
    @AppStorage(Preferences.coverSwipeKey) private var swipeEnabled = true
    @AppStorage(Preferences.coverDoubleTapKey) private var doubleTapEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放页手势")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)

            Toggle(isOn: $swipeEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("左右滑动封面切歌")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text)
                    Text("左滑下一首，右滑上一首")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))

            Divider().background(Theme.separator)

            Toggle(isOn: $doubleTapEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("双击封面暂停 / 播放")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text)
                    Text("双击专辑封面切换播放状态")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))

            Text(swipeEnabled && doubleTapEnabled
                 ? "手势模式已开启：播放页隐藏底部控制按钮，歌词自动上移，只保留顶部设置和播放列表入口"
                 : "两个开关都打开后，播放页会隐藏底部控制按钮，改用滑动切歌和双击暂停")
                .font(.system(size: 11))
                .foregroundColor(swipeEnabled && doubleTapEnabled ? Theme.accent.opacity(0.9) : Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frostedGlass(cornerRadius: 18)
    }
}

struct KeepAwakeSettingsCard: View {
    @AppStorage(Preferences.keepAwakeKey) private var keepAwake = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放页")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.text)
            Toggle(isOn: $keepAwake) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("保持屏幕常亮")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text)
                    Text("听着歌看歌词时不自动锁屏，退出播放页后恢复系统设置")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frostedGlass(cornerRadius: 18)
    }
}

struct LyricOffsetSettingsCard: View {
    @EnvironmentObject private var player: PlayerEngine
    @AppStorage(Preferences.lyricFollowKey) private var autoFollow = true

    private var offsetText: String {
        String(format: "%+.1f 秒", Double(player.lyricOffsetMs) / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("歌词时间校准")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text(offsetText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(player.lyricOffsetMs == 0 ? Theme.secondaryText : Theme.accent)
            }

            HStack(spacing: 8) {
                Button {
                    player.setLyricOffset(milliseconds: player.lyricOffsetMs - 500)
                } label: {
                    Text("歌词延后 0.5s")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.chip)
                        .cornerRadius(9)
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(player.lyricOffsetMs <= -3000)

                Button {
                    player.setLyricOffset(milliseconds: 0)
                } label: {
                    Text("复位")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.chip)
                        .cornerRadius(9)
                }
                .buttonStyle(GlassPressButtonStyle())

                Button {
                    player.setLyricOffset(milliseconds: player.lyricOffsetMs + 500)
                } label: {
                    Text("歌词提前 0.5s")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.chip)
                        .cornerRadius(9)
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(player.lyricOffsetMs >= 3000)
            }

            Text("正数表示歌词提前，负数表示延后；只影响播放页歌词高亮，不改动歌词文件。")
                .font(.system(size: 10))
                .foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(Theme.separator)

            Toggle(isOn: $autoFollow) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("歌词自动跟随")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text)
                    Text("关闭后可以手动上下滚动查看歌词，不再自动跳到当前句")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: Theme.accent))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frostedGlass(cornerRadius: 18)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var player: PlayerEngine
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Preferences.themeModeKey) private var themeRaw = AppTheme.system.rawValue
    @State private var quality: AudioQuality = Preferences.quality
    @State private var lyricSize: LyricTextSize = Preferences.lyricSize
    @State private var customMinutes = 45
    @State private var toast = ""
    @State private var showDiagnostics = false

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    appearanceCard
                    GestureSettingsCard()
                    KeepAwakeSettingsCard()
                    playModeCard
                    speedCard
                    qualityCard
                    lyricCard
                    LyricOffsetSettingsCard()
                    sleepCard
                    storageCard
                    accountCard

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
            .sheet(isPresented: $showDiagnostics) {
                VipDiagnosticsSheet()
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { player.setSettingsVisible(true) }
        .onDisappear { player.setSettingsVisible(false) }
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
                    .buttonStyle(GlassPressButtonStyle())
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
                    .buttonStyle(GlassPressButtonStyle())
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
                    .buttonStyle(GlassPressButtonStyle())
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
                .buttonStyle(GlassPressButtonStyle())
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
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
        }
    }

    private var sleepCard: some View {
        card(title: "睡眠定时") {
            HStack {
                if player.sleepAfterCurrent {
                    Text("播完本首")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Theme.accent)
                } else {
                    SleepCountdownText(deadline: player.sleepDeadline)
                }
                Spacer()
                Text(player.sleepAfterCurrent ? "本首播完即暂停" : (player.sleepDeadline == nil ? "未设定时" : (player.sleepWaitForTrackEnd ? "到点后等本首播完" : "到点自动暂停")))
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
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
            SleepWaitForTrackEndToggle()

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
                .buttonStyle(GlassPressButtonStyle())
            }
        }
    }

    private var accountCard: some View {
        card(title: "账号与诊断") {
            Button {
                showDiagnostics = true
            } label: {
                settingRow(title: "会员领取诊断", icon: "stethoscope")
            }
            .buttonStyle(GlassPressButtonStyle())

            Divider().background(Theme.separator)

            Button {
                guard auth.isLoggedIn else {
                    toast = "当前未登录"
                    flashToast()
                    return
                }
                auth.signOut()
                toast = "已退出登录"
                flashToast()
            } label: {
                settingRow(title: auth.isLoggedIn ? "退出登录" : "未登录",
                           icon: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(GlassPressButtonStyle())
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
            .buttonStyle(GlassPressButtonStyle())

            Divider().background(Theme.separator)

            Button {
                player.clearURLCache()
                toast = "已清空播放缓存"
                flashToast()
            } label: {
                settingRow(title: "清空播放缓存", icon: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(GlassPressButtonStyle())
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
        .frostedGlass(cornerRadius: 18)
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
                LazyVStack(spacing: 16) {
                    GestureSettingsCard()
                    KeepAwakeSettingsCard()
                    playModeCard
                    sleepCard
                    speedCard
                    lyricCard
                    LyricOffsetSettingsCard()
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
        .onAppear { player.setSettingsVisible(true) }
        .onDisappear { player.setSettingsVisible(false) }
    }

    private var sleepCard: some View {
        card(title: "睡眠定时") {
            HStack {
                if player.sleepAfterCurrent {
                    Text("播完本首")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Theme.accent)
                } else {
                    SleepCountdownText(deadline: player.sleepDeadline)
                }
                Spacer()
                Text(player.sleepAfterCurrent ? "本首播完即暂停" : (player.sleepDeadline == nil ? "未设定时" : (player.sleepWaitForTrackEnd ? "到点后等本首播完" : "到点自动暂停")))
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
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
            SleepWaitForTrackEndToggle()
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
                .buttonStyle(GlassPressButtonStyle())
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
                    .buttonStyle(GlassPressButtonStyle())
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
                            .padding(.vertical, 8)
                            .background(player.playbackRate == item.rawValue ? Theme.accent : Theme.chip)
                            .cornerRadius(9)
                    }
                    .buttonStyle(GlassPressButtonStyle())
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
                    .buttonStyle(GlassPressButtonStyle())
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
                .buttonStyle(GlassPressButtonStyle())
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
        .frostedGlass(cornerRadius: 18)
    }
}


private struct VipDiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report = "正在诊断，预计需要十几秒…"
    @State private var finished = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !finished {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
                            Text("正在检查领取链路…")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.secondaryText)
                        }
                    }
                    Text(report)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.text.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("会员领取诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .task {
            report = await KGVIP.probeReport()
            finished = true
        }
    }
}
