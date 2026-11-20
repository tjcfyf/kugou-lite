import Foundation
import Network

/// 网络连通性探针，用于断网时快速失败，避免播放请求一直挂在超时上。
final class NetworkStatus {
    static let shared = NetworkStatus()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kugoulite.network.monitor")
    private let lock = NSLock()
    private var connected = true

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.lock.lock()
            self.connected = (path.status == .satisfied)
            self.lock.unlock()
        }
        monitor.start(queue: queue)
    }
}
