import AVFoundation
import Foundation

/// 本地 UVR-MDX-NET-Voc_FT 离线分离器。
///
/// 与旧版 4.9 MB 实时 MSS 不同，这个模型是电脑端 UVR/MDX-Net 同款
/// `UVR-MDX-NET-Voc_FT`（6144 点 STFT、256 帧窗口）。代价是必须把整首歌
/// 预先分离并缓存；第一次处理一首 3–4 分钟的歌通常需要几十秒到几分钟，
/// 之后直接播放缓存的双轨 WAV，不再重复推理。
final class AIOfflineSeparator {
    static let shared = AIOfflineSeparator()

    struct Playback {
        let composition: AVMutableComposition
        let vocalTrack: AVAssetTrack
        let accompanimentTrack: AVAssetTrack
        let duration: CMTime
    }

    private let queue = DispatchQueue(label: "sonora.aioffline", qos: .userInitiated)
    private var model: MDXRunner?
    private(set) var lastError: String?

    private init() {}

    var isModelLoaded: Bool { model != nil }

    var modelURL: URL? {
        Bundle.main.url(forResource: "mdx-voc-ft", withExtension: "tflite")
            ?? Bundle.main.url(forResource: "mdx-voc-ft", withExtension: "tflite", subdirectory: "Resources")
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
        if model != nil { return true }
        guard let url = modelURL else {
            lastError = "MDX 模型文件缺失"
            return false
        }
        guard let loaded = MDXRunner(path: url.path) else {
            lastError = "MDX 模型加载失败（张量形状不匹配）"
            return false
        }
        model = loaded
        lastError = nil
        return true
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
                    self.lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
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

        let stems = try MDXSeparator.separate(left: decoded.left, right: decoded.right,
                                              model: model!, progress: progress)
        progress(0.96, "写入双轨")
        try writeWav(left: stems.instrumentalLeft, right: stems.instrumentalRight, gain: 1, to: instURL)
        try writeWav(left: stems.vocalLeft, right: stems.vocalRight, gain: 1, to: vocalURL)
        progress(1, "分离完成")
        return try makeComposition(vocalURL: vocalURL, instrumentalURL: instURL)
    }

    private func localAudio(sourceURL: URL, song: Song) async throws -> URL {
        if sourceURL.isFileURL { return sourceURL }
        let dir = try audioCacheDirectory()
        let target = dir.appendingPathComponent(safeName(song.FileHash) + ".audio")
        if FileManager.default.fileExists(atPath: target.path),
           (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.intValue ?? 0 > 44 {
            return target
        }
        let (temporary, _) = try await URLSession.shared.download(from: sourceURL)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: temporary, to: target)
        return target
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
        if reader.status == .failed { throw reader.error ?? Failure.decode }
        guard !left.isEmpty else { throw MDXSeparator.Failure.emptyAudio }
        return (left, right)
    }

    private func writeWav(left: [Float], right: [Float], gain: Float, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let part = url.appendingPathExtension("part")
        try? fm.removeItem(at: part)
        guard fm.createFile(atPath: part.path, contents: nil) else { throw Failure.write }
        let handle = try FileHandle(forWritingTo: part)
        do {
            try handle.write(contentsOf: Data(StereoWav.header(frames: left.count,
                                                               sampleRate: Int(MDXSeparator.sampleRate))))
            var start = 0
            while start < left.count {
                let end = min(start + 65_536, left.count)
                try handle.write(contentsOf: Data(StereoWav.pcm16(left: left, right: right,
                                                                  range: start..<end, gain: gain)))
                start = end
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? fm.removeItem(at: part)
            throw error
        }
        try? fm.removeItem(at: url)
        try fm.moveItem(at: part, to: url)
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
        case write

        var errorDescription: String? {
            switch self {
            case .model: return "MDX 模型未加载"
            case .audioTrack: return "缓存双轨缺少音轨"
            case .decode: return "音频解码失败"
            case .write: return "双轨写入失败"
            }
        }
    }
}
