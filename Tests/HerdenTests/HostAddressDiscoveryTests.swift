import Foundation
import Testing

@testable import Herden

@Suite("Automatic Host routes")
struct HostAddressDiscoveryTests {
    @Test func ignoresNoiseAndUnusableAddresses() {
        let output = """
            login noise 10.0.0.99
            __HERDEN_ADDRESS__=192.168.1.3
            __HERDEN_ADDRESS__=100.64.0.2
            __HERDEN_ADDRESS__=fd7a:115c:a1e0::2
            __HERDEN_ADDRESS__=192.168.1.3
            __HERDEN_ADDRESS__=127.0.0.1
            __HERDEN_ADDRESS__=0.0.0.0
            __HERDEN_ADDRESS__=224.0.0.1
            __HERDEN_ADDRESS__=169.254.1.2
            __HERDEN_ADDRESS__=fe80::1%en0
            __HERDEN_ADDRESS__=fe80::1
            __HERDEN_ADDRESS__=::1
            __HERDEN_ADDRESS__=::
            __HERDEN_ADDRESS__=::ffff:127.0.0.1
            __HERDEN_ADDRESS__=ff02::1
            __HERDEN_ADDRESS__=bad.example
            """
        #expect(HostAddresses.parse(output) == ["192.168.1.3", "100.64.0.2", "fd7a:115c:a1e0::2"])
    }

    @Test func cachesSurviveRelaunchButDoNotFollowAnEditedEndpoint() async throws {
        let suite = "routes-\(UUID())"
        let store = try #require(HostAddressStore(suiteName: suite))
        let host = Host(address: "192.168.1.3", username: "dev")
        await store.remember(["100.64.0.2"], for: host)
        let reloaded = try #require(HostAddressStore(suiteName: suite))
        #expect(await reloaded.addresses(for: host) == ["100.64.0.2"])
        var edited = host
        edited.address = "192.168.1.4"
        #expect(await reloaded.addresses(for: edited).isEmpty)
        edited = host
        edited.jumpAddress = "jump.example"
        #expect(await reloaded.addresses(for: edited).isEmpty)
        await store.remember([], for: host)
        #expect(await store.addresses(for: host) == ["100.64.0.2"])
        await store.forget(host)
    }

    @Test func learnsThroughSSHAndUsesTheAlternateOnTheNextConnection() async throws {
        let host = Host(address: "192.168.1.3", username: "dev")
        let store = HostAddressStore()
        let connector = LearningRouteConnector()
        let policy = HostKeyPolicy(knownHosts: InMemoryKnownHostsStore()) { _ in false }
        let first = try await HostConnection.connect(
            host: host, credentials: .password("test"), policy: policy,
            connector: connector, addressStore: store)
        try await first.close()
        await connector.loseLAN()
        _ = try await HostConnection.connect(
            host: host, credentials: .password("test"), policy: policy,
            connector: connector, addressStore: store)
        #expect(await connector.attempts == ["192.168.1.3", "192.168.1.3", "100.64.0.2"])
        #expect(await connector.lastConnectTimeout == .seconds(3))
        #expect(await connector.lastRequestTimeout == .seconds(15))
    }

    @Test func allLearnedRoutesKeepThePrimaryFingerprint() async {
        let base = InMemoryKnownHostsStore()
        let pin = HostKeyFingerprint(publicKeyBlob: Data("trusted".utf8))
        await base.setFingerprint(pin, host: "192.168.1.3", port: 22)
        let aliases = AlternateAddressKnownHostsStore(
            base: base, primary: "192.168.1.3", backup: "", port: 22,
            additionalAddresses: ["100.64.0.2", "fd7a:115c:a1e0::2"])
        #expect(await aliases.fingerprints(host: "fd7a:115c:a1e0::2", port: 22) == [pin])
        #expect(await aliases.fingerprints(host: "100.64.0.2", port: 2222).isEmpty)
        #expect(await aliases.fingerprints(host: "192.168.1.99", port: 22).isEmpty)
    }

    @Test func networkTransitionsIgnoreStartupDuplicatesAndOffline() {
        var filter = HostNetworkChangeFilter()
        let wifi = HostNetworkPath(available: true, interfaces: ["en0"], expensive: false)
        let vpn = HostNetworkPath(available: true, interfaces: ["utun2", "en0"], expensive: false)
        let cellular = HostNetworkPath(available: true, interfaces: ["pdp_ip0"], expensive: true)
        let transitions = [wifi, wifi, vpn, cellular,
            HostNetworkPath(available: false, interfaces: [], expensive: false), wifi]
        let decisions = transitions.map { filter.shouldReconnect($0) }
        #expect(decisions == [false, false, true, true, false, true])
    }

    @Test func anImpostorOnTheLocalLANDoesNotReplaceThePairedIdentity() async throws {
        let host = Host(address: "100.64.0.2", username: "dev")
        let addresses = HostAddressStore()
        await addresses.remember(["192.168.1.3"], for: host)
        let pins = InMemoryKnownHostsStore()
        let trusted = HostKeyFingerprint(publicKeyBlob: Data("paired host".utf8))
        await pins.setFingerprint(trusted, host: host.address, port: 22)
        let connector = FakeTransportConnector(
            outcome: .connects(pingResult: .failure(.timedOut)),
            presentedKeyBlob: Data("different LAN host".utf8))
        do {
            _ = try await HostConnection.connect(
                host: host, credentials: .password("test"),
                policy: HostKeyPolicy(knownHosts: pins) { _ in
                    Issue.record("A learned address must never ask to trust a new identity")
                    return true
                }, connector: connector, addressStore: addresses)
            Issue.record("Expected a host-key mismatch")
        } catch let error as TransportError {
            guard case .hostKeyMismatch = error else {
                Issue.record("Unexpected error: \(error)"); return
            }
        }
        #expect(await connector.capturedSettings.map(\.host) == ["192.168.1.3"])
        #expect(await pins.fingerprint(host: host.address, port: 22) == trusted)
    }

    @MainActor
    @Test func networkChangeReplacesALiveConnectionButDoesNotWakeASuspendedHost() async throws {
        let routes = NetworkTransitionTransports()
        let host = Host(address: "192.168.1.3", username: "dev")
        let console = ConsoleStore { _, subscriptions in
            EventsSession(subscriptions: subscriptions, connect: {
                await routes.connect()
            }, keepalive: nil)
        }
        console.setHosts([host])
        await console.resume()
        for _ in 0..<200 where console.hostStatuses[host.id] != .connected {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(console.hostStatuses[host.id] == .connected)
        let first = try #require(await routes.transports.first)
        await console.networkDidChange()
        for _ in 0..<200 where await routes.transports.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await routes.transports.count == 2)
        #expect(await first.isConnected == false)
        await console.suspend()
        await console.networkDidChange()
        #expect(await routes.transports.count == 2)
        #expect(console.hostStatuses[host.id] == .suspended)
        console.setHosts([])
    }
}

private actor NetworkTransitionTransports {
    private(set) var transports: [ScriptedTransport] = []
    func connect() -> ScriptedTransport {
        let transport = ScriptedTransport(snapshot: .fixture())
        transports.append(transport)
        return transport
    }
}

private actor LearningRouteConnector: TransportConnector {
    private var lanIsDown = false
    private(set) var attempts: [String] = []
    private(set) var lastConnectTimeout: Duration?
    private(set) var lastRequestTimeout: Duration?

    func loseLAN() { lanIsDown = true }

    func connect(settings: SSHTransportSettings) async throws -> any Transport {
        attempts.append(settings.host)
        lastConnectTimeout = settings.connectTimeout
        lastRequestTimeout = settings.requestTimeout
        if lanIsDown && settings.host == "192.168.1.3" {
            throw TransportError.sshUnreachable(detail: "Wi-Fi disconnected")
        }
        return FakeTransport(
            pingResult: .failure(.timedOut), addresses: ["192.168.1.3", "100.64.0.2"])
    }
}
