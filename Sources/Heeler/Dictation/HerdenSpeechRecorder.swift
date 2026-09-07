@preconcurrency import AVFAudio
import Foundation
import OSLog
@preconcurrency import Speech

/// Streams on-device speech recognition into the live terminal. Herden keeps
/// this separate from Apple's keyboard dictation so it works while the compact
/// terminal controls are visible and never sends audio off the phone.
@MainActor
final class HerdenSpeechRecorder: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case recording
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var supportedLocales: [Locale] = []
    @Published var selectedLocale = Locale.current
    @Published private(set) var settingsRequired = false

    private let logger = Logger(subsystem: "com.3loc.herden", category: "speech")
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var generation = 0

    func prepareLocales() {
        supportedLocales = SFSpeechRecognizer.supportedLocales()
            .filter { SFSpeechRecognizer(locale: $0)?.supportsOnDeviceRecognition == true }
            .sorted { $0.identifier < $1.identifier }
        if let exact = supportedLocales.first(where: { $0.identifier == Locale.current.identifier }) {
            selectedLocale = exact
        } else if let language = Locale.current.language.languageCode?.identifier,
                  let compatible = supportedLocales.first(where: {
                      $0.language.languageCode?.identifier == language
                  }) {
            selectedLocale = compatible
        }
        if supportedLocales.isEmpty {
            state = .unavailable("On-device speech recognition is not available on this iPhone.")
        }
    }

    func start() async {
        guard state != .preparing, state != .recording else { return }
        generation += 1
        let attempt = generation
        state = .preparing
        transcript = ""
        settingsRequired = false
        do {
            let permitted = await Self.hasPermissions()
            guard generation == attempt, state == .preparing else { return }
            guard permitted else { throw HerdenSpeechFailure.permissionDenied }
            guard let recognizer = SFSpeechRecognizer(locale: selectedLocale),
                  recognizer.isAvailable,
                  recognizer.supportsOnDeviceRecognition else {
                throw HerdenSpeechFailure.modelUnavailable
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.taskHint = .dictation
            request.contextualStrings = [
                "Codex", "Herden", "Herdr", "Forgejo", "Claude", "terminal",
            ]
            self.request = request
            task = Self.makeRecognitionTask(
                recognizer: recognizer,
                request: request,
                recorder: self,
                generation: attempt)
            try startAudio(request: request)
            state = .recording
        } catch {
            guard generation == attempt else { return }
            stopAudio()
            request = nil
            task?.cancel()
            task = nil
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
            settingsRequired = (error as? HerdenSpeechFailure)?.requiresSettings == true
            state = .unavailable(error.localizedDescription)
            log(error)
        }
    }

    func stop() {
        guard state == .preparing || state == .recording else { return }
        generation += 1
        stopAudio()
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
        state = .idle
    }

    private func startAudio(request: SFSpeechAudioBufferRecognitionRequest) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        Self.installAudioTap(input: input, format: format, request: request)
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func stopAfterRecognitionFailure(_ failure: HerdenSpeechCallbackFailure) {
        stopAudio()
        request?.endAudio()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
        state = .unavailable("Speech recognition stopped: \(failure.message)")
        logger.error(
            "recognition stopped domain=\(failure.domain, privacy: .public) code=\(failure.code) message=\(failure.message, privacy: .public)")
    }

    private nonisolated static func hasPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
    }

    private nonisolated static func makeRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        recorder: HerdenSpeechRecorder,
        generation: Int
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak recorder] result, error in
            let transcript = result?.bestTranscription.formattedString
            let failure = error.map { error in
                let value = error as NSError
                return HerdenSpeechCallbackFailure(
                    domain: value.domain,
                    code: value.code,
                    message: value.localizedDescription)
            }
            Task { @MainActor [weak recorder, transcript, failure] in
                guard let recorder,
                      recorder.task != nil,
                      recorder.generation == generation else { return }
                if let transcript { recorder.transcript = transcript }
                if let failure { recorder.stopAfterRecognitionFailure(failure) }
            }
        }
    }

    private nonisolated static func installAudioTap(
        input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private func log(_ error: Error) {
        let value = error as NSError
        logger.error(
            "start failed domain=\(value.domain, privacy: .public) code=\(value.code) message=\(value.localizedDescription, privacy: .public)")
    }
}

private struct HerdenSpeechCallbackFailure: Sendable {
    let domain: String
    let code: Int
    let message: String
}

enum HerdenSpeechFailure: LocalizedError, Equatable {
    case permissionDenied
    case modelUnavailable

    var requiresSettings: Bool { self == .permissionDenied }

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Microphone or Speech Recognition access is denied. Enable it in Settings."
        case .modelUnavailable:
            "On-device speech recognition is not available for this language."
        }
    }
}

/// Keeps partial-result corrections honest: when Speech revises a previous
/// word, send enough DEL bytes to replace only the changed suffix.
struct HerdenDictationInputState: Equatable {
    private var terminalTranscript = ""
    private(set) var isActive = false

    mutating func begin() {
        terminalTranscript = ""
        isActive = true
    }

    mutating func apply(_ transcript: String, locale: Locale) -> Data {
        guard isActive else { return Data() }
        let command = Self.singleLine(transcript).lowercased(with: locale)
        let edit = Self.terminalEdit(from: terminalTranscript, to: command)
        terminalTranscript = command
        // Defense in depth at the PTY boundary: dictation may edit the line,
        // but only the explicit Return key is allowed to submit it.
        return Data(edit.utf8.filter { $0 != 0x0A && $0 != 0x0D })
    }

    mutating func end() {
        terminalTranscript = ""
        isActive = false
    }

    static func terminalEdit(from old: String, to new: String) -> String {
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        let sharedCount = zip(oldCharacters, newCharacters)
            .prefix { $0 == $1 }
            .count
        let deletes = String(repeating: "\u{7f}", count: oldCharacters.count - sharedCount)
        return deletes + String(newCharacters.dropFirst(sharedCount))
    }

    static func singleLine(_ transcript: String) -> String {
        var result = ""
        var replacedNewline = false
        for scalar in transcript.unicodeScalars {
            if CharacterSet.newlines.contains(scalar) {
                if !result.hasSuffix(" ") { result.append(" ") }
                replacedNewline = true
            } else {
                result.unicodeScalars.append(scalar)
                replacedNewline = false
            }
        }
        if replacedNewline { return result.trimmingCharacters(in: .whitespaces) }
        return result
    }
}
