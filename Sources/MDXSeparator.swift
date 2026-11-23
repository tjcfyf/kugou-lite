import Accelerate
import Foundation

/// UVR-MDX-NET-Voc_FT 的 STFT → 模型 → 互补掩码 → iSTFT 流程。
/// 和电脑版 UVR/MDX-Net 使用同一个 6144 点 STFT / hop 1024 / 256 帧窗口；
/// 模型只预测人声频谱，伴奏用立体声联动的互补掩码从原频谱重建。
enum MDXSeparator {
    static let sampleRate: Double = 44_100
    static let fftSize = 6_144
    static let frequencyBins = 3_072
    static let hop = 1_024
    static let segmentFrames = 256
    static let chunkOverlap: Double = 0.25
    static let instrumentalGainDB: Float = 1.5

    enum Failure: Error, LocalizedError {
        case emptyAudio
        case transform
        case nonFiniteOutput
        case modelFailed

        var errorDescription: String? {
            switch self {
            case .emptyAudio: return "音频为空，无法分离"
            case .transform: return "FFT 初始化失败"
            case .nonFiniteOutput: return "模型输出了无效数据"
            case .modelFailed: return "MDX 模型推理失败"
            }
        }
    }

    struct Stems {
        let instrumentalLeft: [Float]
        let instrumentalRight: [Float]
        let vocalLeft: [Float]
        let vocalRight: [Float]
    }

    /// 只做分离，不写文件。progress 的第一个参数是 0...1，第二个参数是给 UI 的短文案。
    static func separate(left: [Float], right: [Float], model: MDXRunner,
                         progress: (Double, String) -> Void) throws -> Stems {
        guard !left.isEmpty, left.count == right.count else { throw Failure.emptyAudio }

        let window = hannWindowPeriodic(fftSize)
        let leftPadded = reflectPad(left, pad: fftSize / 2)
        let rightPadded = reflectPad(right, pad: fftSize / 2)
        let paddedLength = leftPadded.count
        let totalFrames = 1 + (paddedLength - fftSize) / hop
        let chunkStride = max(Int(Double(segmentFrames) * (1 - chunkOverlap)), 1)
        let totalChunks = max(Int(ceil(Double(max(totalFrames - segmentFrames, 0)) / Double(chunkStride))), 1)

        var accumLeft = [Float](repeating: 0, count: paddedLength)
        var accumRight = [Float](repeating: 0, count: paddedLength)
        var weightSum = [Float](repeating: 0, count: paddedLength)
        var input = [Float](repeating: 0, count: MDXRunner.inputCount)
        var output = [Float](repeating: 0, count: MDXRunner.inputCount)
        var mask = [Float](repeating: 0, count: frequencyBins)
        var re = [Float](repeating: 0, count: fftSize)
        var im = [Float](repeating: 0, count: fftSize)
        var transform = try VDSPTransform(size: fftSize)
        let planeSize = frequencyBins * segmentFrames

        func fft(inverse: Bool) throws {
            try re.withUnsafeMutableBufferPointer { r in
                try im.withUnsafeMutableBufferPointer { i in
                    try transform.transform(re: r, im: i, inverse: inverse)
                }
            }
        }

        var chunkStart = 0
        var chunkIndex = 0
        while chunkStart < totalFrames {
            let chunkLen = min(segmentFrames, totalFrames - chunkStart)

            for t in 0..<segmentFrames {
                if t < chunkLen {
                    let start = (chunkStart + t) * hop
                    for i in 0..<fftSize { re[i] = leftPadded[start + i] * window[i]; im[i] = 0 }
                    try fft(inverse: false)
                } else {
                    for i in 0..<fftSize { re[i] = 0; im[i] = 0 }
                }
                for f in 0..<frequencyBins {
                    let offset = f * segmentFrames + t
                    input[offset] = re[f]
                    input[planeSize + offset] = im[f]
                }
            }

            for t in 0..<segmentFrames {
                if t < chunkLen {
                    let start = (chunkStart + t) * hop
                    for i in 0..<fftSize { re[i] = rightPadded[start + i] * window[i]; im[i] = 0 }
                    try fft(inverse: false)
                } else {
                    for i in 0..<fftSize { re[i] = 0; im[i] = 0 }
                }
                for f in 0..<frequencyBins {
                    let offset = f * segmentFrames + t
                    input[2 * planeSize + offset] = re[f]
                    input[3 * planeSize + offset] = im[f]
                }
            }

            guard model.run(input: input, output: &output) else { throw Failure.modelFailed }

            for t in 0..<chunkLen {
                let triangular = triangularWeight(t, chunkLength: chunkLen)
                let sampleStart = (chunkStart + t) * hop
                for channel in 0..<2 {
                    let reBase = 2 * channel * planeSize
                    let imBase = (2 * channel + 1) * planeSize
                    for f in 0..<frequencyBins {
                        let offset = f * segmentFrames + t
                        if channel == 0 {
                            var mixPower: Float = 0
                            var vocalPower: Float = 0
                            for plane in 0..<4 {
                                let mixed = input[plane * planeSize + offset]
                                let predicted = output[plane * planeSize + offset]
                                mixPower += mixed * mixed
                                vocalPower += predicted * predicted
                            }
                            mask[f] = linkedInstrumentalMask(mixPower: mixPower, vocalPower: vocalPower,
                                                              frequencyHz: Float(f) * Float(sampleRate) / Float(fftSize))
                        }
                        let m = mask[f]
                        let r = input[reBase + offset] * m
                        let i = input[imBase + offset] * m
                        re[f] = r
                        im[f] = i
                        if f > 0 {
                            re[fftSize - f] = r
                            im[fftSize - f] = -i
                        }
                    }
                    re[frequencyBins] = 0
                    im[frequencyBins] = 0
                    try fft(inverse: true)
                    if channel == 0 {
                        for i in 0..<fftSize { accumLeft[sampleStart + i] += re[i] * window[i] * triangular }
                    } else {
                        for i in 0..<fftSize { accumRight[sampleStart + i] += re[i] * window[i] * triangular }
                    }
                }
                for i in 0..<fftSize { weightSum[sampleStart + i] += window[i] * window[i] * triangular }
            }

            chunkIndex += 1
            progress(min(Double(chunkIndex) / Double(totalChunks), 1.0),
                     "分离中 \(min(chunkIndex, totalChunks))/\(totalChunks)")
            if chunkStart + chunkLen >= totalFrames { break }
            chunkStart += chunkStride
        }

        let trimStart = fftSize / 2
        var outLeft = [Float](repeating: 0, count: left.count)
        var outRight = [Float](repeating: 0, count: right.count)
        for i in 0..<min(left.count, max(paddedLength - trimStart, 0)) {
            let divisor = weightSum[trimStart + i] > 1e-8 ? weightSum[trimStart + i] : 1
            outLeft[i] = accumLeft[trimStart + i] / divisor
            outRight[i] = accumRight[trimStart + i] / divisor
        }

        let gain = try instrumentalGain(mixLeft: left, mixRight: right,
                                        left: outLeft, right: outRight)
        var instLeft = outLeft
        var instRight = outRight
        for i in 0..<instLeft.count { instLeft[i] *= gain }
        for i in 0..<instRight.count { instRight[i] *= gain }

        // 人声 = 原混音 − 未加增益的伴奏。掩码是互补的，两条音轨相加可还原原曲。
        var vocalLeft = left
        var vocalRight = right
        for i in 0..<vocalLeft.count { vocalLeft[i] -= outLeft[i] }
        for i in 0..<vocalRight.count { vocalRight[i] -= outRight[i] }

        return Stems(instrumentalLeft: instLeft, instrumentalRight: instRight,
                     vocalLeft: vocalLeft, vocalRight: vocalRight)
    }

    static func instrumentalGain(mixLeft: [Float], mixRight: [Float],
                                 left: [Float], right: [Float]) throws -> Float {
        let mixRMS = rms(mixLeft, mixRight)
        let instRMS = rms(left, right)
        let rmsMatch = instRMS > 1e-6 ? mixRMS / instRMS : 1
        let flat = Float(pow(10, Double(instrumentalGainDB) / 20))
        let desired = rmsMatch * flat
        var peak: Float = 0
        for i in left.indices {
            guard left[i].isFinite, right[i].isFinite else { throw Failure.nonFiniteOutput }
            peak = max(peak, abs(left[i]), abs(right[i]))
        }
        return peak <= 1e-8 ? 1 : min(min(max(desired, 0.5), 2), 0.98 / peak)
    }

    private static func rms(_ left: [Float], _ right: [Float]) -> Float {
        var sum = 0.0
        for i in left.indices {
            sum += Double(left[i]) * Double(left[i]) + Double(right[i]) * Double(right[i])
        }
        return Float((sum / max(2.0 * Double(left.count), 1)).squareRoot())
    }

    /// 和电脑端 MDX 相同的互补掩码：1 − √(vocal / mix) × smoothstep((f − 55) / 95)。
    static func linkedInstrumentalMask(mixPower: Float, vocalPower: Float, frequencyHz: Float) -> Float {
        guard mixPower.isFinite, vocalPower.isFinite else { return 1 }
        if mixPower <= 1e-12 { return 1 }
        let fraction = min(max((max(vocalPower, 0) / mixPower).squareRoot(), 0), 1)
        let blend = min(max((frequencyHz - 55) / 95, 0), 1)
        let smooth = blend * blend * (3 - 2 * blend)
        return min(max(1 - fraction * smooth, 0), 1)
    }

    static func hannWindowPeriodic(_ size: Int) -> [Float] {
        (0..<size).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size))) }
    }

    static func reflectPad(_ x: [Float], pad: Int) -> [Float] {
        let n = x.count
        guard n > 0 else { return [Float](repeating: 0, count: 2 * pad) }
        var out = [Float](repeating: 0, count: n + 2 * pad)
        for i in 0..<pad { out[i] = x[min(max(pad - i, 0), n - 1)] }
        for i in 0..<n { out[pad + i] = x[i] }
        for i in 0..<pad { out[pad + n + i] = x[min(max(n - 2 - i, 0), n - 1)] }
        return out
    }

    static func triangularWeight(_ t: Int, chunkLength: Int) -> Float {
        if chunkLength <= 1 { return 1 }
        let mid = Float(chunkLength - 1) / 2
        return max(1 - abs(Float(t) - mid) / (mid + 1), 0.05)
    }
}

/// vDSP 的复数 DFT；6144 = 3 × 2¹¹ 是 vDSP_DFT 支持的长度。
final class VDSPTransform {
    let size: Int
    private let forward: vDSP_DFT_Setup
    private let inverse: vDSP_DFT_Setup
    private var outRe: [Float]
    private var outIm: [Float]

    init(size: Int) throws {
        guard let forward = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD),
              let inverse = vDSP_DFT_zop_CreateSetup(forward, vDSP_Length(size), .INVERSE) else {
            throw MDXSeparator.Failure.transform
        }
        self.size = size
        self.forward = forward
        self.inverse = inverse
        outRe = [Float](repeating: 0, count: size)
        outIm = [Float](repeating: 0, count: size)
    }

    deinit {
        vDSP_DFT_DestroySetup(forward)
        vDSP_DFT_DestroySetup(inverse)
    }

    func transform(re: UnsafeMutableBufferPointer<Float>, im: UnsafeMutableBufferPointer<Float>,
                   inverse isInverse: Bool) throws {
        guard re.count == size, im.count == size,
              let reIn = re.baseAddress, let imIn = im.baseAddress else {
            throw MDXSeparator.Failure.transform
        }
        let setup = isInverse ? inverse : forward
        outRe.withUnsafeMutableBufferPointer { oRe in
            outIm.withUnsafeMutableBufferPointer { oIm in
                vDSP_DFT_Execute(setup, reIn, imIn, oRe.baseAddress!, oIm.baseAddress!)
                if isInverse {
                    var scale = 1 / Float(size)
                    vDSP_vsmul(oRe.baseAddress!, 1, &scale, reIn, 1, vDSP_Length(size))
                    vDSP_vsmul(oIm.baseAddress!, 1, &scale, imIn, 1, vDSP_Length(size))
                } else {
                    reIn.update(from: oRe.baseAddress!, count: size)
                    imIn.update(from: oIm.baseAddress!, count: size)
                }
            }
        }
    }
}

enum StereoWav {
    static func header(frames: Int, sampleRate: Int) -> [UInt8] {
        let dataSize = UInt32(truncatingIfNeeded: frames * 4)
        var out: [UInt8] = []
        out.reserveCapacity(44)
        func u32(_ v: UInt32) { for k in 0..<4 { out.append(UInt8(truncatingIfNeeded: v >> (8 * UInt32(k)))) } }
        func u16(_ v: UInt16) { out.append(UInt8(v & 0xFF)); out.append(UInt8(v >> 8)) }
        out += Array("RIFF".utf8); u32(36 &+ dataSize); out += Array("WAVE".utf8)
        out += Array("fmt ".utf8); u32(16); u16(1); u16(2); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 4)); u16(4); u16(16)
        out += Array("data".utf8); u32(dataSize)
        return out
    }

    static func pcm16(left: [Float], right: [Float], range: Range<Int>, gain: Float = 1) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: range.count * 4)
        var o = 0
        for i in range {
            for value in [left[i], right[i]] {
                let sample = Int16(truncatingIfNeeded: Int(min(max(value * gain, -1), 1) * Float(Int16.max)))
                out[o] = UInt8(truncatingIfNeeded: UInt16(bitPattern: sample))
                out[o + 1] = UInt8(truncatingIfNeeded: UInt16(bitPattern: sample) >> 8)
                o += 2
            }
        }
        return out
    }
}
