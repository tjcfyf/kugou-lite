import Foundation
import TensorFlowLiteC

/// TensorFlow Lite C API 的最小封装：29 个输入（1 个频谱 + 28 路流式状态）、
/// 29 个输出（1 个频谱 + 28 路回灌状态）。
///
/// 只跑 CPU + XNNPACK。模型里有 32 个 TRANSPOSE / TRANSPOSE_CONV，旧 GPU delegate
/// 在这些算子上反而更慢，而且部分驱动会在首次 run 时直接崩进程。
final class MSSRunner {
    private(set) var stateSizes: [Int] = []
    private var model: OpaquePointer?
    private var options: OpaquePointer?
    private var interpreter: OpaquePointer?
    private var delegate: OpaquePointer?

    private let spectrumInCount = 8 * 4 * 1024
    private let spectrumOutCount = 8 * 16 * 1024

    init?(path: String) {
        guard let model = TfLiteModelCreateFromFile(path) else { return nil }
        self.model = model

        guard let options = TfLiteInterpreterOptionsCreate() else { return nil }
        self.options = options
        let threads = Int32(min(max(ProcessInfo.processInfo.activeProcessorCount / 2, 2), 6))
        TfLiteInterpreterOptionsSetNumThreads(options, threads)

        var xnnOptions = TfLiteXNNPackDelegateOptionsDefault()
        xnnOptions.num_threads = threads
        if let delegate = TfLiteXNNPackDelegateCreate(&xnnOptions) {
            self.delegate = delegate
            TfLiteInterpreterOptionsAddDelegate(options, delegate)
        }

        guard let interpreter = TfLiteInterpreterCreate(model, options) else { return nil }
        self.interpreter = interpreter
        guard TfLiteInterpreterAllocateTensors(interpreter) == kTfLiteOk else { return nil }

        let inputCount = Int(TfLiteInterpreterGetInputTensorCount(interpreter))
        let outputCount = Int(TfLiteInterpreterGetOutputTensorCount(interpreter))
        guard inputCount == 29, outputCount == 29 else { return nil }

        var sizes: [Int] = []
        sizes.reserveCapacity(28)
        for i in 1..<inputCount {
            guard let tensor = TfLiteInterpreterGetInputTensor(interpreter, Int32(i)) else { return nil }
            var count = 1
            let dims = Int(TfLiteTensorNumDims(tensor))
            for d in 0..<dims { count *= Int(TfLiteTensorDim(tensor, Int32(d))) }
            guard count > 0 else { return nil }
            sizes.append(count)
        }
        guard sizes.count == 28 else { return nil }
        stateSizes = sizes

        // 输出 0 必须是频谱；输出 1...28 必须和状态同形。
        guard let out0 = TfLiteInterpreterGetOutputTensor(interpreter, 0) else { return nil }
        var outCount = 1
        let outDims = Int(TfLiteTensorNumDims(out0))
        for d in 0..<outDims { outCount *= Int(TfLiteTensorDim(out0, Int32(d))) }
        guard outCount == spectrumOutCount else { return nil }

        for i in 1..<outputCount {
            guard let tensor = TfLiteInterpreterGetOutputTensor(interpreter, Int32(i)) else { return nil }
            var count = 1
            let dims = Int(TfLiteTensorNumDims(tensor))
            for d in 0..<dims { count *= Int(TfLiteTensorDim(tensor, Int32(d))) }
            guard count == stateSizes[i - 1] else { return nil }
        }

        // 输入 0 形状校验，避免把损坏模型当成可用模型。
        guard let in0 = TfLiteInterpreterGetInputTensor(interpreter, 0) else { return nil }
        var inCount = 1
        let inDims = Int(TfLiteTensorNumDims(in0))
        for d in 0..<inDims { inCount *= Int(TfLiteTensorDim(in0, Int32(d))) }
        guard inCount == spectrumInCount else { return nil }
    }

    deinit {
        if let interpreter { TfLiteInterpreterDelete(interpreter) }
        if let delegate { TfLiteXNNPackDelegateDelete(delegate) }
        if let options { TfLiteInterpreterOptionsDelete(options) }
        if let model { TfLiteModelDelete(model) }
    }

    func run(spectrumIn: [Float], states: inout [[Float]], spectrumOut: inout [Float]) -> Bool {
        guard let interpreter else { return false }
        guard spectrumIn.count == spectrumInCount, spectrumOut.count == spectrumOutCount else { return false }
        guard states.count == stateSizes.count else { return false }

        guard let input0 = TfLiteInterpreterGetInputTensor(interpreter, 0) else { return false }
        let bytes = spectrumInCount * MemoryLayout<Float>.size
        spectrumIn.withUnsafeBytes { raw in
            _ = TfLiteTensorCopyFromBuffer(input0, raw.baseAddress, bytes)
        }

        for i in 0..<stateSizes.count {
            guard let tensor = TfLiteInterpreterGetInputTensor(interpreter, Int32(i + 1)) else { return false }
            let stateBytes = stateSizes[i] * MemoryLayout<Float>.size
            states[i].withUnsafeBytes { raw in
                _ = TfLiteTensorCopyFromBuffer(tensor, raw.baseAddress, stateBytes)
            }
        }

        guard TfLiteInterpreterInvoke(interpreter) == kTfLiteOk else { return false }

        guard let output0 = TfLiteInterpreterGetOutputTensor(interpreter, 0) else { return false }
        spectrumOut.withUnsafeMutableBytes { raw in
            _ = TfLiteTensorCopyToBuffer(output0, raw.baseAddress, spectrumOutCount * MemoryLayout<Float>.size)
        }

        for i in 0..<stateSizes.count {
            guard let tensor = TfLiteInterpreterGetOutputTensor(interpreter, Int32(i + 1)) else { return false }
            let stateBytes = stateSizes[i] * MemoryLayout<Float>.size
            states[i].withUnsafeMutableBytes { raw in
                _ = TfLiteTensorCopyToBuffer(tensor, raw.baseAddress, stateBytes)
            }
        }
        return true
    }
}
