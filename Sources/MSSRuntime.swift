import Foundation

/// 本地分离模型的发现与生命周期。
///
/// 模型随 App 打进 Bundle（Resources/mss-model.tflite）。模型缺失或 TFLite 加载失败时
/// 整个功能回退到 v78 的官方双轨/中置声道，不会让播放链路崩掉。
final class MSSRuntime {
    static let shared = MSSRuntime()

    private(set) var isAvailable = false
    private var prepared = false

    private init() {}

    var modelURL: URL? {
        Bundle.main.url(forResource: "mss-model", withExtension: "tflite")
            ?? Bundle.main.url(forResource: "mss-model", withExtension: "tflite", subdirectory: "Resources")
    }

    /// 主线程调用一次即可；首次会创建解释器并校验 29 入/29 出、张量形状。
    @discardableResult
    func prepare() -> Bool {
        if prepared { return isAvailable }
        prepared = true
        guard let url = modelURL else {
            isAvailable = false
            return false
        }
        isAvailable = MSSEngine(path: url.path) != nil
        return isAvailable
    }

    /// 每个播放 item 各持一份引擎；TFLite Interpreter 不是线程安全的。
    func makeEngine() -> MSSEngine? {
        guard isAvailable, let url = modelURL else { return nil }
        return MSSEngine(path: url.path)
    }
}
