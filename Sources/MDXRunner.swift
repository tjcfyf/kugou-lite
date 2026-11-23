import Foundation
import TensorFlowLiteC

/// UVR-MDX-NET-Voc_FT 的 TFLite 封装。
/// 输入/输出都是 float32 `[1, 4, 3072, 256]`，planes 顺序
/// `[L-real, L-imag, R-real, R-imag]`，44.1 kHz / 6144 点 FFT / hop 1024。
/// 只跑 CPU + XNNPACK；MDX 全是卷积和矩阵乘，XNNPACK 已足够，
/// 且 iOS 15 的 TFLite Metal delegate 对这个图并不稳定。
protocol MDXEngine {
    func run(input: [Float], output: inout [Float]) -> Bool
}

final class MDXRunner: MDXEngine {
    static let inputCount = 1 * 4 * 3072 * 256

    private var model: OpaquePointer?
    private var options: OpaquePointer?
    private var interpreter: OpaquePointer?
    private var delegate: UnsafeMutablePointer<TfLiteDelegate>?

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

        guard Int(TfLiteInterpreterGetInputTensorCount(interpreter)) == 1,
              Int(TfLiteInterpreterGetOutputTensorCount(interpreter)) == 1,
              let input = TfLiteInterpreterGetInputTensor(interpreter, 0),
              let output = TfLiteInterpreterGetOutputTensor(interpreter, 0) else { return nil }
        var inCount = 1
        for d in 0..<Int(TfLiteTensorNumDims(input)) { inCount *= Int(TfLiteTensorDim(input, Int32(d))) }
        var outCount = 1
        for d in 0..<Int(TfLiteTensorNumDims(output)) { outCount *= Int(TfLiteTensorDim(output, Int32(d))) }
        guard inCount == Self.inputCount, outCount == Self.inputCount else { return nil }
    }

    deinit {
        if let interpreter { TfLiteInterpreterDelete(interpreter) }
        if let delegate { TfLiteXNNPackDelegateDelete(delegate) }
        if let options { TfLiteInterpreterOptionsDelete(options) }
        if let model { TfLiteModelDelete(model) }
    }

    func run(input: [Float], output: inout [Float]) -> Bool {
        guard let interpreter,
              input.count == Self.inputCount,
              output.count == Self.inputCount,
              let inputTensor = TfLiteInterpreterGetInputTensor(interpreter, 0) else { return false }

        let bytes = Self.inputCount * MemoryLayout<Float>.size
        input.withUnsafeBytes { raw in
            _ = TfLiteTensorCopyFromBuffer(inputTensor, raw.baseAddress, bytes)
        }
        guard TfLiteInterpreterInvoke(interpreter) == kTfLiteOk,
              let outputTensor = TfLiteInterpreterGetOutputTensor(interpreter, 0) else { return false }
        output.withUnsafeMutableBytes { raw in
            _ = TfLiteTensorCopyToBuffer(outputTensor, raw.baseAddress, bytes)
        }
        return true
    }
}
