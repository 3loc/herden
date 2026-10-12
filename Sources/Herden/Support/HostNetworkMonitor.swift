import Foundation
import Network

struct HostNetworkPath: Sendable, Equatable {
    let available: Bool
    let interfaces: [String]
    let expensive: Bool
}

struct HostNetworkChangeFilter {
    private var previous: HostNetworkPath?

    mutating func shouldReconnect(_ path: HostNetworkPath) -> Bool {
        defer { previous = path }
        // Initial delivery describes startup, not a network transition.
        return path.available && previous != nil && previous != path
    }
}

enum HostNetworkMonitor {
    static func paths() -> AsyncStream<HostNetworkPath> {
        let monitor = NWPathMonitor()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(HostNetworkPath(
                    available: path.status == .satisfied,
                    interfaces: path.availableInterfaces.map(\.name),
                    expensive: path.isExpensive))
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "ltd.3loc.herden.network"))
        }
    }
}
