import Foundation
import Testing

@testable import Herden

@Suite("Host draft")
struct HostDraftTests {
    @Test func prefillsFromAnExistingHostAndRoundTripsWithItsID() throws {
        let host = Host(
            id: UUID(), name: "Workbox", address: "box.example", port: 2222,
            username: "dev", authMethod: .password, sessionName: "work")

        let draft = HostDraft(host: host)
        let rebuilt = try #require(draft.makeHost(id: host.id))

        #expect(rebuilt == host)
    }

    @Test func prefillsAndRoundTripsAJumpHost() throws {
        let host = Host(
            id: UUID(), name: "Behind NAT", address: "127.0.0.1", port: 12_222,
            username: "dev", sessionName: "work",
            jumpAddress: "jump.example", jumpPort: 2022, jumpUsername: "tunnel")

        let draft = HostDraft(host: host)
        let rebuilt = try #require(draft.makeHost(id: host.id))

        #expect(rebuilt == host)
    }

    @Test func prefillsAndRoundTripsABackupAddress() throws {
        let host = Host(
            name: "fansvine", address: "192.168.10.61",
            backupAddress: "100.64.0.14", username: "ted")
        let draft = HostDraft(host: host)
        #expect(draft.makeHost(id: host.id) == host)
    }

    @Test func rejectsDuplicateAddressOrBackupWithJumpHost() {
        var draft = HostDraft()
        draft.name = "fansvine"
        draft.address = "192.168.10.61"
        draft.username = "ted"
        draft.backupAddress = "192.168.10.61"
        #expect(!draft.isValid)
        draft.backupAddress = "100.64.0.14"
        #expect(draft.isValid)
        draft.jumpAddress = "jump.example"
        #expect(!draft.isValid)
    }

    @Test func blankJumpAddressMeansDirectConnection() throws {
        var draft = HostDraft()
        draft.name = "box"
        draft.address = "box.example"
        draft.username = "dev"

        let host = try #require(draft.makeHost())

        #expect(!host.usesJumpHost)
        #expect(host.jumpAddress.isEmpty)
    }

    // The Jump Host port sits in the form even when unused, so an invalid
    // value must not block saving a Host that connects directly.
    @Test func jumpPortOnlyHasToParseWhenAJumpHostIsSet() throws {
        var draft = HostDraft()
        draft.name = "box"
        draft.address = "box.example"
        draft.username = "dev"
        draft.jumpPort = "not-a-port"
        #expect(draft.isValid)

        draft.jumpAddress = "jump.example"
        #expect(!draft.isValid)

        draft.jumpPort = "2022"
        #expect(draft.isValid)
    }

    @Test func blankJumpUsernameFallsBackToTheHostAccount() throws {
        var draft = HostDraft()
        draft.name = "box"
        draft.address = "127.0.0.1"
        draft.username = "dev"
        draft.jumpAddress = "jump.example"

        let host = try #require(draft.makeHost())

        #expect(host.jumpUsername.isEmpty)
        #expect(host.resolvedJumpUsername == "dev")
    }

    @Test func trimsFieldsOnSave() throws {
        var draft = HostDraft()
        draft.name = " Workbox "
        draft.address = " box.example "
        draft.username = " dev "
        draft.sessionName = " work "

        let host = try #require(draft.makeHost())

        #expect(host.name == "Workbox")
        #expect(host.address == "box.example")
        #expect(host.username == "dev")
        #expect(host.sessionName == "work")
        #expect(host.port == 22)
    }

    @Test func rejectsBlankHostnameAddressOrUsername() {
        var draft = HostDraft()
        draft.name = "box"
        draft.address = ""
        draft.username = "dev"
        #expect(!draft.isValid)
        #expect(draft.makeHost() == nil)

        draft.address = "box.example"
        draft.username = "   "
        #expect(!draft.isValid)

        draft.username = "dev"
        draft.name = "   "
        #expect(!draft.isValid)
    }

    @Test(arguments: ["", "0", "65536", "abc", "-1"])
    func rejectsInvalidPorts(port: String) {
        var draft = HostDraft()
        draft.name = "box"
        draft.address = "box.example"
        draft.username = "dev"
        draft.port = port
        #expect(!draft.isValid)
    }

    @Test func rejectsSessionNamesHerdrWouldReject() {
        let invalidNames = [
            "work session", "../prod", ".", "..", "work/session", String(repeating: "a", count: 65),
        ]

        for sessionName in invalidNames {
            var draft = HostDraft()
            draft.name = "host"
            draft.address = "host.example"
            draft.username = "dev"
            draft.sessionName = sessionName

            #expect(!draft.isValid, "unexpectedly accepted session name: \(sessionName)")
        }
    }

    @Test func acceptsHerdrSessionNameCharacterSetAndLengthLimit() {
        var draft = HostDraft()
        draft.name = "host"
        draft.address = "host.example"
        draft.username = "dev"
        draft.sessionName = String(repeating: "a", count: 60) + "._-9"

        #expect(draft.isValid)
    }

    @Test func passwordUpdateOnlyForPasswordAuthWithAnEntry() {
        var draft = HostDraft()
        draft.authMethod = .password
        draft.password = "hunter2"
        #expect(draft.passwordUpdate == "hunter2")

        // Blank means "keep whatever is stored" when editing.
        draft.password = ""
        #expect(draft.passwordUpdate == nil)

        // The device key path stores no password at all.
        draft.authMethod = .deviceKey
        draft.password = "hunter2"
        #expect(draft.passwordUpdate == nil)
    }

    @Test func newPasswordHostRequiresAPassword() {
        var draft = HostDraft()
        draft.name = "host"
        draft.address = "host.example"
        draft.username = "dev"
        draft.authMethod = .password

        #expect(!draft.canSave(editing: nil))

        draft.password = "secret"
        #expect(draft.canSave(editing: nil))
    }

    @Test func blankPasswordOnlyKeepsAnExistingPasswordCredential() {
        let passwordHost = Host.fixture(name: "host", authMethod: .password)
        let keyHost = Host.fixture(name: "host", authMethod: .deviceKey)
        var draft = HostDraft(host: passwordHost)

        #expect(draft.canSave(editing: passwordHost))

        draft = HostDraft(host: keyHost)
        draft.authMethod = .password
        #expect(!draft.canSave(editing: keyHost))
    }
}

private actor AddressConnector: TransportConnector {
    let failures: [String: TransportError]
    private(set) var attempted: [String] = []

    init(failures: [String: TransportError] = [:]) {
        self.failures = failures
    }

    func connect(settings: SSHTransportSettings) async throws -> any Transport {
        attempted.append(settings.host)
        if let failure = failures[settings.host] { throw failure }
        return FakeTransport(pingResult: .success(
            ServerInfo(version: "0.8.2", protocolVersion: 17)))
    }
}

@Suite("Host connection addresses")
struct HostConnectionTests {
    private let primary = "192.168.10.61"
    private let backup = "100.64.0.14"

    private func connect(
        host: Host, connector: AddressConnector
    ) async throws -> any Transport {
        let policy = HostKeyPolicy(knownHosts: InMemoryKnownHostsStore()) { _ in false }
        return try await HostConnection.connect(
            host: host, credentials: .password("test"), policy: policy,
            connector: connector)
    }

    @Test func usesPrimaryWhenReachable() async throws {
        let connector = AddressConnector()
        let host = Host(address: primary, backupAddress: backup, username: "ted")
        _ = try await connect(host: host, connector: connector)
        #expect(await connector.attempted == [primary])
    }

    @Test func triesBackupAfterNetworkFailure() async throws {
        let connector = AddressConnector(failures: [
            primary: .sshUnreachable(detail: "no route")])
        let host = Host(address: primary, backupAddress: backup, username: "ted")
        _ = try await connect(host: host, connector: connector)
        #expect(await connector.attempted == [primary, backup])
    }

    @Test func doesNotTryBackupAfterAuthenticationFailure() async {
        let connector = AddressConnector(failures: [primary: .authenticationFailed])
        let host = Host(address: primary, backupAddress: backup, username: "ted")
        do {
            _ = try await connect(host: host, connector: connector)
            Issue.record("authentication failure must stop failover")
        } catch let error as TransportError {
            #expect(error == .authenticationFailed)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(await connector.attempted == [primary])
    }

    @Test func pinFromEitherAddressIsRequiredAtTheOther() async throws {
        let base = InMemoryKnownHostsStore()
        let trusted = HostKeyFingerprint(publicKeyBlob: Data("real host".utf8))
        await base.setFingerprint(trusted, host: primary, port: 22)
        let aliases = AlternateAddressKnownHostsStore(
            base: base, primary: primary, backup: backup, port: 22)
        #expect(await aliases.fingerprint(
            host: backup, port: 22, algorithm: trusted.algorithm) == trusted)
        #expect(await aliases.fingerprints(host: backup, port: 22) == [trusted])
        let conflicting = HostKeyFingerprint(publicKeyBlob: Data("other host".utf8))
        await base.setFingerprint(conflicting, host: backup, port: 22)
        #expect(await aliases.fingerprints(host: backup, port: 22) == [trusted])
    }
}
