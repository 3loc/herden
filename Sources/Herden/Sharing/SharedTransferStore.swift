import Foundation
import Darwin

struct SharedTransfer: Codable, Identifiable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case waiting, uploading, uploaded, inserting, added, interrupted, uncertain
    }

    let id: UUID
    let host: Host
    let paneID: String
    let agentName: String
    let filename: String
    let fileExtension: String
    let byteCount: Int64
    var status: Status = .waiting
    var transferredBytes: Int64 = 0
    var remotePath: String?
    var updatedAt = Date()

    var canRetry: Bool {
        [.waiting, .interrupted, .uploaded].contains(status)
    }

    var message: String {
        switch status {
        case .waiting: "Ready to upload"
        case .uploading: "Uploading…"
        case .uploaded: "Uploaded — ready to insert the path"
        case .inserting: "Adding the path…"
        case .added: "File added — open the Agent to add text."
        case .interrupted: "Transfer interrupted. Retry when connected."
        case .uncertain: "File uploaded. Check the Agent before pasting its path again."
        }
    }
}

/// One atomic record per transfer. The operation lease is a nonblocking POSIX
/// lock held across upload and insertion; it is released by the OS on death.
/// Readers never take the lease. Recovery only changes records after acquiring
/// it, so a suspended extension cannot race a second uploader in the app.
struct SharedTransferStore: Sendable {
    let directory: URL

    init(directory: URL) { self.directory = directory }

    init() throws {
        guard let root = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedAppStorage.appGroup)
        else { throw CocoaError(.fileNoSuchFile) }
        directory = root.appendingPathComponent("Transfers", isDirectory: true)
    }

    func create(file: PreparedFile, filename: String, host: Host, paneID: String,
                agentName: String) throws -> SharedTransfer {
        let record = SharedTransfer(id: UUID(), host: host, paneID: paneID,
                                    agentName: agentName, filename: filename,
                                    fileExtension: file.fileExtension, byteCount: file.byteCount)
        try ensureDirectory()
        let target = sourceURL(record.id)
        try FileManager.default.copyItem(at: file.fileURL, to: target)
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: target.path)
            try save(record)
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return record
    }

    func save(_ record: SharedTransfer) throws {
        try ensureDirectory()
        var record = record
        record.updatedAt = Date()
        try JSONEncoder().encode(record).write(
            to: recordURL(record.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func read(_ id: UUID) throws -> SharedTransfer {
        try JSONDecoder().decode(SharedTransfer.self, from: Data(contentsOf: recordURL(id)))
    }

    func records() throws -> [SharedTransfer] {
        try ensureDirectory()
        return try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(SharedTransfer.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func preparedFile(_ record: SharedTransfer) -> PreparedFile {
        PreparedFile(fileURL: sourceURL(record.id), fileExtension: record.fileExtension,
                     byteCount: record.byteCount)
    }

    func removeSource(_ id: UUID) {
        try? FileManager.default.removeItem(at: sourceURL(id))
    }

    func dismiss(_ id: UUID) throws {
        guard let lease = try lease(id) else { return }
        defer { lease.release() }
        try FileManager.default.removeItem(at: recordURL(id))
        removeSource(id)
        // Keep the tiny lock inode: unlinking it can create two lock domains.
    }

    func recover() throws {
        for var record in try records() {
            guard [.uploading, .inserting].contains(record.status),
                  let lease = try lease(record.id) else { continue }
            defer { lease.release() }
            record = try read(record.id)
            switch record.status {
            case .uploading: record.status = .interrupted
            case .inserting: record.status = .uncertain
            default: continue
            }
            try save(record)
        }
    }

    func lease(_ id: UUID) throws -> SharedTransferLease? {
        try ensureDirectory()
        return try SharedTransferLease(url: directory.appendingPathComponent("\(id).lock"))
    }

    private func sourceURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id).source") }
    private func recordURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id).json") }
    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

final class SharedTransferLease {
    private var descriptor: Int32
    init?(url: URL) throws {
        descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            descriptor = -1
            if code == EWOULDBLOCK { return nil }
            throw CocoaError(.fileWriteUnknown)
        }
    }
    func release() {
        if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 }
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}
