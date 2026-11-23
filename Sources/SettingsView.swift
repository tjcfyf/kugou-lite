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
        .appSurface(cornerRadius: 12)
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
    @State private var showLyricSource = false
    @State private var showEQ = false
    @State private var lyricFilterDraft = Preferences.lyricFilter
    @ObservedObject private var audio = AudioEnhancer.shared

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    appearanceCard
                    playModeCard
                    speedCard
                    qualityCard
                    audioCard
                    karaokeCard
                    aiCard
                    lyricCard
                    lyricSourceCard
                    lyricFilterCard
                    LyricOffsetSettingsCard()
                    storageCard
                    accountCard

                    Text("Sonora · iOS 15 · v93")
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
            .sheet(isPresented: $showLyricSource) {
                LyricSourceSheet().environmentObject(player)
            }
            .sheet(isPresented: $showEQ) {
                AudioEQSheet().environmentObject(player)
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { player.setSettingsVisible(true) }
        .onDisappear { player.setSettingsVisible(false) }
    }

    private var appearanceCard: some View {
        card(title: "外观") {
            Picker("外观", selection: $themeRaw) {
                ForEach(AppTheme.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
                        .foregroundColor(player.playMode == mode ? Theme.onAccent : Theme.text)
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
                            .foregroundColor(player.playbackRate == item.rawValue ? Theme.onAccent : Theme.text)
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

    private var audioCard: some View {
        card(title: "音频增强") {
            Toggle(isOn: Binding(
                get: { audio.isEnabled },
                set: { value in
                    audio.setEnabled(value)
                    player.reloadForAudioEnhancement()
                }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("10 段均衡器 + 前级补偿")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("实时处理 AVPlayer PCM；开启后会重载当前歌曲")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)

            Button {
                showEQ = true
            } label: {
                HStack {
                    Text("调整频段与预设")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text(String(format: "%+.1f dB", audio.preampDB))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.tertiaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(GlassPressButtonStyle())
        }
    }

    private var karaokeCard: some View {
        card(title: "伴唱") {
            Toggle(isOn: Binding(
                get: { player.karaokeEnabled },
                set: { player.setKaraokeEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("开启伴唱分离")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("官方双轨优先；没有官方双轨时才使用 AI 本地分离")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)

            HStack(spacing: 8) {
                Image(systemName: player.karaokeEnabled ? "music.mic" : "music.mic")
                    .font(.system(size: 13))
                    .foregroundColor(player.karaokeEnabled ? Theme.accent : Theme.tertiaryText)
                Text(player.karaokeEnabled ? "伴唱已开启，播放页「分离」里调音量" : "开启后播放页出现人声/伴奏音量控制")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var aiCard: some View {
        card(title: "AI 伴唱分离") {
            Toggle(isOn: Binding(
                get: { player.aiSeparationEnabled },
                set: { player.setAISeparationEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本地 MSS 人声/伴奏分离")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("官方双轨的兜底；仅在取不到官方双轨时启用")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)

            HStack(spacing: 8) {
                Image(systemName: player.aiSeparationEnabled ? "waveform" : "waveform.slash")
                    .font(.system(size: 13))
                    .foregroundColor(player.aiSeparationEnabled ? Theme.accent : Theme.tertiaryText)
                Text(player.aiSeparationEnabled
                     ? (player.aiSeparationAvailable ? "AI 已开启；官方双轨仍然优先" : "正在后台加载 AI 模型…")
                     : "当前未开启；没有官方双轨时退回中置声道")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var lyricCard: some View {
        card(title: "歌词显示") {
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
                        .foregroundColor(lyricSize == item ? Theme.onAccent : Theme.text)
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

    private var lyricSourceCard: some View {
        card(title: "歌词来源") {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentLyricSourceTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)
                        .lineLimit(2)
                    Text(player.lyricTranslationAvailable ? "含翻译，可用 KRC 逐字高亮" : "默认使用 KRC 逐字歌词，失败时回落 LRC")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button {
                    showLyricSource = true
                } label: {
                    Text("选择")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.accentGradient)
                        .cornerRadius(9)
                }
                .buttonStyle(GlassPressButtonStyle())
                .disabled(player.current == nil)
            }
        }
    }

    private var lyricFilterCard: some View {
        card(title: "歌词正则过滤") {
            TextField("例如 ^作词|^作曲，匹配的行会被隐藏", text: $lyricFilterDraft)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .appChip(cornerRadius: 9)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onSubmit { applyLyricFilter() }

            HStack(spacing: 8) {
                Button {
                    applyLyricFilter()
                } label: {
                    Text("应用")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.accentGradient)
                        .cornerRadius(9)
                }
                .buttonStyle(GlassPressButtonStyle())

                Button {
                    lyricFilterDraft = ""
                    player.setLyricFilter("")
                    toast = "已清除歌词过滤"
                    flashToast()
                } label: {
                    Text("清除")
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
    }

    private var currentLyricSourceTitle: String {
        guard let id = player.lyricSourceID,
              let candidate = player.lyricCandidates.first(where: { $0.id == id }) else {
            return player.current == nil ? "未在播放" : "自动匹配"
        }
        return candidate.song ?? "自动匹配"
    }

    private func applyLyricFilter() {
        let value = lyricFilterDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, (try? NSRegularExpression(pattern: value)) == nil {
            toast = "正则表达式无效"
            flashToast()
            return
        }
        player.setLyricFilter(value)
        toast = value.isEmpty ? "已清除歌词过滤" : "歌词过滤已应用"
        flashToast()
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
                        .foregroundColor(Theme.onAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.accentGradient)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
                .padding(.leading, 4)

            // 必须先把 content 收进一个 VStack 再套卡片样式；
            // 直接修饰 TupleView 会让每一行各自变成一张卡，Divider 也会变成一条空卡片。
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appSurface(cornerRadius: 12)
        }
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
                    playModeCard
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
                        .foregroundColor(Theme.onAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.accentGradient)
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
                        .foregroundColor(player.playMode == mode ? Theme.onAccent : Theme.text)
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
                            .foregroundColor(player.playbackRate == item.rawValue ? Theme.onAccent : Theme.text)
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

    private var aiCard: some View {
        card(title: "AI 伴唱分离") {
            Toggle(isOn: Binding(
                get: { player.aiSeparationEnabled },
                set: { player.setAISeparationEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本地 MSS 人声/伴奏分离")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("4.9MB 模型随 App 内置；开启后覆盖官方双轨/中置声道")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)

            HStack(spacing: 8) {
                Image(systemName: player.aiSeparationEnabled ? "waveform" : "waveform.slash")
                    .font(.system(size: 13))
                    .foregroundColor(player.aiSeparationEnabled ? Theme.accent : Theme.tertiaryText)
                Text(player.aiSeparationEnabled ? "当前使用 AI 本地分离" : "当前未开启；播放页「分离」里也能开关")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var lyricCard: some View {
        card(title: "歌词显示") {
            HStack(spacing: 8) {
                ForEach(LyricTextSize.allCases) { item in
                    Button {
                        lyricSize = item
                        Preferences.lyricSize = item
                    } label: {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(lyricSize == item ? Theme.onAccent : Theme.text)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
                .padding(.leading, 4)

            // 必须先把 content 收进一个 VStack 再套卡片样式；
            // 直接修饰 TupleView 会让每一行各自变成一张卡，Divider 也会变成一条空卡片。
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .appSurface(cornerRadius: 12)
        }
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
