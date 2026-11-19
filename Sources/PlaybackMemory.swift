import Foundation

/// 播放进度记忆：每首歌记住上次听到哪，再点同一首能接着放。
enum PlaybackMemory {
    private static let key = "kg.playback.positions"
    private static let minimumSeconds: Double = 5

    private static var store: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func position(for hash: String) -> Double {
        store[hash.lowercased()] ?? 0
    }

    static func save(_ seconds: Double, for hash: String) {
        guard seconds >= minimumSeconds else { return }
        var dict = store
        dict[hash.lowercased()] = seconds
        store = dict
    }

    static func clear(_ hash: String) {
        var dict = store
        dict.removeValue(forKey: hash.lowercased())
        store = dict
    }
}
