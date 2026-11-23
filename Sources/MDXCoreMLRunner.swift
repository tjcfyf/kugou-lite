import CoreML
import Foundation

/// UVR_MDXNET_1_9703 的 Core ML 版本（iOS 15 / CoreML5 / float16）。
/// 输入输出 `spectrum` / `vocals`，[1, 4, 2048, 256]，planes 顺序
/// [L-real, L-imag, R-real, R-imag]。2048-bin 比 Voc_FT 的 3072-bin
/// 少约一半计算量，是 iPhone 12 上能压到几十秒的关键。
final class MDXCoreMLRunner: MDXEngine {
    private let model: MLModel
    private let inputArray: MLMultiArray
    private let inputName = "spectrum"
    private let outputName = "vocals"
    private var outputBuffer: [Float]

    init?(bundleName: String = MDXModel.bundleName, onlyCPU: Bool = false) {
        guard let url = Bundle.main.url(forResource: bundleName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: bundleName, withExtension: "mlmodelc", subdirectory: "Resources") else {
            return nil
        }
        let units: [MLComputeUnits] = onlyCPU ? [.cpuOnly] : [.cpuAndNeuralEngine, .all, .cpuOnly]
        var loaded: MLModel?
        for unit in units {
            let configuration = MLModelConfiguration()
            configuration.computeUnits = unit
            if let made = try? MLModel(contentsOf: url, configuration: configuration) {
                loaded = made
                break
            }
        }
        guard let loaded else { return nil }
        model = loaded
        guard let input = try? MLMultiArray(shape: [1, 4, 2048, 256], dataType: .float32) else { return nil }
        inputArray = input
        outputBuffer = [Float](repeating: 0, count: MDXModel.inputCount)
    }

    /// 用一帧全零频谱做自检：模型能 load 不代表能在当前设备上真正推理。
    func warmUp() -> Bool {
        var probeIn = [Float](repeating: 0, count: MDXModel.inputCount)
        var probeOut = [Float](repeating: 0, count: MDXModel.inputCount)
        return run(input: probeIn, output: &probeOut)
    }

    func run(input: [Float], output: inout [Float]) -> Bool {
        guard input.count == MDXModel.inputCount, output.count == MDXModel.inputCount else { return false }
        let destination = inputArray.dataPointer.assumingMemoryBound(to: Float.self)
        input.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            destination.update(from: base, count: MDXModel.inputCount)
        }
        guard let provider = try? MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(multiArray: inputArray)]),
              let result = try? model.prediction(from: provider),
              let vocals = result.featureValue(for: outputName)?.multiArrayValue,
              vocals.count == MDXModel.inputCount else { return false }
        copyIntoBuffer(vocals)
        output = outputBuffer
        return true
    }

    private func copyIntoBuffer(_ array: MLMultiArray) {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        var expected = [Int](repeating: 1, count: shape.count)
        for i in stride(from: shape.count - 2, through: 0, by: -1) {
            expected[i] = expected[i + 1] * shape[i + 1]
        }
        if array.dataType == .float32 && strides == expected {
            let source = array.dataPointer.assumingMemoryBound(to: Float.self)
            outputBuffer.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress?.update(from: source, count: MDXModel.inputCount)
            }
            return
        }
        var index = 0
        for a in 0..<shape[0] {
            for b in 0..<shape[1] {
                for c in 0..<shape[2] {
                    for d in 0..<shape[3] {
                        let sourceIndex = a * strides[0] + b * strides[1] + c * strides[2] + d * strides[3]
                        outputBuffer[index] = array[sourceIndex].floatValue
                        index += 1
                    }
                }
            }
        }
    }
}
