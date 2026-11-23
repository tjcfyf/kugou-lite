import CoreML
import Foundation

/// UVR-MDX-NET-Voc_FT 的 Core ML 版本（iOS 15 可直接加载的 CoreML5 / float16）。
/// 输入输出契约与 TFLite 版本完全一致：`spectrum` / `vocals`，[1,4,3072,256]。
/// iPhone 12 上优先用 Neural Engine + GPU；加载失败时由 AIOfflineSeparator 回退 TFLite。
final class MDXCoreMLRunner: MDXEngine {
    static let inputCount = 4 * 3072 * 256
    private let model: MLModel
    private let inputArray: MLMultiArray
    private let inputName = "spectrum"
    private let outputName = "vocals"
    private var outputBuffer: [Float]

    init?(bundleName: String = "MdxNetVocFT_iOS15") {
        guard let url = Bundle.main.url(forResource: bundleName, withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: bundleName, withExtension: "mlmodelc", subdirectory: "Resources") else {
            return nil
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        guard let loaded = try? MLModel(contentsOf: url, configuration: configuration) else {
            // Neural Engine / GPU 不可用时至少还能用 CPU，不要因为加载策略把功能直接判死。
            let cpu = MLModelConfiguration()
            cpu.computeUnits = .cpuOnly
            guard let fallback = try? MLModel(contentsOf: url, configuration: cpu),
                  let input = try? MLMultiArray(shape: [1, 4, 3072, 256], dataType: .float32) else {
                return nil
            }
            model = fallback
            inputArray = input
            outputBuffer = [Float](repeating: 0, count: Self.inputCount)
            return
        }
        guard let input = try? MLMultiArray(shape: [1, 4, 3072, 256], dataType: .float32) else { return nil }
        model = loaded
        inputArray = input
        outputBuffer = [Float](repeating: 0, count: Self.inputCount)
    }

    func run(input: [Float], output: inout [Float]) -> Bool {
        guard input.count == Self.inputCount, output.count == Self.inputCount else { return false }
        // iOS 15 没有 `withUnsafeBufferPointer(ofType:)`（15.4 才有），
        // 直接拿 MLMultiArray 的 dataPointer；输入是我们自己分配、连续排布的 float32。
        let destination = inputArray.dataPointer.assumingMemoryBound(to: Float.self)
        input.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            destination.update(from: base, count: Self.inputCount)
        }
        guard let provider = try? MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(multiArray: inputArray)]),
              let result = try? model.prediction(from: provider),
              let vocals = result.featureValue(for: outputName)?.multiArrayValue,
              vocals.count == Self.inputCount else { return false }
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
                destination.baseAddress?.update(from: source, count: Self.inputCount)
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
