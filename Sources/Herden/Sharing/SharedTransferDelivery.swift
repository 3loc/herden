import Foundation

@MainActor
enum SharedTransferDelivery {
    typealias Stage = (PreparedFile, @escaping @Sendable (AttachmentStageProgress) async -> Void) async throws -> StagedFile
    typealias Insert = (PaneSendInputParams) async throws -> Void

    /// Never retries insertion. A lost acknowledgement is indistinguishable
    /// from a delivered paste; persist that boundary before writing to the Host.
    static func run(id: UUID, store: SharedTransferStore, stage: Stage, insert: Insert,
                    changed: @escaping @MainActor (SharedTransfer) -> Void = { _ in }) async throws {
        guard let lease = try store.lease(id) else { return }
        defer { lease.release() }
        var record = try store.read(id)
        guard record.canRetry else { return }
        do {
            try Task.checkCancellation()
            if record.remotePath == nil {
                record.status = .uploading
                record.transferredBytes = 0
                try store.save(record)
                changed(record)
                let staged = try await stage(store.preparedFile(record)) { progress in
                    await MainActor.run {
                        guard var current = try? store.read(id), current.status == .uploading else { return }
                        // Avoid a disk write for every SFTP packet.
                        guard progress.transferredBytes == progress.totalBytes
                            || progress.transferredBytes - current.transferredBytes >= 262_144 else { return }
                        current.transferredBytes = progress.transferredBytes
                        try? store.save(current)
                        changed(current)
                    }
                }
                record.remotePath = staged.path
                record.transferredBytes = record.byteCount
                record.status = .uploaded
                try store.save(record)
                changed(record)
            }
            try Task.checkCancellation()
            guard let path = record.remotePath else { throw CocoaError(.fileReadUnknown) }
            _ = try StagedFile(path: path)
            record.status = .inserting
            try store.save(record)
            changed(record)
            // Text only: neither newline nor keys. The Host brackets the paste
            // when the receiving terminal requests bracketed paste.
            try await insert(PaneSendInputParams(paneID: record.paneID, text: path + " "))
            record.status = .added
            try store.save(record)
            store.removeSource(id)
            changed(record)
        } catch {
            record.status = record.status == .inserting ? .uncertain
                : (record.remotePath == nil ? .interrupted : .uploaded)
            try? store.save(record)
            changed(record)
            throw error
        }
    }

    static func connect(_ host: Host) async throws -> any Transport {
        let credentials = try HostCredentialsProvider().credentials(for: host)
        let policy = HostKeyPolicy(knownHosts: UserDefaultsKnownHostsStore.shared,
                                   confirmFirstConnect: { _ in false })
        let transport = try await SSHTransportConnector().connect(settings:
            SSHTransportSettings(host: host, credentials: credentials, hostKeyPolicy: policy))
        do {
            _ = try await transport.ping()
            return transport
        } catch {
            try? await transport.close()
            throw error
        }
    }
}
