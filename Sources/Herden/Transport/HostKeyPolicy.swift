import Foundation

/// An unknown host key awaiting the user's trust decision on first connect.
struct HostKeyCandidate: Sendable, Equatable {
    let host: String
    let port: Int

    let fingerprint: HostKeyFingerprint
}

/// TOFU host key policy: trust the fingerprint the user confirmed on first
/// connect, hard-fail when a known Host's key changes. No SSH primitive
/// leaks through this surface — the UI implements the confirmation and injects
/// the store without seeing one.
struct HostKeyPolicy: Sendable {
    /// Fingerprints of already-trusted Hosts.
    var knownHosts: any KnownHostsStore

    /// First-connect confirmation, implemented by the UI: shown the
    /// candidate, returns whether the user trusts it. Returning false fails
    /// the connection with `.hostKeyRejected` and stores nothing.
    var confirmFirstConnect: @Sendable (HostKeyCandidate) async -> Bool

    init(
        knownHosts: any KnownHostsStore,
        confirmFirstConnect: @escaping @Sendable (HostKeyCandidate) async -> Bool
    ) {
        self.knownHosts = knownHosts
        self.confirmFirstConnect = confirmFirstConnect
    }
}

/// Treat two routes to one Host as the same SSH identity. An existing pin for
/// either address must match the key presented at the other address; a new
/// route cannot silently acquire a different identity during failover.
struct AlternateAddressKnownHostsStore: KnownHostsStore {
    let base: any KnownHostsStore
    let primary: String
    let backup: String
    let port: Int
    var additionalAddresses: [String] = []

    private func trustedAddress(for host: String, port: Int) async -> String {
        let addresses = [primary, backup] + additionalAddresses
        guard port == self.port, addresses.contains(host) else { return host }
        for address in addresses where !address.isEmpty {
            if !(await base.fingerprints(host: address, port: port)).isEmpty { return address }
        }
        return host
    }

    func fingerprints(host: String, port: Int) async -> [HostKeyFingerprint] {
        let trusted = await trustedAddress(for: host, port: port)
        return await base.fingerprints(host: trusted, port: port)
    }

    func fingerprint(host: String, port: Int, algorithm: String) async -> HostKeyFingerprint? {
        let trusted = await trustedAddress(for: host, port: port)
        return await base.fingerprint(host: trusted, port: port, algorithm: algorithm)
    }

    func setFingerprint(_ fingerprint: HostKeyFingerprint, host: String, port: Int) async {
        await base.setFingerprint(fingerprint, host: host, port: port)
    }
}
