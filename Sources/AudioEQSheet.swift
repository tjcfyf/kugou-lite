import SwiftUI

struct AudioEQSheet: View {
    @EnvironmentObject private var player: PlayerEngine
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var audio = AudioEnhancer.shared
    @State private var toast = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    enableCard
                    presetCard
                    bandCard
                    noteCard
                }
                .padding(16)
            }
            .background(AppBackground())
            .navigationTitle("音频增强")
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

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { audio.isEnabled },
                set: { value in
                    audio.setEnabled(value)
                    player.reloadForAudioEnhancement()
                    toast = value ? "已开启 10 段均衡器" : "已关闭音频增强"
                    flashToast()
                }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("10 段均衡器")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(audio.isEnabled ? "实时处理 AVPlayer 音频，自动前级补偿已生效" : "关闭时不接触播放链路")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .tint(Theme.accent)

            if audio.isEnabled {
                HStack {
                    Text("前级补偿")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                    Spacer()
                    Text(String(format: "%+.2f dB", audio.preampDB))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appSurface(cornerRadius: 20)
    }

    private var presetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预设")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EQPreset.allCases) { preset in
                        Button {
                            audio.applyPreset(preset)
                        } label: {
                            Text(preset.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.text)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Theme.chip)
                                .cornerRadius(9)
                        }
                        .buttonStyle(GlassPressButtonStyle())
                    }
                    Button {
                        audio.reset()
                    } label: {
                        Text("重置")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.chip)
                            .cornerRadius(9)
                    }
                    .buttonStyle(GlassPressButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appSurface(cornerRadius: 20)
    }

    private var bandCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("频段")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                Spacer()
                Text("−12 ~ +12 dB")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.tertiaryText)
            }

            ForEach(0..<10, id: \.self) { index in
                HStack(spacing: 10) {
                    Text(AudioEnhancer.bandLabels[index])
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 34, alignment: .leading)

                    Slider(value: Binding(
                        get: { Double(audio.gains[safe: index] ?? 0) },
                        set: { audio.setGain(Float($0), at: index) }
                    ), in: -12...12)
                    .tint(Theme.accent)

                    Text(String(format: "%+.1f", audio.gains[safe: index] ?? 0))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor((audio.gains[safe: index] ?? 0) == 0 ? Theme.tertiaryText : Theme.accent)
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appSurface(cornerRadius: 20)
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("实现范围")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.secondaryText)
            Text("这版使用 MTAudioProcessingTap 在 AVPlayer 输出端处理 PCM，10 个 RBJ peaking biquad 级联，并按 20 Hz–20 kHz 的完整频响自动计算前级补偿。")
                .font(.system(size: 10))
                .foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("EchoMusic 的 LUFS 标准化、WAV/IRS 卷积和第三方音效 Provider 依赖桌面 Rust/FFmpeg DSP，iOS 15 的 AVPlayer 没有对应节点；本版没有用假开关冒充这些能力。")
                .font(.system(size: 10))
                .foregroundColor(Theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appSurface(cornerRadius: 20)
    }

    private func flashToast() {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            toast = ""
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
