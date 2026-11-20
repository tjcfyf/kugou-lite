import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class PlayerEngine: NSObject, ObservableObject {
    static let shared = PlayerEngine()

    @Published private(set) var current: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var lyric: [LyricLine] = []
    @Published private(set) var lyricIndex: Int = 0
    @Published var errorMessage: String?
    @Published var toast: String?
    @Published private(set) var sleepDeadline: Date?
    @Published private(set) var sleepAfterCurrent = false
    @Published private(set) var sleepWaitForTrackEnd = UserDefaults.standard.bool(forKey: Preferences.sleepWaitKey)
    @Published private(set) var lyricOffsetMs = Preferences.lyricOffsetMs
    @Published private(set) var currentQuality: String = ""
    @Published private(set) var playMode: PlayMode = Preferences.playMode
    @Published private(set) var playbackRate: Float = Preferences.playbackRate

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var queue: [Song] = []
    private var index = 0

    var queueSongs: [Song] { queue }
    var currentIndex: Int { index }
    private var loadTask: Task<Void, Never>?
    private var lyricTask: Task<Void, Never>?
    private var urlCache: [String: URL] = [:]
    private var recentAutoIndices: [Int] = []
    private var toastTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?

    override init() {
        super.init()
        // 应用启动时就把网络探针跑起来，保证第一次断网点歌也能立刻失败。
        _ = NetworkStatus.shared
        configureAudioSession()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.tick(time)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEnded),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        registerRemoteCommands()
    }

    deinit {
        if let observer = timeObserver { player.removeTimeObserver(observer) }
        NotificationCenter.default.removeObserver(self)
        artworkTask?.cancel()
    }

    // MARK: - Control

    func play(_ song: Song, in list: [Song]) {
        queue = list.isEmpty ? [song] : list
        index = queue.firstIndex(of: song) ?? 0
        load(song, resume: false)
    }

    func toggle() {
        guard player.currentItem != nil else {
            if let song = current { load(song) }
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
        refreshNowPlayingPlayback()
    }

    func next() {
        advance(automatic: false)
    }

    func cyclePlayMode() {
        setPlayMode(playMode.next)
    }

    func setPlayMode(_ mode: PlayMode) {
        playMode = mode
        Preferences.playMode = mode
        showToast("播放模式：\(mode.title)")
    }

    func setPlaybackRate(_ rate: Float) {
        let clamped = min(max(rate, 0.5), 2.0)
        playbackRate = clamped
        Preferences.playbackRate = clamped
        if isPlaying {
            player.rate = clamped
            refreshNowPlayingPlayback()
        }
        let title = PlaybackSpeed.allCases.first(where: { abs($0.rawValue - clamped) < 0.01 })?.title
            ?? String(format: "%.2gx", clamped)
        showToast("播放速度：\(title)")
    }

    private func advance(automatic: Bool) {
        guard !queue.isEmpty else { return }
        if playMode == .shuffle, queue.count > 1 {
            let candidates = queue.indices.filter { $0 != index && !recentAutoIndices.contains($0) }
            index = (candidates.isEmpty ? queue.indices.filter { $0 != index } : candidates).randomElement() ?? index
            recentAutoIndices.append(index)
            if recentAutoIndices.count > 6 { recentAutoIndices.removeFirst() }
            load(queue[index], resume: false)
            return
        }
        if automatic, playMode == .sequential, index == queue.count - 1 {
            player.pause()
            isPlaying = false
            seek(to: 0)
            showToast("已是最后一首")
            return
        }
        index = (index + 1) % queue.count
        load(queue[index], resume: false)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        index = (index - 1 + queue.count) % queue.count
        load(queue[index], resume: false)
    }

    func setSleepTimer(minutes: Int?) {
        sleepAfterCurrent = false
        sleepDeadline = minutes.flatMap { Date().addingTimeInterval(Double($0) * 60) }
    }

    func setSleepWaitForTrackEnd(_ enabled: Bool) {
        sleepWaitForTrackEnd = enabled
        UserDefaults.standard.set(enabled, forKey: Preferences.sleepWaitKey)
    }

    func setLyricOffset(milliseconds: Int) {
        let clamped = max(-3000, min(3000, milliseconds))
        lyricOffsetMs = clamped
        Preferences.lyricOffsetMs = clamped
        updateLyricIndex(currentTime)
    }

    func retryCurrent() {
        guard let song = current else { return }
        guard NetworkStatus.shared.isConnected else {
            showToast("还没有联网")
            return
        }
        urlCache[song.FileHash] = nil
        errorMessage = nil
        // 和重新点歌保持一致，不能带着上次的播放位置去续播，
        // 否则可能拿到试听片段后直接跳到中后段，被服务端当成付费内容。
        load(song, resume: false)
    }

    /// 只打乱当前这首之后的顺序，当前播放位置和已听过的队列保持不变。
    func shuffleUpcomingQueue() {
        guard index + 1 < queue.count else {
            showToast("后面没有可打乱的歌曲")
            return
        }
        let head = Array(queue[...index])
        let tail = Array(queue[(index + 1)...]).shuffled()
        queue = head + tail
        showToast("已打乱后面 \(tail.count) 首")
    }

    func removeFromQueue(at target: Int) {
        guard queue.indices.contains(target) else { return }
        let removingCurrent = target == index
        queue.remove(at: target)
        if queue.isEmpty {
            player.pause()
            player.replaceCurrentItem(with: nil)
            current = nil
            isPlaying = false
            index = 0
            return
        }
        if target < index {
            index -= 1
        } else if removingCurrent {
            index = min(index, queue.count - 1)
            load(queue[index], resume: false)
        }
    }

    func clearQueue() {
        queue.removeAll()
        index = 0
        player.pause()
        player.replaceCurrentItem(with: nil)
        current = nil
        isPlaying = false
    }

    /// 插到当前歌曲后面，下一首就放它。
    func playNext(_ song: Song) {
        guard let playing = current else {
            play(song, in: [song])
            return
        }
        guard playing.FileHash != song.FileHash else {
            showToast("这首正在播放")
            return
        }
        queue.removeAll { $0.FileHash == song.FileHash }
        if let newIndex = queue.firstIndex(where: { $0.FileHash == playing.FileHash }) {
            index = newIndex
        }
        queue.insert(song, at: min(index + 1, queue.count))
        showToast("下一首播放：\(song.SongName)")
    }

    func appendToQueue(_ song: Song) {
        if queue.isEmpty {
            play(song, in: [song])
            return
        }
        guard !queue.contains(where: { $0.FileHash == song.FileHash }) else {
            showToast("已在播放列表里")
            return
        }
        queue.append(song)
        showToast("已加入播放列表末尾")
    }

    func jump(to target: Int) {
        guard queue.indices.contains(target) else { return }
        index = target
        load(queue[target], resume: false)
    }

    func clearURLCache() {
        urlCache.removeAll()
    }

    /// 切音质后重载当前这首，并用新的码率继续播。
    func reloadCurrentAfterQualityChange() {
        guard let song = current else { return }
        load(song, resume: true)
    }

    func seek(to seconds: Double) {
        guard player.currentItem != nil else { return }
        let clamped = max(0, min(seconds, max(duration, 0.1)))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        if isPlaying { player.rate = playbackRate }
        currentTime = clamped
        updateLyricIndex(clamped)
        refreshNowPlayingPlayback()
    }

    // MARK: - Loading

    private func load(_ song: Song, resume: Bool = false) {
        loadTask?.cancel()
        lyricTask?.cancel()

        // 先把上一首停下来：否则请求播放地址的那一两秒里旧歌还在响。
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false

        current = song
        lyric = []
        lyricIndex = 0
        currentTime = 0
        duration = Double(song.Duration ?? 0)
        isLoading = true
        errorMessage = nil

        guard NetworkStatus.shared.isConnected else {
            isLoading = false
            isPlaying = false
            errorMessage = "当前没有网络，联网后点重试"
            showToast("当前没有网络")
            return
        }

        updateNowPlayingMetadata()

        loadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let url: URL
                if let cached = self.urlCache[song.FileHash] {
                    url = cached
                } else {
                    url = try await KGService.playURL(for: song)
                    if self.urlCache.count > 30 { self.urlCache.removeAll() }
                    self.urlCache[song.FileHash] = url
                }
                if Task.isCancelled { return }
                let item = AVPlayerItem(url: url)
                item.preferredForwardBufferDuration = 3
                item.audioTimePitchAlgorithm = .spectral
                self.player.replaceCurrentItem(with: item)
                self.currentQuality = KGService.quality(for: song.FileHash) ?? ""
                let saved = resume ? PlaybackMemory.position(for: song.FileHash) : 0
                let total = Double(song.Duration ?? 0)
                if saved > 5, total <= 0 || saved < total - 5 {
                    _ = await self.player.seek(to: CMTime(seconds: saved, preferredTimescale: 600),
                                               toleranceBefore: .zero, toleranceAfter: .zero)
                    self.currentTime = saved
                }
                self.player.play()
                self.player.rate = self.playbackRate
                self.isLoading = false
                LibraryStore.shared.addRecent(song)
                let seconds = item.duration.seconds
                if seconds.isFinite, seconds > 0 { self.duration = seconds }
                self.isPlaying = true
                self.updateNowPlayingMetadata()
                self.refreshNowPlayingPlayback()
                self.prefetchNext()

                // 概念版的做法：播放时顺手领一次当日会员，每天一次。
                Task {
                    let result = await KGVIP.claimIfNeeded()
                    if result == .claimed {
                        self.showToast("已自动领取今日会员")
                    }
                }
            } catch {
                if Task.isCancelled { return }
                self.isLoading = false
                self.isPlaying = false
                let message = (error as? LocalizedError)?.errorDescription ?? "加载失败"
                self.errorMessage = message
                self.showToast(message)
            }
        }

        lyricTask = Task { [weak self] in
            guard let self = self else { return }
            guard let lines = try? await KGService.lyric(hash: song.FileHash, title: song.SongName) else { return }
            if Task.isCancelled { return }
            self.lyric = lines
        }
    }

    // MARK: - Ticking

    private func tick(_ time: CMTime) {
        if let item = player.currentItem, item.status == .failed {
            if errorMessage == nil {
                isPlaying = false
                isLoading = false
                errorMessage = "这首歌暂时无法播放"
                if let hash = current?.FileHash { urlCache[hash] = nil }
                showToast("这首歌暂时无法播放，换一首试试")
            }
            return
        }
        let seconds = time.seconds
        guard seconds.isFinite else { return }
        currentTime = seconds
        if duration <= 0, let item = player.currentItem {
            let value = item.duration.seconds
            if value.isFinite, value > 0 { duration = value }
        }
        if let deadline = sleepDeadline, Date() >= deadline {
            sleepDeadline = nil
            if sleepWaitForTrackEnd {
                sleepAfterCurrent = true
                showToast("睡眠定时已到，等本首播完再暂停")
            } else {
                player.pause()
                isPlaying = false
                showToast("睡眠定时已到，已暂停")
            }
        }
        updateLyricIndex(seconds)
        if Int(seconds) % 5 == 0 {
            refreshNowPlayingPlayback()
            if let hash = current?.FileHash { PlaybackMemory.save(seconds, for: hash) }
        }
    }

    private func updateLyricIndex(_ seconds: Double) {
        guard !lyric.isEmpty else { return }
        var target = 0
        let adjusted = seconds + Double(lyricOffsetMs) / 1000
        for (offset, line) in lyric.enumerated() {
            if line.time <= adjusted + 0.05 { target = offset } else { break }
        }
        if target != lyricIndex { lyricIndex = target }
    }

    @objc private func handleEnded() {
        if let deadline = sleepDeadline, Date() >= deadline {
            sleepDeadline = nil
            if !sleepWaitForTrackEnd {
                player.pause()
                isPlaying = false
                showToast("睡眠定时已到，已暂停")
                return
            }
            sleepAfterCurrent = true
        }
        if sleepAfterCurrent {
            sleepAfterCurrent = false
            player.pause()
            isPlaying = false
            if let hash = current?.FileHash { PlaybackMemory.clear(hash) }
            showToast("已播完当前歌曲，已暂停")
            return
        }
        if playMode == .single {
            seek(to: 0)
            player.play()
            player.rate = playbackRate
            isPlaying = true
            return
        }
        if let hash = current?.FileHash { PlaybackMemory.clear(hash) }
        advance(automatic: true)
    }

    func moveQueue(from source: IndexSet, to destination: Int) {
        guard let playing = current else { return }
        var updated = queue
        updated.move(fromOffsets: source, toOffset: destination)
        queue = updated
        if let newIndex = queue.firstIndex(where: { $0.FileHash == playing.FileHash }) {
            index = newIndex
        }
    }

    // MARK: - Helpers

    /// 提前把下一首的播放地址取回来，切歌时直接命中缓存。
    private func prefetchNext() {
        guard queue.count > 1 else { return }
        let nextIndex = (index + 1) % queue.count
        let song = queue[nextIndex]
        guard urlCache[song.FileHash] == nil else { return }
        Task(priority: .utility) { [weak self] in
            guard let self = self else { return }
            guard let url = try? await KGService.playURL(for: song) else { return }
            self.urlCache[song.FileHash] = url
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if Task.isCancelled { return }
            self?.toast = nil
        }
    }

    // MARK: - Audio session & remote

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.player.play()
            self.player.rate = self.playbackRate
            self.isPlaying = true
            self.refreshNowPlayingPlayback()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.player.pause(); self?.isPlaying = false; self?.refreshNowPlayingPlayback(); return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    private func updateNowPlayingMetadata() {
        guard let song = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.SongName,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // 封面必须异步取：断网时 Data(contentsOf:) 会卡住主线程，整页无响应。
        artworkTask?.cancel()
        guard let url = song.coverURL else { return }
        artworkTask = Task { [weak self] in
            guard let self = self else { return }
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            let result = try? await URLSession.shared.data(for: request)
            guard !Task.isCancelled, self.current?.FileHash == song.FileHash,
                  let data = result?.0, let image = UIImage(data: data) else { return }
            var latest = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            latest[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = latest
        }
    }

    private func refreshNowPlayingPlayback() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = playbackRate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

}
