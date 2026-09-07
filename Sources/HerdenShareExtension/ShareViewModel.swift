import Foundation
import Observation

struct ShareDestination: Identifiable, Sendable {
    let host: Host
    let agent: Agent

    var id: String { "\(host.id.uuidString):\(agent.paneID)" }
}

@MainActor
@Observable
final class ShareViewModel {
    private struct Discovery: Sendable {
        let host: Host
        let transport: any Transport
        let agents: [Agent]
    }

    enum Phase: Equatable {
        case loading
        case choosing
        case sending(progress: Double)
        case sent
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var destinations: [ShareDestination] = []
    private(set) var filename = "Shared file"

    private let extensionContext: NSExtensionContext?
    private var preparedFile: PreparedFile?
    private var transports: [Host.ID: any Transport] = [:]

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    func load() async {
        do {
            let loaded = try await ShareItemLoader.load(from: extensionContext)
            defer { try? FileManager.default.removeItem(at: loaded.url) }
            filename = loaded.displayName
            preparedFile = try await FilePreparer().prepare(loaded.url)

            let hosts = HostStore().hosts
            guard !hosts.isEmpty else {
                phase = .failed("Open Herden and add a Host first.")
                return
            }

            await withTaskGroup(of: Discovery?.self) { group in
                for host in hosts {
                    group.addTask { await Self.discover(host) }
                }
                for await discovery in group {
                    guard let discovery else { continue }
                    transports[discovery.host.id] = discovery.transport
                    destinations.append(contentsOf: discovery.agents.map {
                        ShareDestination(host: discovery.host, agent: $0)
                    })
                }
            }

            destinations.sort {
                if $0.host.displayName != $1.host.displayName {
                    return $0.host.displayName.localizedCaseInsensitiveCompare(
                        $1.host.displayName) == .orderedAscending
                }
                return $0.agent.displayName.localizedCaseInsensitiveCompare(
                    $1.agent.displayName) == .orderedAscending
            }
            phase = destinations.isEmpty
                ? .failed("No reachable Agents. Open Herden to check the Host connection.")
                : .choosing
        } catch FilePreparationError.sourceTooLarge {
            phase = .failed("That file is larger than Herden’s 64 MB sharing limit.")
        } catch {
            phase = .failed("Herden couldn’t read this item.")
        }
    }

    func send(to destination: ShareDestination) async {
        guard let file = preparedFile, let transport = transports[destination.host.id] else {
            phase = .failed("That Agent is no longer available.")
            return
        }
        phase = .sending(progress: 0)
        do {
            let staged = try await transport.stageFile(file) { [weak self] progress in
                await MainActor.run {
                    self?.phase = .sending(progress: progress.fractionCompleted)
                }
            }
            try await transport.sendPaneInput(
                PaneSendInputParams(paneID: destination.agent.paneID, text: staged.path + " "))
            phase = .sent
            try? file.remove()
            preparedFile = nil
            for transport in transports.values { try? await transport.close() }
            transports = [:]
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            phase = .failed("The file could not be delivered. Nothing was submitted to the Agent.")
        }
    }

    func chooseAnotherAgent() {
        guard !destinations.isEmpty else { return }
        phase = .choosing
    }

    func cancel() {
        if let preparedFile { try? preparedFile.remove() }
        Task {
            for transport in transports.values { try? await transport.close() }
        }
        extensionContext?.cancelRequest(withError: CancellationError())
    }

    private nonisolated static func discover(_ host: Host) async -> Discovery? {
        var connected: (any Transport)?
        do {
            let credentials = try HostCredentialsProvider().credentials(for: host)
            let policy = HostKeyPolicy(
                knownHosts: UserDefaultsKnownHostsStore.shared,
                confirmFirstConnect: { _ in false })
            let transport = try await SSHTransportConnector().connect(
                settings: SSHTransportSettings(
                    host: host, credentials: credentials, hostKeyPolicy: policy))
            connected = transport
            _ = try await transport.ping()
            let agents = try await transport.listAgents()
            return Discovery(host: host, transport: transport, agents: agents)
        } catch {
            if let connected { try? await connected.close() }
            return nil
        }
    }
}
