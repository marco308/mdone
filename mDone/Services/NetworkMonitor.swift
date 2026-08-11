import Foundation
import Network

@Observable
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.mdone.networkmonitor")

    var isConnected: Bool = true
    var connectionType: ConnectionType = .unknown

    enum ConnectionType {
        case wifi, cellular, wired, unknown
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.connectionType = self?.getConnectionType(path) ?? .unknown
            }
        }
        monitor.start(queue: queue)
    }

    /// Builds a monitor pinned to a fixed state, without starting `NWPathMonitor`.
    /// Tests need a deterministic offline flag; a started monitor would
    /// asynchronously overwrite `isConnected` with the host's real path.
    init(stubbedConnection isConnected: Bool) {
        self.isConnected = isConnected
    }

    private func getConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .unknown
    }

    deinit {
        monitor.cancel()
    }
}
