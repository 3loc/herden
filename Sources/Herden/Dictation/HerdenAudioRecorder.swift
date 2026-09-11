@preconcurrency import AVFAudio
import Foundation

/// Recording and playback stay on the phone until the user attaches the file.
@MainActor
protocol AudioRecordingDevice: AnyObject {
    var isRecording: Bool { get }
    var isPlaying: Bool { get }
    var elapsed: TimeInterval { get }
    func start(at url: URL) throws
    func finish() throws -> TimeInterval
    func play(_ url: URL) throws
    func stop()
}

@MainActor
final class SystemAudioRecordingDevice: AudioRecordingDevice {
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?

    var isRecording: Bool { recorder?.isRecording == true }
    var isPlaying: Bool { player?.isPlaying == true }
    var elapsed: TimeInterval { recorder?.currentTime ?? 0 }

    func start(at url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ])
        self.recorder = recorder
        guard recorder.prepareToRecord(), recorder.record(forDuration: 600) else {
            throw AudioRecordingFailure.couldNotRecord
        }
    }

    func finish() throws -> TimeInterval {
        guard let recorder else { throw AudioRecordingFailure.emptyRecording }
        recorder.stop()
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        // Verify a decodable, nonempty audio stream, not merely an M4A header.
        let file = try AVAudioFile(forReading: recorder.url)
        guard file.length > 0, file.processingFormat.sampleRate > 0 else {
            throw AudioRecordingFailure.emptyRecording
        }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    func play(_ url: URL) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        let player = try AVAudioPlayer(contentsOf: url)
        self.player = player
        guard player.play() else { throw AudioRecordingFailure.couldNotPlay }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum AudioRecordingFailure: LocalizedError {
    case couldNotRecord, emptyRecording, couldNotPlay

    var errorDescription: String? {
        switch self {
        case .couldNotRecord: "Recording could not start. Check your microphone and try again."
        case .emptyRecording: "No audio was recorded. Please try again."
        case .couldNotPlay: "This recording could not be played."
        }
    }
}

@MainActor
final class HerdenAudioRecorder: ObservableObject {
    enum State: Equatable { case idle, preparing, recording, review }
    static let defaultDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HerdenAudioRecordings", isDirectory: true)

    @Published private(set) var state: State = .idle
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var message: String?
    @Published private(set) var settingsRequired = false
    private(set) var preparedFile: PreparedFile?
    private var fileURL: URL?
    private var generation = 0
    private let device: any AudioRecordingDevice
    private let directory: URL
    private let permission: () async -> Bool

    init(
        device: any AudioRecordingDevice = SystemAudioRecordingDevice(),
        directory: URL = HerdenAudioRecorder.defaultDirectory,
        permission: @escaping () async -> Bool = {
            await AVAudioApplication.requestRecordPermission()
        }
    ) {
        self.device = device
        self.directory = directory
        self.permission = permission
    }

    func start() async {
        guard state == .idle else { return }
        generation += 1
        let attempt = generation
        state = .preparing
        message = nil
        settingsRequired = false
        let allowed = await permission()
        guard generation == attempt, state == .preparing else { return }
        guard allowed else {
            state = .idle
            settingsRequired = true
            message = "Allow microphone access in Settings to record audio."
            return
        }
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.complete])
            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            var protectedDirectory = directory
            try protectedDirectory.setResourceValues(excluded)
            let url = directory.appendingPathComponent("\(UUID().uuidString).m4a")
            fileURL = url
            try device.start(at: url)
            try manager.setAttributes([.protectionKey: FileProtectionType.complete],
                                      ofItemAtPath: url.path)
            duration = 0
            state = .recording
        } catch {
            discard()
            message = error.localizedDescription
        }
    }

    /// Called by the visible recorder, including when its audio session is interrupted.
    func finish() {
        if state == .preparing {
            generation += 1
            state = .idle
            return
        }
        guard state == .recording, let fileURL else { return }
        do {
            duration = try device.finish()
            let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= FilePreparer.maximumByteCount, duration > 0 else {
                throw AudioRecordingFailure.emptyRecording
            }
            preparedFile = PreparedFile(fileURL: fileURL, fileExtension: "m4a", byteCount: Int64(size))
            state = .review
        } catch {
            discard()
            message = error.localizedDescription
        }
    }

    func tick() {
        if state == .recording {
            if device.isRecording { duration = device.elapsed }
            else { finish() } // Time limit, device loss or interruption: never auto-resume.
        }
        if isPlaying, !device.isPlaying {
            device.stop()
            isPlaying = false
        }
    }

    func togglePlayback() {
        guard state == .review, let preparedFile else { return }
        if isPlaying {
            device.stop()
            isPlaying = false
        } else {
            do {
                try device.play(preparedFile.fileURL)
                isPlaying = true
                message = nil
            } catch {
                device.stop()
                message = error.localizedDescription
            }
        }
    }

    func suspend() {
        finish()
        device.stop()
        isPlaying = false
    }

    /// Transfer ownership synchronously. A busy/disconnected destination must
    /// leave the review file available; sheet dismissal must not delete an upload.
    func attach(using accept: (PreparedFile) -> Bool) -> Bool {
        guard state == .review, let preparedFile else { return false }
        device.stop()
        isPlaying = false
        guard accept(preparedFile) else {
            message = "The terminal is not ready. Reconnect or finish the current upload, then try again."
            return false
        }
        self.preparedFile = nil
        fileURL = nil
        state = .idle
        return true
    }

    func discard() {
        generation += 1
        device.stop()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        preparedFile = nil
        state = .idle
        duration = 0
        isPlaying = false
        message = nil
    }

    static func cleanupRemnants() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: defaultDirectory.path) else { return }
        try manager.removeItem(at: defaultDirectory)
    }
}
