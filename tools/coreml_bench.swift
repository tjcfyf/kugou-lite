import CoreML
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: bench <mlpackage|mlmodelc>"); exit(2) }
let url = URL(fileURLWithPath: args[1])
let configuration = MLModelConfiguration()
configuration.computeUnits = .all
let model = try MLModel(contentsOf: url, configuration: configuration)
print("model loaded: \(model.modelDescription.inputDescriptionsByName.keys) -> \(model.modelDescription.outputDescriptionsByName.keys)")

let shape: [NSNumber] = [1, 4, 3072, 256]
let input = try MLMultiArray(shape: shape, dataType: .float32)
let count = 4 * 3072 * 256
let p = input.dataPointer.assumingMemoryBound(to: Float.self)
for i in 0..<count { p[i] = Float((i % 97) - 48) / 48.0 }

let provider = try MLDictionaryFeatureProvider(dictionary: ["spectrum": MLFeatureValue(multiArray: input)])
// warmup
_ = try model.prediction(from: provider)
let t0 = CFAbsoluteTimeGetCurrent()
var result: MLFeatureProvider!
for _ in 0..<3 { result = try model.prediction(from: provider) }
let elapsed = (CFAbsoluteTimeGetCurrent() - t0) / 3.0
print(String(format: "avg inference: %.3f s", elapsed))
if let out = result.featureValue(for: "vocals")?.multiArrayValue {
    print("output shape \(out.shape) count \(out.count) strides \(out.strides)")
    var sum = 0.0, maxv = 0.0
    for i in stride(from: 0, to: out.count, by: 997) {
        let v = out[i].floatValue
        sum += Double(v * v)
        maxv = max(maxv, abs(Double(v)))
    }
    print(String(format: "finite sample rms %.5f max %.5f", sqrt(sum / Double(out.count)), maxv))
} else {
    print("no vocals output"); exit(1)
}
