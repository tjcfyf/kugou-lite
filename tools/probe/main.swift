import AVFoundation
import Foundation

func decode(_ url: URL) throws -> ([Float], [Float]) {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first else { fatalError("no track") }
    let reader = try AVAssetReader(asset: asset)
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]
    let out = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
    out.alwaysCopiesSampleData = false
    reader.add(out); reader.startReading()
    var l = [Float](), r = [Float]()
    while reader.status == .reading, let s = out.copyNextSampleBuffer() {
        defer { CMSampleBufferInvalidate(s) }
        guard let b = CMSampleBufferGetDataBuffer(s) else { continue }
        var len = 0, total = 0; var ptr: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(b, atOffset: 0, lengthAtOffsetOut: &len, totalLengthOut: &total, dataPointerOut: &ptr) == noErr, let ptr else { continue }
        let f = UnsafeRawPointer(ptr).assumingMemoryBound(to: Float.self)
        let n = min(CMSampleBufferGetNumSamples(s), total / 8)
        for i in 0..<n { l.append(f[2*i]); r.append(f[2*i+1]) }
    }
    if reader.status == .failed { throw reader.error! }
    return (l, r)
}

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: probe <model.mlmodelc> <audio>") }
let modelURL = URL(fileURLWithPath: args[1])
let audioURL = URL(fileURLWithPath: args[2])
guard let model = MDXCoreMLRunner(modelURL: modelURL) else { fatalError("model load failed") }
print("model loaded")
let (l, r) = try decode(audioURL)
print("decoded \(l.count) frames")
var last = 0.0
let t0 = CFAbsoluteTimeGetCurrent()
try MDXSeparator.separateToWAV(left: l, right: r, model: model,
                               instrumentalURL: URL(fileURLWithPath: "/tmp/probe-inst.wav"),
                               vocalURL: URL(fileURLWithPath: "/tmp/probe-voc.wav")) { p, s in
    if p - last > 0.1 || p >= 1 { print(String(format: "%.2f %@", p, s)); last = p }
}
print(String(format: "total %.1f s", CFAbsoluteTimeGetCurrent() - t0))
for name in ["/tmp/probe-inst.wav", "/tmp/probe-voc.wav"] {
    let a = try decode(URL(fileURLWithPath: name))
    let rms = sqrt(a.0.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(a.0.count, 1)))
    print(name, a.0.count, String(format: "rms %.4f", rms))
}
