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

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var queue: [Song] = []
    private var index = 0
    private var loadTask: Task<Void, Never>?
    private var lyricTask: Task<Void, Never>?
    private var urlCache: [String: URL] = [:]
    private var toastTask: Task<Void, Never>?

    override init() {
        super.init()
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
    }

    // MARK: - Control

    func play(_ song: Song, in list: [Song]) {
        queue = list.isEmpty ? [song] : list
        index = queue.firstIndex(of: song) ?? 0
        load(song)
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
            isPlaying = true
        }
        refreshNowPlayingPlayback()
    }

    func next() {
        guard !queue.isEmpty else { return }
        index = (index + 1) % queue.count
        load(queue[index])
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentTime > 4 {
            seek(to: 0)
            return
        }
        index = (index - 1 + queue.count) % queue.count
        load(queue[index])
    }

    func seek(to seconds: Double) {
        guard player.currentItem != nil else { return }
        let clamped = max(0, min(seconds, max(duration, 0.1)))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        currentTime = clamped
        updateLyricIndex(clamped)
        refreshNowPlayingPlayback()
    }

    // MARK: - Loading

    private func load(_ song: Song) {
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
        updateNowPlayingMetadata()

        loadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let url: URL
                if let cached = self.urlCache[song.FileHash] {
                    url = cached
                } else {
                    url = try await KGService.playURL(hash: song.FileHash, albumID: song.AlbumID)
                    if self.urlCache.count > 30 { self.urlCache.removeAll() }
                    self.urlCache[song.FileHash] = url
                }
                if Task.isCancelled { return }
                let item = AVPlayerItem(url: url)
                item.preferredForwardBufferDuration = 3
                self.player.replaceCurrentItem(with: item)
                self.player.play()
                self.isLoading = false
                let seconds = item.duration.seconds
                if seconds.isFinite, seconds > 0 { self.duration = seconds }
                self.isPlaying = true
                self.updateNowPlayingMetadata()
                self.refreshNowPlayingPlayback()
                self.prefetchNext()
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
        updateLyricIndex(seconds)
        if Int(seconds) % 5 == 0 { refreshNowPlayingPlayback() }
    }

    private func updateLyricIndex(_ seconds: Double) {
        guard !lyric.isEmpty else { return }
        var target = 0
        for (offset, line) in lyric.enumerated() {
            if line.time <= seconds + 0.05 { target = offset } else { break }
        }
        if target != lyricIndex { lyricIndex = target }
    }

    @objc private func handleEnded() {
        next()
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
            guard let url = try? await KGService.playURL(hash: song.FileHash, albumID: song.AlbumID) else { return }
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
            self?.player.play(); self?.isPlaying = true; self?.refreshNowPlayingPlayback(); return .success
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
        ]
        if let url = song.coverURL {
            info[MPMediaItemPropertyArtwork] = makeArtwork(url)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func refreshNowPlayingPlayback() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1 : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func makeArtwork(_ url: URL) -> MPMediaItemArtwork? {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
