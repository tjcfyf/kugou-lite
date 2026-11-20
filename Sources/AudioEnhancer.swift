import AVFoundation
import MediaToolbox
import Combine

struct AudioEQSnapshot {
    let enabled: Bool
    let gains: [Float]
    let version: Int
}

struct KaraokeSnapshot {
    let active: Bool
    let vocal: Float
    let accompaniment: Float
}

private struct BiquadCoefficients {
    var b0: Float
    var b1: Float
    var b2: Float
    var a1: Float
    var a2: Float

    static func peaking(frequency: Double, sampleRate: Double, gainDB: Double, q: Double = 1.0) -> BiquadCoefficients {
        let omega = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(omega) / (2 * q)
        let a = pow(10, gainDB / 40)
        let b0 = 1 + alpha * a
        let b1 = -2 * cos(omega)
        let b2 = 1 - alpha * a
        let a0 = 1 + alpha / a
        let a1 = -2 * cos(omega)
        let a2 = 1 - alpha / a
        return BiquadCoefficients(b0: Float(b0 / a0),
                                  b1: Float(b1 / a0),
                                  b2: Float(b2 / a0),
                                  a1: Float(a1 / a0),
                                  a2: Float(a2 / a0))
    }

    func magnitudeDB(at frequency: Double, sampleRate: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let one = cos(omega)
        let two = cos(2 * omega)
        let oneImag = -sin(omega)
        let twoImag = -sin(2 * omega)

        let numRe = Double(b0) + Double(b1) * one + Double(b2) * two
        let numIm = Double(b1) * oneImag + Double(b2) * twoImag
        let denRe = 1 + Double(a1) * one + Double(a2) * two
        let denIm = Double(a1) * oneImag + Double(a2) * twoImag
        let num = numRe * numRe + numIm * numIm
        let den = denRe * denRe + denIm * denIm
        guard den > 0 else { return 0 }
        return 10 * log10(max(num / den, 1e-12))
    }
}

private struct BiquadState {
    let coefficients: BiquadCoefficients
    var x1: Float = 0
    var x2: Float = 0
    var y1: Float = 0
    var y2: Float = 0

    mutating func process(_ input: Float) -> Float {
        let output = coefficients.b0 * input
            + coefficients.b1 * x1
            + coefficients.b2 * x2
            - coefficients.a1 * y1
            - coefficients.a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}

private enum AudioEQMath {
    static let frequencies: [Double] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let labels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    static func preampDB(gains: [Float], sampleRate: Double = 44100) -> Double {
        let coefficients = frequencies.enumerated().map { index, frequency in
            BiquadCoefficients.peaking(frequency: frequency,
                                       sampleRate: sampleRate,
                                       gainDB: Double(gains[safe: index] ?? 0))
        }
        var maxGain = 0.0
        for step in 0..<256 {
            let fraction = Double(step) / 255.0
            let frequency = 20.0 * pow(1000.0, fraction)
            var sum = 0.0
            for coefficient in coefficients {
                sum += coefficient.magnitudeDB(at: frequency, sampleRate: sampleRate)
            }
            maxGain = max(maxGain, sum)
        }
        return min(0, -maxGain)
    }
}

final class AudioEnhancer: ObservableObject {
    static let shared = AudioEnhancer()
    static let bandLabels = ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    @Published var isEnabled: Bool {
        didSet { persist(); rebuildSnapshot() }
    }

    @Published var gains: [Float] {
        didSet { persist(); rebuildSnapshot() }
    }

    private var snapshot = AudioEQSnapshot(enabled: false,
                                          gains: Array(repeating: 0, count: 10),
                                          version: 0)
    private var karaoke = KaraokeSnapshot(active: false, vocal: 1, accompaniment: 1)
    private let lock = NSLock()
    private var version = 0

    private init() {
        let savedEnabled = UserDefaults.standard.bool(forKey: Preferences.audioEQEnabledKey)
        let savedGains: [Float]
        if let data = UserDefaults.standard.data(forKey: Preferences.audioEQGainsKey),
           let decoded = try? JSONDecoder().decode([Float].self, from: data),
           decoded.count == AudioEQMath.frequencies.count {
            savedGains = decoded
        } else {
            savedGains = Array(repeating: 0, count: AudioEQMath.frequencies.count)
        }
        isEnabled = savedEnabled
        gains = savedGains
        snapshot = AudioEQSnapshot(enabled: savedEnabled,
                                   gains: savedGains,
                                   version: 0)
    }

    var preampDB: Double {
        AudioEQMath.preampDB(gains: gains)
    }

    func snapshotValue() -> AudioEQSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    func karaokeValue() -> KaraokeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return karaoke
    }

    /// 伴唱兼容模式：用立体声中置/侧声道近似拆出人声与伴奏。
    /// 双轨伴唱时不走这里，由 AVPlayerItem.audioMix 直接控制两条音轨。
    func setKaraoke(active: Bool, vocal: Float, accompaniment: Float) {
        lock.lock()
        karaoke = KaraokeSnapshot(active: active,
                                  vocal: min(max(vocal, 0), 1),
                                  accompaniment: min(max(accompaniment, 0), 1))
        lock.unlock()
    }

    func setGain(_ value: Float, at index: Int) {
        guard gains.indices.contains(index) else { return }
        var next = gains
        next[index] = min(max(value, -12), 12)
        gains = next
    }

    func setEnabled(_ value: Bool) {
        guard isEnabled != value else { return }
        isEnabled = value
    }

    func reset() {
        gains = Array(repeating: 0, count: AudioEQMath.frequencies.count)
    }

    func applyPreset(_ preset: EQPreset) {
        gains = preset.gains
    }

    /// 只在开启增强时给 AVPlayerItem 挂处理 tap；关闭时完全不碰播放链路。
    func attachTap(to item: AVPlayerItem, asset: AVURLAsset) {
        guard isEnabled || karaokeValue().active else { return }
        guard let track = asset.tracks(withMediaType: .audio).first else { return }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        guard let tap = makeTap() else { return }
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
    }

    private func persist() {
        UserDefaults.standard.set(isEnabled, forKey: Preferences.audioEQEnabledKey)
        if let data = try? JSONEncoder().encode(gains) {
            UserDefaults.standard.set(data, forKey: Preferences.audioEQGainsKey)
        }
    }

    private func rebuildSnapshot() {
        lock.lock()
        version += 1
        snapshot = AudioEQSnapshot(enabled: isEnabled, gains: gains, version: version)
        lock.unlock()
    }

    private func makeTap() -> MTAudioProcessingTap? {
        let context = DSPTapContext()
        let clientInfo = Unmanaged.passRetained(context).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: dspTapInit,
            finalize: dspTapFinalize,
            prepare: dspTapPrepare,
            unprepare: dspTapUnprepare,
            process: dspTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault,
                                                &callbacks,
                                                kMTAudioProcessingTapCreationFlag_PostEffects,
                                                &tap)
        if status != noErr {
            Unmanaged<DSPTapContext>.fromOpaque(clientInfo).release()
            return nil
        }
        return tap
    }
}

enum EQPreset: String, CaseIterable, Identifiable {
    case flat = "平直"
    case pop = "流行"
    case rock = "摇滚"
    case classical = "古典"
    case vocal = "人声"
    case night = "深夜"

    var id: String { rawValue }

    var gains: [Float] {
        switch self {
        case .flat: return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .pop: return [1, 2, 2, 1, 0, -1, 1, 3, 3, 1]
        case .rock: return [4, 3, 2, 1, -1, 1, 3, 4, 3, 1]
        case .classical: return [1, 2, 4, 4, 2, 0, -1, -1, 1, 2]
        case .vocal: return [-1, 0, 1, 3, 4, 4, 2, 0, -1, -2]
        case .night: return [-3, -2, -1, 0, 1, 2, 2, 1, 0, -1]
        }
    }
}

private final class DSPTapContext {
    private var bands: [BiquadState] = []
    private var preamp: Float = 1
    private var version = -1
    private var sampleRate: Double = 44100
    private var channels = 2
    private var interleaved = true
    private var floatFormat = false

    func prepare(format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44100
        channels = max(Int(format.mChannelsPerFrame), 1)
        interleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        floatFormat = format.mFormatID == kAudioFormatLinearPCM
            && (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            && format.mBitsPerChannel == 32
        bands = []
        version = -1
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: CMItemCount) {
        let eq = AudioEnhancer.shared.snapshotValue()
        let karaoke = AudioEnhancer.shared.karaokeValue()
        guard eq.enabled || karaoke.active else { return }
        guard floatFormat else { return }

        var processEQ = eq.enabled
        if processEQ {
            if eq.version != version {
                apply(eq)
            }
            if preamp <= 0 || bands.isEmpty {
                processEQ = false
            }
        }

        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        if interleaved {
            for bufferIndex in 0..<abl.count {
                guard let raw = abl[bufferIndex].mData else { continue }
                let data = raw.assumingMemoryBound(to: Float.self)
                let frames = Int(abl[bufferIndex].mDataByteSize) / (MemoryLayout<Float>.size * channels)
                guard frames > 0 else { continue }
                for frame in 0..<frames {
                    let base = frame * channels
                    if processEQ {
                        for channel in 0..<channels {
                            var value = data[base + channel]
                            for band in 0..<10 {
                                let index = channel * 10 + band
                                if index < bands.count {
                                    value = bands[index].process(value)
                                }
                            }
                            data[base + channel] = value * preamp
                        }
                    }
                    if karaoke.active, channels >= 2 {
                        let left = data[base]
                        let right = data[base + 1]
                        let mid = (left + right) * 0.5
                        let side = (left - right) * 0.5
                        data[base] = mid * karaoke.vocal + side * karaoke.accompaniment
                        data[base + 1] = mid * karaoke.vocal - side * karaoke.accompaniment
                    }
                }
            }
        } else {
            if processEQ {
                for channel in 0..<min(abl.count, channels) {
                    guard let raw = abl[channel].mData else { continue }
                    let data = raw.assumingMemoryBound(to: Float.self)
                    let frames = Int(abl[channel].mDataByteSize) / MemoryLayout<Float>.size
                    for frame in 0..<frames {
                        var value = data[frame]
                        for band in 0..<10 {
                            let index = channel * 10 + band
                            if index < bands.count {
                                value = bands[index].process(value)
                            }
                        }
                        data[frame] = value * preamp
                    }
                }
            }
            if karaoke.active, channels >= 2, abl.count >= 2,
               let leftRaw = abl[0].mData, let rightRaw = abl[1].mData {
                let leftData = leftRaw.assumingMemoryBound(to: Float.self)
                let rightData = rightRaw.assumingMemoryBound(to: Float.self)
                let frames = min(Int(abl[0].mDataByteSize), Int(abl[1].mDataByteSize)) / MemoryLayout<Float>.size
                for frame in 0..<frames {
                    let left = leftData[frame]
                    let right = rightData[frame]
                    let mid = (left + right) * 0.5
                    let side = (left - right) * 0.5
                    leftData[frame] = mid * karaoke.vocal + side * karaoke.accompaniment
                    rightData[frame] = mid * karaoke.vocal - side * karaoke.accompaniment
                }
            }
        }
    }

    private func apply(_ snapshot: AudioEQSnapshot) {
        let coefficients = AudioEQMath.frequencies.enumerated().map { index, frequency in
            BiquadCoefficients.peaking(frequency: frequency,
                                       sampleRate: sampleRate,
                                       gainDB: Double(snapshot.gains[safe: index] ?? 0))
        }
        var next: [BiquadState] = []
        next.reserveCapacity(channels * coefficients.count)
        for _ in 0..<channels {
            for coefficient in coefficients {
                next.append(BiquadState(coefficients: coefficient))
            }
        }
        bands = next
        preamp = Float(pow(10, AudioEQMath.preampDB(gains: snapshot.gains, sampleRate: sampleRate) / 20))
        version = snapshot.version
    }
}

private func dspTapInit(tap: MTAudioProcessingTap,
                        clientInfo: UnsafeMutableRawPointer?,
                        tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    tapStorageOut.pointee = clientInfo
}

private func dspTapFinalize(tap: MTAudioProcessingTap) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<DSPTapContext>.fromOpaque(storage).release()
}

private func dspTapPrepare(tap: MTAudioProcessingTap,
                           itemCount: CMItemCount,
                           processingFormat: UnsafePointer<AudioStreamBasicDescription>) {
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<DSPTapContext>.fromOpaque(storage).takeUnretainedValue()
    context.prepare(format: processingFormat.pointee)
}

private func dspTapUnprepare(tap: MTAudioProcessingTap) {}

private func dspTapProcess(tap: MTAudioProcessingTap,
                           numberFrames: CMItemCount,
                           flags: MTAudioProcessingTapFlags,
                           bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
                           numberFramesOut: UnsafeMutablePointer<CMItemCount>,
                           flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    var sourceFlags = MTAudioProcessingTapFlags()
    var sourceFrames = CMItemCount()
    let status = MTAudioProcessingTapGetSourceAudio(tap,
                                                     numberFrames,
                                                     bufferListInOut,
                                                     &sourceFlags,
                                                     nil,
                                                     &sourceFrames)
    guard status == noErr else { return }
    numberFramesOut.pointee = sourceFrames
    flagsOut.pointee = sourceFlags
    let storage = MTAudioProcessingTapGetStorage(tap)
    let context = Unmanaged<DSPTapContext>.fromOpaque(storage).takeUnretainedValue()
    context.process(bufferList: bufferListInOut, frameCount: sourceFrames)
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
