import Foundation

/// MDX-Net 的前端/模型契约。9703 是 UVR 的 2048-bin 轻量 MDX 模型：
/// 4096 点 STFT / hop 1024 / 256 帧，输入输出 [1, 4, 2048, 256]。
protocol MDXEngine {
    func run(input: [Float], output: inout [Float]) -> Bool
}

enum MDXModel {
    static let sampleRate: Double = 44_100
    static let fftSize = 4_096
    static let frequencyBins = 2_048
    static let hop = 1_024
    static let segmentFrames = 256
    static let planeSize = frequencyBins * segmentFrames
    static let inputCount = 4 * planeSize
    static let bundleName = "MdxNetFast9703_iOS15"
}
