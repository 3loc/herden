import Foundation
import Testing

@testable import Herden

@MainActor
@Suite("Audio recording")
struct HerdenAudioRecorderTests {
    @Test func deniedPermissionDoesNotOpenMicrophoneOrCreateFile() async throws {
        let fixture = Fixture(allowed: false)
        defer { fixture.cleanup() }
        await fixture.recorder.start()
        #expect(fixture.device.starts == 0)
        #expect(fixture.recorder.state == .idle)
        #expect(fixture.recorder.settingsRequired)
        #expect(fixture.recorder.message != nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test func cancellingDuringPermissionPromptCannotStartRecordingLater() async throws {
        let gate = PermissionGate()
        let device = RecordingDevice()
        let recorder = HerdenAudioRecorder(device: device, permission: { await gate.wait() })
        let pending = Task { await recorder.start() }
        while gate.continuation == nil { await Task.yield() }
        recorder.discard()
        gate.continuation?.resume(returning: true)
        await pending.value
        #expect(device.starts == 0)
        #expect(recorder.state == .idle)
    }

    @Test func recordingIsRetainedWhenDestinationRejectsAndTransferredOnlyOnAcceptance() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        await fixture.recorder.start()
        #expect(fixture.recorder.state == .recording)
        fixture.recorder.finish()
        let file = try #require(fixture.recorder.preparedFile)
        #expect(file.fileExtension == "m4a")
        #expect(file.remoteFilename == "file.m4a")
        #expect(fixture.recorder.state == .review)
        #expect(!fixture.recorder.attach(using: { _ in false }))
        #expect(fixture.recorder.preparedFile == file)
        #expect(FileManager.default.fileExists(atPath: file.fileURL.path))
        var accepted: PreparedFile?
        #expect(fixture.recorder.attach(using: { accepted = $0; return true }))
        fixture.recorder.discard() // Sheet teardown must not delete a staged recording.
        #expect(accepted == file)
        #expect(FileManager.default.fileExists(atPath: file.fileURL.path))
    }

    @Test func discardStopsCaptureAndDeletesOnlyItsOwnRecording() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        await fixture.recorder.start()
        let url = try #require(fixture.device.url)
        fixture.recorder.discard()
        #expect(!fixture.device.isRecording)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(fixture.recorder.preparedFile == nil)
    }

    @Test func interruptionAndTimeLimitRetainReviewWithoutResuming() async throws {
        for interrupted in [true, false] {
            let fixture = Fixture()
            defer { fixture.cleanup() }
            await fixture.recorder.start()
            if interrupted { fixture.recorder.suspend() }
            else {
                fixture.device.isRecording = false
                fixture.recorder.tick()
            }
            #expect(fixture.recorder.state == .review)
            #expect(fixture.recorder.preparedFile != nil)
            #expect(!fixture.device.isRecording)
            await fixture.recorder.start()
            #expect(fixture.device.starts == 1)
        }
    }

    @Test func anUnreadableRecordingCannotBeAttached() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        fixture.device.finishFails = true
        await fixture.recorder.start()
        let url = try #require(fixture.device.url)
        fixture.recorder.finish()
        #expect(fixture.recorder.state == .idle)
        #expect(fixture.recorder.message != nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!fixture.recorder.attach(using: { _ in Issue.record("Must not offer invalid audio"); return true }))
    }

    @Test func playbackStopsOnSuspensionAndKeepsTheReview() async throws {
        let fixture = Fixture()
        defer { fixture.cleanup() }
        await fixture.recorder.start()
        fixture.recorder.finish()
        fixture.recorder.togglePlayback()
        #expect(fixture.recorder.isPlaying)
        fixture.recorder.suspend()
        #expect(!fixture.device.isPlaying)
        #expect(fixture.recorder.state == .review)
    }
}

@MainActor
private final class PermissionGate {
    var continuation: CheckedContinuation<Bool, Never>?
    func wait() async -> Bool {
        await withCheckedContinuation { continuation = $0 }
    }
}

@MainActor
private struct Fixture {
    let device = RecordingDevice()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recorder: HerdenAudioRecorder
    init(allowed: Bool = true) {
        recorder = HerdenAudioRecorder(device: device, directory: directory, permission: { allowed })
    }
    func cleanup() {
        recorder.discard()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class RecordingDevice: AudioRecordingDevice {
    var isRecording = false
    var isPlaying = false
    var elapsed: TimeInterval = 2
    var starts = 0
    var url: URL?
    var finishFails = false
    func start(at url: URL) throws {
        starts += 1
        self.url = url
        try Data([1, 2, 3, 4]).write(to: url)
        isRecording = true
    }
    func finish() throws -> TimeInterval {
        isRecording = false
        if finishFails { throw AudioRecordingFailure.emptyRecording }
        return elapsed
    }
    func play(_ url: URL) throws { isPlaying = true }
    func stop() { isRecording = false; isPlaying = false }
}
