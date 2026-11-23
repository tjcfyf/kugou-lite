import Accelerate
import Foundation

/// UVR_MDXNET_1_9703 的 STFT → 模型 → 互补掩码 → iSTFT 流程。
/// 4096 点 STFT / hop 1024 / 256 帧窗口；模型只预测人声频谱，
/// 伴奏用立体声联动的互补掩码从原频谱重建。
///
/// 结果直接流式写两条 WAV，不再在内存里额外保留 4 条整首歌的 Float 数组。
/// 这是 iOS 上最容易 OOM 的地方，也是 9703 能把内存压下来的关键。
enum MDXSeparator {
    static let sampleRate = MDXModel.sampleRate
    static let fftSize = MDXModel.fftSize
    static let frequencyBins = MDXModel.frequencyBins
    static let hop = MDXModel.hop
    static let segmentFrames = MDXModel.segmentFrames
    static let chunkOverlap: Double = 0.25
    static let instrumentalGainDB: Float = 1.5

    enum Failure: Error, LocalizedError {
        case emptyAudio
        case transform
        case nonFiniteOutput
        case modelFailed
        case write

        var errorDescription: String? {
            switch self {
            case .emptyAudio: return "音频为空，无法分离"
            case .transform: return "FFT 初始化失败"
            case .nonFiniteOutput: return "模型输出了无效数据"
            case .modelFailed: return "MDX 模型推理失败"
            case .write: return "双轨写入失败"
            }
        }
    }

    /// 只做分离并写文件，不返回整首歌的采样数组。progress 为 0...1。
    static func separateToWAV(left: [Float], right: [Float], model: MDXEngine,
                              instrumentalURL: URL, vocalURL: URL,
                              progress: (Double, String) -> Void) throws {
        guard !left.isEmpty, left.count == right.count else { throw Failure.emptyAudio }

        let window = hannWindowPeriodic(fftSize)
        let leftPadded = reflectPad(left, pad: fftSize / 2)
        let rightPadded = reflectPad(right, pad: fftSize / 2)
        let paddedLength = leftPadded.count
        let totalFrames = 1 + (paddedLength - fftSize) / hop
        let chunkStride = max(Int(Double(segmentFrames) * (1 - chunkOverlap)), 1)
        let totalChunks = max(Int(ceil(Double(max(totalFrames - segmentFrames, 0)) / Double(chunkStride))), 1)
        let planeSize = MDXModel.planeSize

        var accumLeft = [Float](repeating: 0, count: paddedLength)
        var accumRight = [Float](repeating: 0, count: paddedLength)
        var weightSum = [Float](repeating: 0, count: paddedLength)
        var input = [Float](repeating: 0, count: MDXModel.inputCount)
        var output = [Float](repeating: 0, count: MDXModel.inputCount)
        var mask = [Float](repeating: 0, count: frequencyBins)
        var re = [Float](repeating: 0, count: fftSize)
        var im = [Float](repeating: 0, count: fftSize)
        let transform = try VDSPTransform(size: fftSize)

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
            progress(min(Double(chunkIndex) / Double(totalChunks) * 0.82, 0.82),
                     "分离中 \(min(chunkIndex, totalChunks))/\(totalChunks)")
            if chunkStart + chunkLen >= totalFrames { break }
            chunkStart += chunkStride
        }

        let trimStart = fftSize / 2
        let frames = left.count
        for i in 0..<paddedLength {
            let divisor = weightSum[i] > 1e-8 ? weightSum[i] : 1
            accumLeft[i] /= divisor
            accumRight[i] /= divisor
        }

        progress(0.86, "计算伴奏增益")
        let gain = try instrumentalGain(mixLeft: left, mixRight: right,
                                        bedLeft: accumLeft, bedRight: accumRight,
                                        offset: trimStart, frames: frames)
        progress(0.90, "写入双轨")
        try writeWavPair(instrumentalURL: instrumentalURL, vocalURL: vocalURL,
                         frames: frames, mixLeft: left, mixRight: right,
                         bedLeft: accumLeft, bedRight: accumRight,
                         bedOffset: trimStart, gain: gain)
    }

    private static func instrumentalGain(mixLeft: [Float], mixRight: [Float],
                                         bedLeft: [Float], bedRight: [Float],
                                         offset: Int, frames: Int) throws -> Float {
        var mixSum = 0.0
        var bedSum = 0.0
        var peak: Float = 0
        for i in 0..<frames {
            let ml = mixLeft[i], mr = mixRight[i]
            guard ml.isFinite, mr.isFinite else { throw Failure.nonFiniteOutput }
            mixSum += Double(ml * ml) + Double(mr * mr)
        }
        for i in 0..<frames {
            let bl = bedLeft[offset + i], br = bedRight[offset + i]
            guard bl.isFinite, br.isFinite else { throw Failure.nonFiniteOutput }
            bedSum += Double(bl * bl) + Double(br * br)
            peak = max(peak, abs(bl), abs(br))
        }
        let mixRMS = Float((mixSum / max(2.0 * Double(frames), 1)).squareRoot())
        let bedRMS = Float((bedSum / max(2.0 * Double(frames), 1)).squareRoot())
        let rmsMatch = bedRMS > 1e-6 ? mixRMS / bedRMS : 1
        let flat = Float(pow(10, Double(instrumentalGainDB) / 20))
        let desired = rmsMatch * flat
        return peak <= 1e-8 ? 1 : min(min(max(desired, 0.5), 2), 0.98 / peak)
    }

    private static func writeWavPair(instrumentalURL: URL, vocalURL: URL,
                                     frames: Int, mixLeft: [Float], mixRight: [Float],
                                     bedLeft: [Float], bedRight: [Float],
                                     bedOffset: Int, gain: Float) throws {
        let fm = FileManager.default
        let instPart = instrumentalURL.appendingPathExtension("part")
        let vocalPart = vocalURL.appendingPathExtension("part")
        for url in [instrumentalURL, vocalURL, instPart, vocalPart] { try? fm.removeItem(at: url) }
        for url in [instrumentalURL, vocalURL] {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        guard fm.createFile(atPath: instPart.path, contents: nil),
              fm.createFile(atPath: vocalPart.path, contents: nil) else { throw Failure.write }
        let instHandle = try FileHandle(forWritingTo: instPart)
        let vocalHandle = try FileHandle(forWritingTo: vocalPart)
        do {
            let header = StereoWav.header(frames: frames, sampleRate: Int(sampleRate))
            try instHandle.write(contentsOf: Data(header))
            try vocalHandle.write(contentsOf: Data(header))

            var start = 0
            while start < frames {
                let end = min(start + 65_536, frames)
                let count = end - start
                var instBytes = [UInt8](repeating: 0, count: count * 4)
                var vocalBytes = [UInt8](repeating: 0, count: count * 4)
                var o = 0
                for i in start..<end {
                    let bedL = bedLeft[bedOffset + i]
                    let bedR = bedRight[bedOffset + i]
                    let instL = clamp(bedL * gain)
                    let instR = clamp(bedR * gain)
                    let vocL = clamp(mixLeft[i] - bedL)
                    let vocR = clamp(mixRight[i] - bedR)
                    StereoWav.appendPCM16(instL, to: &instBytes, at: &o)
                    StereoWav.appendPCM16(instR, to: &instBytes, at: &o)
                    var vo = (i - start) * 4
                    StereoWav.appendPCM16(vocL, to: &vocalBytes, at: &vo)
                    StereoWav.appendPCM16(vocR, to: &vocalBytes, at: &vo)
                }
                try instHandle.write(contentsOf: Data(instBytes))
                try vocalHandle.write(contentsOf: Data(vocalBytes))
                start = end
            }
            try instHandle.close()
            try vocalHandle.close()
        } catch {
            try? instHandle.close()
            try? vocalHandle.close()
            try? fm.removeItem(at: instPart)
            try? fm.removeItem(at: vocalPart)
            throw Failure.write
        }
        try? fm.removeItem(at: instrumentalURL)
        try? fm.removeItem(at: vocalURL)
        try fm.moveItem(at: instPart, to: instrumentalURL)
        try fm.moveItem(at: vocalPart, to: vocalURL)
    }

    private static func clamp(_ value: Float) -> Float {
        min(max(value.isFinite ? value : 0, -1), 1)
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

/// vDSP 的复数 DFT；4096 = 2¹² 是 vDSP_DFT 支持的长度。
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

    @inline(__always)
    static func appendPCM16(_ value: Float, to bytes: inout [UInt8], at offset: inout Int) {
        let sample = Int16(truncatingIfNeeded: Int(value * Float(Int16.max)))
        bytes[offset] = UInt8(truncatingIfNeeded: UInt16(bitPattern: sample))
        bytes[offset + 1] = UInt8(truncatingIfNeeded: UInt16(bitPattern: sample) >> 8)
        offset += 2
    }
}
