import Foundation

/// 4-stem 流式 MSS 前端。按模型契约重写的 Swift 版：
/// 44.1 kHz / 2048 点 STFT / hop 512 / 周期 Hann / 只取 0..1023 bin。
///
/// 输出顺序：0 人声、1 贝斯、2 鼓、3 其他；播放只把人声作为 vocal，
/// 贝斯+鼓+其他逐 bin 求和作为 accompaniment。
final class MSSEngine {
    struct Output {
        var vocal: [Float]
        var accompaniment: [Float]
        /// 实际产出的帧数；调用方未填满的部分应继续播放原音，避免补零造成断续。
        var producedFrames: Int
    }

    private enum Constants {
        static let sampleRate = 44100
        static let nfft = 2048
        static let hop = 512
        static let bins = 1024
        static let frames = 8
        static let chunk = frames * hop
        static let pad = nfft / 2
        static let look = hop
        static let win = chunk + look
        static let tail = nfft - hop
        static let ola = pad + chunk + tail
        static let ring = 8
    }

    private let runner: MSSRunner
    private let win: [Float]
    private let cosT: [Float]
    private let sinT: [Float]
    private let rev: [Int]

    private var states: [[Float]]
    private var carry = [Float](repeating: 0, count: 2 * Constants.pad)
    private var tailV = [Float](repeating: 0, count: 2 * Constants.tail)
    private var tailA = [Float](repeating: 0, count: 2 * Constants.tail)
    private var tailW = [Float](repeating: 0, count: Constants.tail)

    private var buf = [Float](repeating: 0, count: 2 * (Constants.pad + Constants.win))
    private var inQ = [Float](repeating: 0, count: 2 * (Constants.win + 4 * Constants.chunk))
    private var inLen = 0

    private var vocRing: [[Float]]
    private var accRing: [[Float]]
    private var ringW = 0
    private var ringR = 0
    private var ringN = 0
    private var ringOff = 0

    private var re = [Float](repeating: 0, count: Constants.nfft)
    private var im = [Float](repeating: 0, count: Constants.nfft)
    private var vL = [Float](repeating: 0, count: Constants.ola)
    private var vR = [Float](repeating: 0, count: Constants.ola)
    private var aL = [Float](repeating: 0, count: Constants.ola)
    private var aR = [Float](repeating: 0, count: Constants.ola)
    private var wsum = [Float](repeating: 0, count: Constants.ola)

    private var spectrumIn = [Float](repeating: 0, count: 8 * 4 * 1024)
    private var spectrumOut = [Float](repeating: 0, count: 8 * 16 * 1024)

    init?(path: String) {
        guard let runner = MSSRunner(path: path) else { return nil }
        self.runner = runner
        states = runner.stateSizes.map { [Float](repeating: 0, count: $0) }

        var window = [Float](repeating: 0, count: Constants.nfft)
        var cosine = [Float](repeating: 0, count: Constants.nfft / 2)
        var sine = [Float](repeating: 0, count: Constants.nfft / 2)
        var reversal = [Int](repeating: 0, count: Constants.nfft)
        for i in 0..<Constants.nfft {
            window[i] = Float(0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / Double(Constants.nfft)))
        }
        for i in 0..<(Constants.nfft / 2) {
            let angle = -2.0 * Double.pi * Double(i) / Double(Constants.nfft)
            cosine[i] = Float(cos(angle))
            sine[i] = Float(sin(angle))
        }
        for i in 0..<Constants.nfft {
            var value = UInt32(i)
            var reversed: UInt32 = 0
            for _ in 0..<11 {
                reversed = (reversed << 1) | (value & 1)
                value >>= 1
            }
            reversal[i] = Int(reversed)
        }
        win = window
        cosT = cosine
        sinT = sine
        rev = reversal
        vocRing = Array(repeating: [Float](repeating: 0, count: 2 * Constants.chunk), count: Constants.ring)
        accRing = Array(repeating: [Float](repeating: 0, count: 2 * Constants.chunk), count: Constants.ring)
    }

    /// 初始化后做一次最小推理，确认 TFLite 运行时能真正执行这个模型。
    func validateRuntime() -> Bool {
        runner.validateRuntime()
    }

    func reset() {
        for i in states.indices {
            for j in states[i].indices { states[i][j] = 0 }
        }
        for i in carry.indices { carry[i] = 0 }
        for i in tailV.indices { tailV[i] = 0 }
        for i in tailA.indices { tailA[i] = 0 }
        for i in tailW.indices { tailW[i] = 0 }
        inLen = 0
        ringW = 0
        ringR = 0
        ringN = 0
        ringOff = 0
    }

    /// 送入交错立体声。返回的数组长度与输入帧数一致，但可能只填了前 producedFrames 帧；
    /// 没有可用块时返回 nil，调用方应继续播原音。
    func process(interleaved: [Float], frames: Int) -> Output? {
        guard frames > 0 else { return nil }
        let n = frames * 2
        guard interleaved.count >= n else { return nil }

        if n > inQ.count - inLen {
            let drop = n - (inQ.count - inLen)
            if drop > 0 && drop < inLen {
                for i in 0..<(inLen - drop) { inQ[i] = inQ[i + drop] }
            }
            inLen = max(0, inLen - drop)
        }
        for i in 0..<n { inQ[inLen + i] = interleaved[i] }
        inLen += n

        while inLen >= 2 * Constants.win && ringN < Constants.ring {
            if !runBlock() { break }
            let keep = inLen - 2 * Constants.chunk
            if keep <= 0 {
                inLen = 0
            } else {
                for i in 0..<keep { inQ[i] = inQ[i + 2 * Constants.chunk] }
                inLen = keep
            }
        }

        var vocal = [Float](repeating: 0, count: n)
        var accompaniment = [Float](repeating: 0, count: n)
        var got = 0
        while got < n && ringN > 0 {
            let v = vocRing[ringR]
            let a = accRing[ringR]
            let take = min(2 * Constants.chunk - ringOff, n - got)
            if take > 0 {
                for i in 0..<take {
                    vocal[got + i] = v[ringOff + i]
                    accompaniment[got + i] = a[ringOff + i]
                }
            }
            ringOff += take
            got += take
            if ringOff >= 2 * Constants.chunk {
                ringOff = 0
                ringR = (ringR + 1) % Constants.ring
                ringN -= 1
            }
            if take <= 0 { break }
        }
        guard got > 0 else { return nil }
        return Output(vocal: vocal, accompaniment: accompaniment, producedFrames: got / 2)
    }

    private func runBlock() -> Bool {
        for i in buf.indices { buf[i] = 0 }
        for i in 0..<carry.count { buf[i] = carry[i] }
        for i in 0..<(2 * Constants.win) { buf[carry.count + i] = inQ[i] }

        for i in spectrumIn.indices { spectrumIn[i] = 0 }
        for t in 0..<Constants.frames {
            for c in 0..<2 {
                let start = t * Constants.hop
                for i in 0..<Constants.nfft {
                    re[i] = buf[2 * (start + i) + c] * win[i]
                    im[i] = 0
                }
                fft(inverse: false)
                let base = t * 4 * Constants.bins + c * 2 * Constants.bins
                for f in 0..<Constants.bins {
                    spectrumIn[base + f] = re[f]
                    spectrumIn[base + Constants.bins + f] = im[f]
                }
            }
        }

        for i in spectrumOut.indices { spectrumOut[i] = 0 }
        guard runner.run(spectrumIn: spectrumIn, states: &states, spectrumOut: &spectrumOut) else { return false }

        for i in vL.indices { vL[i] = 0 }
        for i in vR.indices { vR[i] = 0 }
        for i in aL.indices { aL[i] = 0 }
        for i in aR.indices { aR[i] = 0 }
        for i in wsum.indices { wsum[i] = 0 }
        for i in 0..<Constants.tail {
            vL[Constants.pad + i] = tailV[i]
            vR[Constants.pad + i] = tailV[Constants.tail + i]
            aL[Constants.pad + i] = tailA[i]
            aR[Constants.pad + i] = tailA[Constants.tail + i]
            wsum[Constants.pad + i] = tailW[i]
        }

        for t in 0..<Constants.frames {
            let start = t * Constants.hop
            for i in 0..<Constants.nfft where start + i < Constants.ola {
                wsum[start + i] += win[i] * win[i]
            }
            for c in 0..<2 {
                for stem in 0..<2 {
                    for i in re.indices { re[i] = 0; im[i] = 0 }
                    for f in 0..<Constants.bins {
                        let p = (t * 16 + c * 2) * Constants.bins + f
                        if stem == 0 {
                            re[f] = spectrumOut[p]
                            im[f] = spectrumOut[p + Constants.bins]
                        } else {
                            var sr: Float = 0
                            var si: Float = 0
                            for s in 1..<4 {
                                sr += spectrumOut[p + s * 4 * Constants.bins]
                                si += spectrumOut[p + s * 4 * Constants.bins + Constants.bins]
                            }
                            re[f] = sr
                            im[f] = si
                        }
                    }
                    for f in 1..<Constants.bins {
                        re[Constants.nfft - f] = re[f]
                        im[Constants.nfft - f] = -im[f]
                    }
                    fft(inverse: true)
                    for i in 0..<Constants.nfft where start + i < Constants.ola {
                        let value = re[i] * win[i]
                        if stem == 0 {
                            if c == 0 { vL[start + i] += value } else { vR[start + i] += value }
                        } else {
                            if c == 0 { aL[start + i] += value } else { aR[start + i] += value }
                        }
                    }
                }
            }
        }

        var voc = [Float](repeating: 0, count: 2 * Constants.chunk)
        var acc = [Float](repeating: 0, count: 2 * Constants.chunk)
        for i in 0..<Constants.chunk {
            let p = Constants.pad + i
            let w = max(wsum[p], 1e-8)
            voc[2 * i] = vL[p] / w
            voc[2 * i + 1] = vR[p] / w
            acc[2 * i] = aL[p] / w
            acc[2 * i + 1] = aR[p] / w
        }

        for i in 0..<carry.count { carry[i] = buf[2 * Constants.chunk + i] }
        for i in 0..<Constants.tail {
            tailV[i] = vL[Constants.pad + Constants.chunk + i]
            tailV[Constants.tail + i] = vR[Constants.pad + Constants.chunk + i]
            tailA[i] = aL[Constants.pad + Constants.chunk + i]
            tailA[Constants.tail + i] = aR[Constants.pad + Constants.chunk + i]
            tailW[i] = wsum[Constants.pad + Constants.chunk + i]
        }

        if ringN < Constants.ring {
            for i in 0..<(2 * Constants.chunk) {
                vocRing[ringW][i] = voc[i]
                accRing[ringW][i] = acc[i]
            }
            ringW = (ringW + 1) % Constants.ring
            ringN += 1
        }
        return true
    }

    private func fft(inverse: Bool) {
        for i in 0..<Constants.nfft {
            let j = rev[i]
            if j > i {
                let tr = re[i]; re[i] = re[j]; re[j] = tr
                let ti = im[i]; im[i] = im[j]; im[j] = ti
            }
        }
        var len = 2
        while len <= Constants.nfft {
            let half = len >> 1
            let step = Constants.nfft / len
            var i = 0
            while i < Constants.nfft {
                for k in 0..<half {
                    let wr = cosT[k * step]
                    let wi = inverse ? -sinT[k * step] : sinT[k * step]
                    let a = i + k
                    let b = a + half
                    let xr = re[b] * wr - im[b] * wi
                    let xi = re[b] * wi + im[b] * wr
                    re[b] = re[a] - xr
                    im[b] = im[a] - xi
                    re[a] += xr
                    im[a] += xi
                }
                i += len
            }
            len <<= 1
        }
        if inverse {
            let scale = 1.0 / Float(Constants.nfft)
            for i in 0..<Constants.nfft {
                re[i] *= scale
                im[i] *= scale
            }
        }
    }
}
