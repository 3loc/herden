import Testing
@testable import Herden

struct HarnessPixelMarkTests {
    @Test func coversTheHostAgentCatalogWithReadableLetters() {
        #expect(SupportedAgentKind.allCases.count == 24)
        #expect(SupportedAgentKind.pi.pixelLetters == "P")
        #expect(SupportedAgentKind.claude.pixelLetters == "C")
        #expect(SupportedAgentKind.codex.pixelLetters == "Cx")
        #expect(SupportedAgentKind.letta.displayName == "Letta Code")
        #expect(SupportedAgentKind.allCases.allSatisfy {
            !$0.pixelLetters.isEmpty && $0.brandAccent != 0
        })
    }

    @Test func identifiesOnlyAnObservedForegroundShell() {
        let bash = PaneProcessInfoProcess(name: "/bin/bash", pid: 42)
        let editor = PaneProcessInfoProcess(name: "vim", pid: 99)
        #expect(TerminalShellKind.detected(in: PaneProcessInfo(
            paneID: "p1", foregroundProcesses: [bash], shellPid: 42)) == .bash)
        #expect(TerminalShellKind.detected(in: PaneProcessInfo(
            paneID: "p1", foregroundProcesses: [editor], shellPid: 42)) == nil)
        #expect(TerminalShellKind.detected(in: PaneProcessInfo(
            paneID: "p1", foregroundProcessGroupID: 99,
            foregroundProcesses: [bash, editor], shellPid: 42)) == nil)
        #expect(TerminalShellKind.detected(in: PaneProcessInfo(
            paneID: "p1", foregroundProcesses: [bash, editor])) == nil)
        #expect(TerminalShellKind.detected(in: PaneProcessInfo(
            paneID: "p1", foregroundProcesses: [.init(name: "-zsh", pid: 7)])) == .zsh)
        #expect(TerminalShellKind.detected(in: PaneProcessInfo(
            paneID: "p1", foregroundProcesses: [.init(name: "fish", pid: 7)])) == .fish)
    }

    @Test func spaceUsesShellOnlyForAnOrdinaryTerminal() {
        let host = Host.fixture(name: "studio")
        let agent = ConsoleAgent(
            hostID: host.id, hostName: host.displayName,
            agent: Agent(.fixture(paneID: "agent", workspaceID: "w2")),
            workspaceLabel: "Agent", repositoryCheckout: nil)
        let spaces = ConsoleSpace.project(
            hosts: [host],
            workspacesByHost: [host.id: [
                ConsoleWorkspace(id: "w1", label: "Shell"),
                ConsoleWorkspace(id: "w2", label: "Agent"),
            ]],
            agents: [agent],
            shellKind: { _ in .fish })
        #expect(spaces.first(where: { $0.workspace.id == "w1" })?.shellKind == .fish)
        #expect(spaces.first(where: { $0.workspace.id == "w2" })?.shellKind == nil)
    }
}
