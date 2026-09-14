import Foundation
import Testing

@testable import Herden

@MainActor
@Suite("New Space store")
struct NewSpaceStoreTests {
    @Test func aSingleHostIsPreselectedAndDirectoryDefaultsToHostHome() {
        let host = Host.fixture(name: "buildbox")
        let store = NewSpaceStore(hosts: [host]) { _, _ in Self.createdSpace }

        #expect(store.selectedHostID == host.id)
        #expect(store.canSubmit)

        store.directory = "src/app"
        #expect(store.directoryErrorMessage == "Enter an absolute path on the Host.")
        #expect(!store.canSubmit)

        store.directory = "/home/developer/src/app"
        #expect(store.directoryErrorMessage == nil)
        #expect(store.canSubmit)
    }

    @Test func submitCreatesOnlyTheSpaceAndReturnsItsRootTerminal() async throws {
        let host = Host.fixture(name: "buildbox")
        var receivedSpec: SpaceCreationRequest?
        var receivedHostID: Host.ID?
        let store = NewSpaceStore(hosts: [host]) { spec, hostID in
            receivedSpec = spec
            receivedHostID = hostID
            return Self.createdSpace
        }
        store.directory = "  /home/developer/src/app  "
        store.label = "  App  "

        let result = try #require(await store.submit())

        #expect(receivedSpec == SpaceCreationRequest(directory: "/home/developer/src/app", label: "App"))
        #expect(receivedHostID == host.id)
        #expect(result.0 == host.id)
        #expect(result.1 == Self.createdSpace)
        #expect(store.state == .created)
    }

    @Test func anEmptyDirectoryAsksHerdrForTheHostDefault() async throws {
        let host = Host.fixture(name: "buildbox")
        var receivedSpec: SpaceCreationRequest?
        let store = NewSpaceStore(hosts: [host]) { spec, _ in
            receivedSpec = spec
            return Self.createdSpace
        }

        _ = try #require(await store.submit())

        #expect(receivedSpec == SpaceCreationRequest())
    }

    @Test func transportFailureReturnsTheFormToAnActionableState() async {
        let host = Host.fixture(name: "buildbox")
        let store = NewSpaceStore(hosts: [host]) { _, _ in
            throw TransportError.sshUnreachable(detail: "connection dropped")
        }
        store.directory = "/home/developer"

        #expect(await store.submit() == nil)
        #expect(store.state == .failed("The Host is not connected."))
        #expect(store.canSubmit)
        #expect(store.canDismiss)
    }

    private static let createdSpace = CreatedSpace(
        workspaceID: "w7",
        label: "App",
        terminal: ShellTerminalIdentity(
            paneID: "w7:p1",
            tabID: "w7:t1",
            terminalID: "term-space"))
}
