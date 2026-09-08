import Foundation
import Observation

@MainActor
@Observable
final class ShareViewModel {
    private struct Discovery: Sendable {
        let host: Host
        let transport: any Transport
        let agents: [Agent]
        let workspaceNames: [String: String]
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
    private(set) var transfer: SharedTransfer?
    private(set) var isBusy = false

    private let extensionContext: NSExtensionContext?
    private var preparedFile: PreparedFile?
    private var transports: [Host.ID: any Transport] = [:]
    private var operation: Task<Void, Never>?
    private var cancelled = false
    private var transferStore: SharedTransferStore?

    init(extensionContext: NSExtensionContext?) {
        self.extensionContext = extensionContext
    }

    func load() async {
        guard !cancelled, preparedFile == nil else { return }
        do {
            transferStore = try SharedTransferStore()
            let loaded = try await ShareItemLoader.load(from: extensionContext)
            defer { try? FileManager.default.removeItem(at: loaded.url) }
            filename = loaded.displayName
            preparedFile = try await FilePreparer().prepare(loaded.url)
            try Task.checkCancellation()
            guard !cancelled else {
                try? preparedFile?.remove()
                preparedFile = nil
                return
            }

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
                    guard !cancelled else {
                        try? await discovery.transport.close()
                        continue
                    }
                    transports[discovery.host.id] = discovery.transport
                    destinations.append(contentsOf: discovery.agents.map {
                        ShareDestination(host: discovery.host, agent: $0,
                            workspaceName: discovery.workspaceNames[$0.workspaceID])
                    })
                }
            }

            destinations.sort {
                if $0.host.displayName != $1.host.displayName {
                    return $0.host.displayName.localizedCaseInsensitiveCompare(
                        $1.host.displayName) == .orderedAscending
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            guard !cancelled else { return }
            phase = destinations.isEmpty
                ? .failed("No reachable Agents. Open Herden to check the Host connection.")
                : .choosing
        } catch FilePreparationError.sourceTooLarge {
            phase = .failed("That file is larger than Herden’s 64 MB sharing limit.")
        } catch {
            phase = .failed("Herden couldn’t read this item.")
        }
    }

    func send(to destination: ShareDestination) {
        guard !isBusy, transfer == nil, !cancelled else { return }
        operation = Task { await deliver(to: destination) }
        isBusy = true
    }

    private func deliver(to destination: ShareDestination) async {
        defer { isBusy = false; operation = nil }
        guard let file = preparedFile, let transport = transports[destination.host.id] else {
            phase = .failed("That Agent is no longer available.")
            return
        }
        phase = .sending(progress: 0)
        do {
            guard let store = transferStore else { throw CocoaError(.fileWriteUnknown) }
            let record = try store.create(file: file, filename: filename, host: destination.host,
                paneID: destination.agent.paneID, agentName: destination.title)
            transfer = record
            try? file.remove()
            preparedFile = nil
            try await perform(record, store: store, transport: transport)
        } catch {
            phase = .failed(transfer?.message ?? "The file could not be prepared for sharing.")
        }
    }

    func retry() {
        guard !isBusy, !cancelled, let record = transfer, record.canRetry,
              let store = transferStore else { return }
        isBusy = true
        phase = .sending(progress: 0)
        operation = Task {
            defer { isBusy = false; operation = nil }
            do {
                let transport = try await SharedTransferDelivery.connect(record.host)
                transports[record.host.id] = transport
                try await perform(record, store: store, transport: transport)
            } catch { phase = .failed(transfer?.message ?? "Reconnect and retry in Herden.") }
        }
    }

    private func perform(_ record: SharedTransfer, store: SharedTransferStore,
                         transport: any Transport) async throws {
        do {
            try await SharedTransferDelivery.run(id: record.id, store: store,
                stage: { file, progress in try await transport.stageFile(file, progress: progress) },
                insert: { params in try await transport.sendPaneInput(params) },
                changed: { [weak self] current in
                    self?.transfer = current
                    self?.phase = .sending(progress: Double(current.transferredBytes) / Double(max(1, current.byteCount)))
                })
            phase = transfer?.status == .added ? .sent : .failed(transfer?.message ?? "Open Herden to check the transfer.")
        } catch {
            await closeConnections()
            throw error
        }
        await closeConnections()
    }

    private func closeConnections() async {
        let connections = Array(transports.values)
        transports = [:]
        for transport in connections { try? await transport.close() }
    }

    func done() { extensionContext?.completeRequest(returningItems: nil) }

    func pause() { operation?.cancel() }

    func chooseAnotherAgent() {
        guard transfer == nil, !destinations.isEmpty else { return }
        phase = .choosing
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        operation?.cancel()
        if let preparedFile { try? preparedFile.remove() }
        preparedFile = nil
        Task {
            // Let structured upload compensation finish before tearing down SSH.
            await operation?.value
            await closeConnections()
            extensionContext?.cancelRequest(withError: CancellationError())
        }
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
            let snapshot = try await transport.sessionSnapshot()
            let names = Dictionary(snapshot.workspaces.map { ($0.workspaceID, $0.label) },
                uniquingKeysWith: { first, _ in first })
            return Discovery(host: host, transport: transport,
                agents: snapshot.agents.map(Agent.init), workspaceNames: names)
        } catch {
            if let connected { try? await connected.close() }
            return nil
        }
    }
}
