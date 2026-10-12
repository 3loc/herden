import Foundation

/// Opens a connected Transport for the given settings: the seam between UI
/// stores and real SSH. Production is `SSHTransportConnector`; tests inject
/// a scripted fake, so screen logic never touches an SSH library (ADR 0011).
protocol TransportConnector: Sendable {
    func connect(settings: SSHTransportSettings) async throws -> any Transport
}

/// The one production SSH backend: libssh2 reaching the herden socket over
/// direct-streamlocal (ADR 0011). There is deliberately no second path — a
/// Host that denies stream-local forwarding is a server policy to fix, not a
/// case to fall back from.
struct SSHTransportConnector: TransportConnector {
    func connect(settings: SSHTransportSettings) async throws -> any Transport {
        try await HerdenSSHTransport.connect(settings: settings)
    }
}

extension SSHTransportSettings {
    /// Transport settings for a catalog Host, given resolved credentials and
    /// the TOFU policy the UI wires up.
    init(host: Host, credentials: SSHCredentials, hostKeyPolicy: HostKeyPolicy) {
        self.init(
            host: host.address,
            port: host.port,
            username: host.username,
            credentials: credentials,
            hostKeyPolicy: hostKeyPolicy,
            socket: host.socketLocation,
            // Both hops use the Host's resolved credential. Device Key is the
            // normal case; password Hosts require the same password at both hops.
            jump: host.usesJumpHost
                ? SSHJumpSettings(
                    host: host.jumpAddress.trimmingCharacters(in: .whitespaces),
                    port: host.jumpPort,
                    username: host.resolvedJumpUsername,
                    credentials: credentials)
                : nil)
    }
}

enum HostConnection {
    static func connect(
        host: Host,
        credentials: SSHCredentials,
        policy: HostKeyPolicy,
        connector: any TransportConnector,
        addressStore: HostAddressStore = .shared,
        onAttempt: (@Sendable (String) async -> Void)? = nil
    ) async throws -> any Transport {
        let learned = await addressStore.addresses(for: host)
        var seen = Set<String>()
        let addresses = (host.directAddresses + learned)
            .filter { seen.insert($0).inserted }
            .enumerated().sorted {
                let lhs = HostAddresses.rank($0.element), rhs = HostAddresses.rank($1.element)
                return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
            }.map(\.element)
        var policy = policy
        if addresses.count > 1 {
            policy.knownHosts = AlternateAddressKnownHostsStore(
                base: policy.knownHosts, primary: host.address, backup: host.backupAddress,
                port: host.port, additionalAddresses: learned)
        }
        for (index, address) in addresses.enumerated() {
            try Task.checkCancellation()
            await onAttempt?(address)
            var settings = SSHTransportSettings(
                host: host, credentials: credentials, hostKeyPolicy: policy)
            settings.host = address
            if addresses.count > 1 { settings.connectTimeout = .seconds(3) }
            do {
                let transport = try await connector.connect(settings: settings)
                // Best effort and bounded: unsupported discovery must not turn
                // a working SSH connection into a failed Host.
                if !host.usesJumpHost,
                    let discovered = try? await AsyncDeadline.run(for: .seconds(2), operation: {
                        try await transport.connectionAddresses()
                    }) {
                    await addressStore.remember(discovered, for: host)
                }
                if Task.isCancelled {
                    try? await transport.close()
                    throw CancellationError()
                }
                return transport
            } catch let error as TransportError {
                guard index + 1 < addresses.count, error.isAddressReachabilityFailure else {
                    throw error
                }
            }
        }
        // Every attempt either returned or threw, including the last one.
        throw TransportError.sshUnreachable(detail: "No address could be reached")
    }
}

private extension TransportError {
    var isAddressReachabilityFailure: Bool {
        switch self {
        case .sshUnreachable, .timedOut: true
        default: false
        }
    }
}
