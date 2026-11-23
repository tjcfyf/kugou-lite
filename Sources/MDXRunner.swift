import Foundation
import TensorFlowLiteC

/// MDX 的 TFLite 后备封装。当前包不再内置 TFLite 权重，只保留代码路径；
/// 主要运行的是 2048-bin 的 Core ML 快速模型。
final class MDXRunner: MDXEngine {

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
        guard inCount == MDXModel.inputCount, outCount == MDXModel.inputCount else { return nil }
    }

    deinit {
        if let interpreter { TfLiteInterpreterDelete(interpreter) }
        if let delegate { TfLiteXNNPackDelegateDelete(delegate) }
        if let options { TfLiteInterpreterOptionsDelete(options) }
        if let model { TfLiteModelDelete(model) }
    }

    func run(input: [Float], output: inout [Float]) -> Bool {
        guard let interpreter,
              input.count == MDXModel.inputCount,
              output.count == MDXModel.inputCount,
              let inputTensor = TfLiteInterpreterGetInputTensor(interpreter, 0) else { return false }

        let bytes = MDXModel.inputCount * MemoryLayout<Float>.size
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
