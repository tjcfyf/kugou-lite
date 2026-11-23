import AVFoundation
import Foundation

/// 本地 UVR MDX 离线分离器。
///
/// 当前模型是 `UVR_MDXNET_1_9703` 的 2048-bin Core ML 版：
/// 4096 点 STFT / hop 1024 / 256 帧，输入 `[1,4,2048,256]`。
/// 相比 Voc_FT 的 3072-bin，计算量和内存都接近减半，
/// iPhone 12 上整首歌的目标是 20–30 秒；第一次处理后会缓存双轨。
final class AIOfflineSeparator {
    static let shared = AIOfflineSeparator()

    struct Playback {
        let composition: AVMutableComposition
        let vocalTrack: AVAssetTrack
        let accompanimentTrack: AVAssetTrack
        let duration: CMTime
    }

    private let queue = DispatchQueue(label: "sonora.aioffline", qos: .userInitiated)
    private var engine: MDXEngine?
    private(set) var lastError: String?

    private init() {}

    var isModelLoaded: Bool { engine != nil }
    var engineName: String {
        engine is MDXCoreMLRunner ? "UVR_MDXNET_9703 · Core ML" : "未加载"
    }

    func prepareModelAsync() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                let ok = self.loadModel()
                DispatchQueue.main.async { continuation.resume(returning: ok) }
            }
        }
    }

    private func loadModel() -> Bool {
        if engine != nil { return true }
        if let coreml = MDXCoreMLRunner(), coreml.warmUp() {
            engine = coreml
            lastError = nil
            return true
        }
        if let cpu = MDXCoreMLRunner(onlyCPU: true), cpu.warmUp() {
            engine = cpu
            lastError = "Neural Engine 自检失败，已切到 CPU 模式（速度会慢一些）"
            return true
        }
        lastError = "Core ML 模型加载或自检失败（\(MDXModel.bundleName)）"
        return false
    }

    /// 取缓存或执行一次完整分离。progress 会在后台线程调用，调用方自行切主线程。
    func prepare(song: Song, sourceURL: URL,
                 progress: @escaping (Double, String) -> Void) async throws -> Playback {
        let local = try await localAudio(sourceURL: sourceURL, song: song)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let playback = try self.prepareOnQueue(song: song, localAudio: local, progress: progress)
                    DispatchQueue.main.async { continuation.resume(returning: playback) }
                } catch {
                    let detail = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    self.lastError = detail
                    DispatchQueue.main.async { continuation.resume(throwing: error) }
                }
            }
        }
    }

    private func prepareOnQueue(song: Song, localAudio: URL,
                                progress: @escaping (Double, String) -> Void) throws -> Playback {
        let dir = try cacheDirectory(song: song)
        let vocalURL = dir.appendingPathComponent("vocals.wav")
        let instURL = dir.appendingPathComponent("instrumental.wav")
        if isComplete(vocalURL), isComplete(instURL) {
            progress(1, "使用已缓存的双轨")
            return try makeComposition(vocalURL: vocalURL, instrumentalURL: instURL)
        }
        try? FileManager.default.removeItem(at: vocalURL)
        try? FileManager.default.removeItem(at: instURL)

        guard loadModel() else { throw Failure.model }
        progress(0.02, "读取音频")
        let decoded = try decode(url: localAudio)
        progress(0.06, "解码完成，准备分离")

        guard let engine else { throw Failure.model }
        progress(0.08, "分离中 0/0")
        try MDXSeparator.separateToWAV(left: decoded.left, right: decoded.right,
                                       model: engine, instrumentalURL: instURL, vocalURL: vocalURL,
                                       progress: progress)
        progress(0.98, "准备双轨播放")
        return try makeComposition(vocalURL: vocalURL, instrumentalURL: instURL)
    }

    private func localAudio(sourceURL: URL, song: Song) async throws -> URL {
        if sourceURL.isFileURL { return sourceURL }
        let dir = try audioCacheDirectory()
        let ext = audioExtension(for: sourceURL, mimeType: nil)
        let target = dir.appendingPathComponent(safeName(song.FileHash) + "." + ext)
        if FileManager.default.fileExists(atPath: target.path),
           (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.intValue ?? 0 > 65_536,
           !AVURLAsset(url: target).tracks(withMediaType: .audio).isEmpty {
            return target
        }
        try? FileManager.default.removeItem(at: target)

        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 45
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        let (temporary, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw Failure.download("音频下载失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)）")
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 65_536 else { throw Failure.download("音频下载不完整（\(size) 字节）") }

        // URLSession 的临时文件没有扩展名，AVURLAsset 对本地文件很依赖扩展名；
        // 先按 Content-Type/URL 改成 .mp3/.m4a/.flac，再判断是否能解出音轨。
        let ext = audioExtension(for: sourceURL, mimeType: http.mimeType)
        let finalURL = dir.appendingPathComponent(safeName(song.FileHash) + "." + ext)
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.moveItem(at: temporary, to: finalURL)
        let asset = AVURLAsset(url: finalURL)
        guard asset.tracks(withMediaType: .audio).first != nil else {
            try? FileManager.default.removeItem(at: finalURL)
            throw Failure.download("下载到的文件不是可解码音频（\(ext)）")
        }
        return finalURL
    }

    private func audioExtension(for url: URL, mimeType: String?) -> String {
        let type = (mimeType ?? "").lowercased()
        if type.contains("mpeg") || type.contains("mp3") { return "mp3" }
        if type.contains("mp4") || type.contains("m4a") || type.contains("aac") { return "m4a" }
        if type.contains("flac") { return "flac" }
        if type.contains("wav") { return "wav" }
        let ext = url.pathExtension.lowercased()
        if ["mp3", "m4a", "aac", "flac", "wav", "ogg", "opus"].contains(ext) { return ext }
        return "mp3"
    }

    private func makeComposition(vocalURL: URL, instrumentalURL: URL) throws -> Playback {
        let vocalAsset = AVURLAsset(url: vocalURL)
        let instAsset = AVURLAsset(url: instrumentalURL)
        guard let vocalSource = vocalAsset.tracks(withMediaType: .audio).first,
              let instSource = instAsset.tracks(withMediaType: .audio).first else {
            throw Failure.audioTrack
        }
        let composition = AVMutableComposition()
        guard let vocalTrack = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid),
              let instTrack = composition.addMutableTrack(withMediaType: .audio,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw Failure.audioTrack
        }
        let duration = min(CMTimeGetSeconds(vocalAsset.duration), CMTimeGetSeconds(instAsset.duration))
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
        try vocalTrack.insertTimeRange(range, of: vocalSource, at: .zero)
        try instTrack.insertTimeRange(range, of: instSource, at: .zero)
        return Playback(composition: composition, vocalTrack: vocalTrack,
                        accompanimentTrack: instTrack, duration: range.duration)
    }

    private func decode(url: URL) throws -> (left: [Float], right: [Float]) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { throw Failure.audioTrack }
        let seconds = CMTimeGetSeconds(asset.duration)
        let expected = max(Int((seconds.isFinite ? seconds : 0) * MDXSeparator.sampleRate), 0)

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: MDXSeparator.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw Failure.decode }
        reader.add(output)
        guard reader.startReading() else { throw Failure.decode }

        var left = [Float](); left.reserveCapacity(expected)
        var right = [Float](); right.reserveCapacity(expected)
        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(sample) }
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0, let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var lengthAtOffset = 0
            var totalLength = 0
            var pointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(block, atOffset: 0,
                                                     lengthAtOffsetOut: &lengthAtOffset,
                                                     totalLengthOut: &totalLength,
                                                     dataPointerOut: &pointer)
            guard status == kCMBlockBufferNoErr, let pointer else { continue }
            let floatPointer = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
            let availableFrames = min(frames, totalLength / (2 * MemoryLayout<Float>.size))
            for i in 0..<availableFrames {
                left.append(floatPointer[2 * i])
                right.append(floatPointer[2 * i + 1])
            }
        }
        if reader.status == .failed { throw Failure.decode }
        guard !left.isEmpty else { throw MDXSeparator.Failure.emptyAudio }
        return (left, right)
    }

    private func isComplete(_ url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber, size.intValue > 44,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 12), data.count == 12,
              data.prefix(4) == Data("RIFF".utf8) else { return false }
        var declared: UInt32 = 0
        for k in 0..<4 { declared |= UInt32(data[4 + k]) << (8 * UInt32(k)) }
        return Int64(declared) + 8 <= size.int64Value
    }

    private func cacheDirectory(song: Song) throws -> URL {
        let base = try applicationSupport()
            .appendingPathComponent("Sonora/Separated", isDirectory: true)
            .appendingPathComponent(safeName(song.FileHash), isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func audioCacheDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sonora/Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func applicationSupport() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func safeName(_ raw: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "._-")
        let mapped = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(mapped.prefix(96))
        return value.isEmpty ? "song" : value
    }

    enum Failure: Error, LocalizedError {
        case model
        case audioTrack
        case decode
        case download(String)

        var errorDescription: String? {
            switch self {
            case .model: return "MDX 模型未加载"
            case .audioTrack: return "缓存双轨缺少音轨"
            case .decode: return "音频解码失败"
            case .download(let detail): return detail
            }
        }
    }
}
