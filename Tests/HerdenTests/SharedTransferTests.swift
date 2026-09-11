import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Herden

@Suite("Shared file delivery")
@MainActor
struct SharedTransferTests {
    @Test func destinationUsesNameThenWorkspaceBeforeAgentType() {
        let host = Host(address: "localhost", username: "ted")
        let agent = Agent(terminalID: "t1", kind: "claude", title: "Working",
            status: .idle, workspaceID: "w1", tabID: "t1", paneID: "w1:p1", cwd: "/src/herden",
            revision: 0, name: "claude")
        #expect(ShareDestination(host: host, agent: agent, workspaceName: "Herden").title == "Herden")
        let named = Agent(terminalID: "t1", kind: "claude", title: "Working",
            status: .idle, workspaceID: "w1", tabID: "t1", paneID: "w1:p1", cwd: "/src/herden",
            revision: 0, name: "release-helper")
        #expect(ShareDestination(host: host, agent: named, workspaceName: "Herden").title == "release-helper")
    }

    @Test func fileRepresentationIsCopiedBeforeProviderReleasesIt() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
        try Data("document".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = NSItemProvider()
        provider.suggestedName = "Report.pdf"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier,
            fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            return nil
        }
        let loaded = try await ShareItemLoader.load(providers: [provider])
        defer { try? FileManager.default.removeItem(at: loaded.url) }
        try FileManager.default.removeItem(at: url)
        #expect(loaded.displayName == "Report.pdf")
        #expect(loaded.url.pathExtension == "pdf")
        #expect(try Data(contentsOf: loaded.url) == Data("document".utf8))
    }

    @Test func fileURLOnlyProviderWorksAndWebLinksAreRejected() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).txt")
        try Data("document".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let loaded = try await ShareItemLoader.load(providers: [provider])
        defer { try? FileManager.default.removeItem(at: loaded.url) }
        #expect(try Data(contentsOf: loaded.url) == Data("document".utf8))
        let web = NSItemProvider(item: NSURL(string: "https://example.com"), typeIdentifier: UTType.url.identifier)
        await #expect(throws: (any Error).self) { try await ShareItemLoader.load(providers: [web]) }
        await #expect(throws: (any Error).self) { try await ShareItemLoader.load(providers: [provider, provider]) }
    }

    @Test func discordImageShareIgnoresCaptionAndSourceLink() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        try png.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = NSItemProvider()
        image.suggestedName = "discord-image.png"
        image.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier,
            fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            return nil
        }
        let caption = NSItemProvider(item: "caption" as NSString,
                                     typeIdentifier: UTType.plainText.identifier)
        let source = NSItemProvider(item: NSURL(string: "https://discord.com/channels/example"),
                                    typeIdentifier: UTType.url.identifier)

        let loaded = try await ShareItemLoader.load(providers: [caption, image, source])
        defer { try? FileManager.default.removeItem(at: loaded.url) }
        #expect(loaded.displayName == "discord-image.png")
        #expect(loaded.url.pathExtension == "png")
        #expect(try Data(contentsOf: loaded.url) == png)
    }

    private func fixture() throws -> (SharedTransferStore, SharedTransfer, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.txt")
        try Data("test document".utf8).write(to: source)
        let store = SharedTransferStore(directory: root.appendingPathComponent("transfers"))
        let file = PreparedFile(fileURL: source, fileExtension: "txt", byteCount: 13)
        let host = Host(name: "test", address: "localhost", port: 22, username: "ted", authMethod: .deviceKey)
        let record = try store.create(file: file, filename: "document.txt", host: host,
                                      paneID: "wA:pB", agentName: "claude")
        return (store, record, root)
    }

    @Test func deliveryAndReopenNeverSubmitOrReplay() async throws {
        let (store, record, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var insertions = 0
        let insert: SharedTransferDelivery.Insert = { params in
            insertions += 1
            #expect(params.paneID == "wA:pB")
            #expect(params.text == "/tmp/stage/file.txt ")
            #expect(params.keys == nil || params.keys?.isEmpty == true)
            #expect(params.text?.contains("\n") == false)
            #expect(params.text?.contains("\r") == false)
        }
        let stage: SharedTransferDelivery.Stage = { file, progress in
            #expect(try Data(contentsOf: file.fileURL) == Data("test document".utf8))
            await progress(AttachmentStageProgress(transferredBytes: 13, totalBytes: 13))
            return try StagedFile(path: "/tmp/stage/file.txt")
        }
        try await SharedTransferDelivery.run(id: record.id, store: store, stage: stage, insert: insert)
        let reopened = SharedTransferStore(directory: store.directory)
        try reopened.recover()
        #expect(try reopened.read(record.id).status == .added)
        let history = try reopened.records()
        #expect(history.count == 1)
        #expect(SharedTransfersView.bannerRecord(in: history) == nil)
        try await SharedTransferDelivery.run(id: record.id, store: reopened, stage: stage, insert: insert)
        #expect(insertions == 1)
        #expect(!FileManager.default.fileExists(atPath: store.preparedFile(record).fileURL.path))
    }

    @Test func completedShareDoesNotHideAnOlderUnfinishedTransfer() throws {
        let (store, original, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var completed = original
        completed.status = .added
        try store.save(completed)
        let persistedCompleted = try store.records()
        var pending = SharedTransfer(
            id: UUID(), host: original.host, paneID: original.paneID,
            agentName: original.agentName, filename: "pending.txt",
            fileExtension: "txt", byteCount: 13)
        pending.updatedAt = .distantPast
        for status in [SharedTransfer.Status.waiting, .uploading, .uploaded,
                       .inserting, .interrupted, .uncertain] {
            pending.status = status
            #expect(SharedTransfersView.bannerRecord(in: persistedCompleted + [pending]) == pending)
        }
        #expect(SharedTransfersView.bannerRecord(in: []) == nil)
        #expect(try store.read(original.id).status == .added)
    }

    @Test func lostAcknowledgementNeverRetriesPaste() async throws {
        let (store, record, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var insertions = 0
        let stage: SharedTransferDelivery.Stage = { _, _ in try StagedFile(path: "/tmp/file.txt") }
        let insert: SharedTransferDelivery.Insert = { _ in
            insertions += 1
            throw CocoaError(.fileReadUnknown)
        }
        do { try await SharedTransferDelivery.run(id: record.id, store: store, stage: stage, insert: insert) }
        catch {}
        #expect(try store.read(record.id).status == .uncertain)
        try store.recover()
        try await SharedTransferDelivery.run(id: record.id, store: store, stage: stage, insert: insert)
        #expect(insertions == 1)
    }

    @Test func cancelledUploadCanRetryWithoutSubmitting() async throws {
        let (store, record, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var inserted = false
        do {
            try await SharedTransferDelivery.run(id: record.id, store: store,
                stage: { _, _ in throw CancellationError() }, insert: { _ in inserted = true })
        } catch {}
        #expect(!inserted)
        #expect(try store.read(record.id).status == .interrupted)
        #expect(FileManager.default.fileExists(atPath: store.preparedFile(record).fileURL.path))
        try await SharedTransferDelivery.run(id: record.id, store: store,
            stage: { _, _ in try StagedFile(path: "/tmp/file.txt") },
            insert: { params in inserted = true; #expect(params.keys == nil) })
        #expect(inserted)
    }

    @Test func processDeathRecoveryRespectsLiveLease() throws {
        let (store, original, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var record = original
        record.status = .uploading
        try store.save(record)
        let lease = try #require(try store.lease(record.id))
        try store.recover()
        #expect(try store.read(record.id).status == .uploading)
        lease.release()
        try store.recover()
        #expect(try store.read(record.id).status == .interrupted)
        record.status = .inserting
        record.remotePath = "/tmp/file.txt"
        try store.save(record)
        try store.recover()
        #expect(try store.read(record.id).status == .uncertain)
    }

    @Test func uploadedRecoveryUsesExistingFile() async throws {
        let (store, original, root) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var record = original
        record.remotePath = "/tmp/file.txt"
        record.status = .uploaded
        try store.save(record)
        try await SharedTransferDelivery.run(id: record.id, store: store,
            stage: { _, _ in Issue.record("Uploaded files must not upload again"); throw CancellationError() },
            insert: { params in #expect(params.text == "/tmp/file.txt "); #expect(params.keys == nil) })
        #expect(try store.read(record.id).status == .added)
    }
}
