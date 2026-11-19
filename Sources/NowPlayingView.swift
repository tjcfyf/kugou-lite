import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerEngine
    @State private var showQueue = false
    @State private var sleepText = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                grabber

                CoverImage(url: player.current?.coverURL, size: 250, radius: 18)
                    .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
                    .padding(.top, 8)

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(player.current?.SongName ?? "未在播放")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if let song = player.current {
                            Button {
                                let added = Preferences.toggleFavorite(song)
                                player.showToast(added ? "已收藏" : "已取消收藏")
                            } label: {
                                Image(systemName: Preferences.isFavorite(song) ? "heart.fill" : "heart")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Preferences.isFavorite(song) ? Theme.accent : Theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(player.current?.artist ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1)
                        if !player.currentQuality.isEmpty {
                            Text(player.currentQuality)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.accent.opacity(0.7), lineWidth: 0.6)
                                )
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)

                progress
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                controls
                    .padding(.top, 10)

                lyricView
                    .frame(maxHeight: .infinity)
                    .padding(.top, 8)
            }

            VStack {
                HStack(spacing: 10) {
                    Spacer()
                    if !sleepText.isEmpty {
                        Text(sleepText)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.accent)
                    }
                    Menu {
                        ForEach([0, 15, 30, 60], id: \.self) { minutes in
                            Button(minutes == 0 ? "关闭睡眠定时" : "\(minutes) 分钟后暂停") {
                                player.setSleepTimer(minutes: minutes == 0 ? nil : minutes)
                                player.showToast(minutes == 0 ? "已关闭睡眠定时" : "\(minutes) 分钟后暂停")
                            }
                        }
                    } label: {
                        Image(systemName: player.sleepDeadline == nil ? "moon" : "moon.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(player.sleepDeadline == nil ? .white.opacity(0.75) : Theme.accent)
                            .padding(10)
                    }
                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.top, 8)

            if let toast = player.toast {
                VStack {
                    ToastView(text: toast)
                    Spacer()
                }
            }
        }
        .animation(.easeOut(duration: 0.22), value: player.toast)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            QueueView().environmentObject(player)
        }
        .onReceive(timer) { _ in
            guard let deadline = player.sleepDeadline else { sleepText = ""; return }
            let remain = Int(deadline.timeIntervalSinceNow)
            if remain <= 0 { sleepText = ""; return }
            sleepText = String(format: "剩余 %02d:%02d", remain / 60, remain % 60)
        }
    }

    private var background: some View {
        ZStack {
            Theme.background
            LinearGradient(
                colors: [
                    Theme.accent.opacity(0.20),
                    Color(red: 0.12, green: 0.05, blue: 0.12),
                    Theme.background,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.25))
            .frame(width: 38, height: 5)
            .padding(.bottom, 8)
    }

    private var progress: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { player.duration > 0 ? min(player.currentTime, player.duration) : 0 },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .accentColor(Theme.accent)

            HStack {
                Text(format(player.currentTime))
                Spacer()
                Text(format(player.duration))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Theme.secondaryText)
        }
    }

    private var controls: some View {
        HStack(spacing: 44) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.85))
            }

            Button { player.toggle() } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 64, height: 64)
                    if player.isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .black))
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
            }

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
    }

    private var lyricView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if player.lyric.isEmpty {
                    Text(player.isLoading ? "正在缓冲…" : (player.errorMessage ?? "暂无歌词"))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondaryText)
                        .padding(.top, 24)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(player.lyric.enumerated()), id: \.offset) { index, line in
                            Text(line.text)
                                .font(.system(size: index == player.lyricIndex ? 17 : 15,
                                              weight: index == player.lyricIndex ? .semibold : .regular))
                                .foregroundColor(index == player.lyricIndex ? .white : Color.white.opacity(0.38))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 30)
                }
            }
            .onChange(of: player.lyricIndex) { index in
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .mask(
            LinearGradient(
                colors: [.clear, .black, .black, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
