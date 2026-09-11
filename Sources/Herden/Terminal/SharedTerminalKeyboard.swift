import SwiftUI
import UIKit

/// One everyday toolbar for both Agent and Space terminals.
struct TerminalKeyboard: View {
    let keyboardControl: TerminalKeyboardControl?
    let isKeyboardUp: Bool
    let canUpload: Bool
    let documents: () -> Void
    let media: () -> Void
    let recordAudio: (PreparedFile) -> Bool
    let toggleSystemKeyboard: () -> Void
    let dismissSystemKeyboard: () -> Void
    let sendQuickKey: (AgentQuickKey) -> Void
    let sendInput: (Data) -> Void
    @StateObject private var speech = HerdenSpeechRecorder()
    @State private var dictationInput = HerdenDictationInputState()
    @State private var recordingTarget: RecordingTarget?
    @Environment(\.scenePhase) private var scenePhase

    private struct RecordingTarget: Identifiable {
        let id: ObjectIdentifier
    }

    var body: some View {
        VStack(spacing: 6) {
            if case let .unavailable(message) = speech.state { speechFailure(message) }
            TerminalDirectInputDeck(
                isKeyboardUp: isKeyboardUp,
                isDictating: dictationInput.isActive,
                canInput: keyboardControl?.terminal != nil,
                canUpload: canUpload && keyboardControl?.terminal != nil,
                toggleKeyboard: {
                    finishDictation()
                    toggleSystemKeyboard()
                },
                toggleDictation: toggleDictation,
                recordAudio: {
                    finishDictation()
                    guard let terminal = keyboardControl?.terminal else { return }
                    recordingTarget = RecordingTarget(id: ObjectIdentifier(terminal))
                    dismissSystemKeyboard()
                },
                sendQuickKey: { key in
                    finishDictation()
                    sendQuickKey(key)
                },
                sendInput: { data in
                    finishDictation()
                    sendInput(data)
                },
                documents: { finishDictation(); documents() },
                media: { finishDictation(); media() },
                paste: {
                    finishDictation()
                    guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
                    keyboardControl?.paste(text)
                },
                speech: speech,
                finishDictation: finishDictation)
        }
        .accessibilityIdentifier("terminal-keyboard")
        .sheet(item: $recordingTarget) { target in
            AudioRecordingSheet { file in
                guard let terminal = keyboardControl?.terminal,
                      ObjectIdentifier(terminal) == target.id, canUpload else { return false }
                return recordAudio(file)
            }
        }
        .task { speech.prepareLocales() }
        .onAppear { keyboardControl?.onPromptEditing = { finishDictation() } }
        .onDisappear {
            finishDictation()
            recordingTarget = nil
            keyboardControl?.onPromptEditing = nil
        }
        .onChange(of: speech.transcript) { _, transcript in
            let bytes = dictationInput.apply(transcript, locale: speech.selectedLocale)
            if !bytes.isEmpty { sendInput(bytes) }
        }
        .onChange(of: speech.state) { _, state in
            if state != .preparing, state != .recording { dictationInput.end() }
        }
        .onChange(of: isKeyboardUp) { _, isUp in
            if isUp, dictationInput.isActive { finishDictation() }
        }
        .onChange(of: keyboardControl?.terminal) { _, _ in
            finishDictation()
            recordingTarget = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && speech.state == .recording) {
                finishDictation()
            }
        }
    }

    private func toggleDictation() {
        if dictationInput.isActive { finishDictation(); return }
        dismissSystemKeyboard()
        dictationInput.begin()
        Task {
            guard dictationInput.isActive else { return }
            await speech.start()
            if speech.state != .preparing, speech.state != .recording { dictationInput.end() }
        }
    }

    private func finishDictation() {
        speech.stop()
        dictationInput.end()
    }

    private func speechFailure(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).lineLimit(2)
            Spacer(minLength: 0)
            if speech.settingsRequired {
                Button("Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Brand.fault)
        .padding(.horizontal, 10)
    }
}

/// The keys used under pressure stay fixed under the thumb; uncommon terminal
/// controls live in More.
struct TerminalDirectInputDeck: View {
    let isKeyboardUp: Bool
    let isDictating: Bool
    let canInput: Bool
    let canUpload: Bool
    let toggleKeyboard: () -> Void
    let toggleDictation: () -> Void
    let recordAudio: () -> Void
    let sendQuickKey: (AgentQuickKey) -> Void
    let sendInput: (Data) -> Void
    let documents: () -> Void
    let media: () -> Void
    let paste: () -> Void
    @ObservedObject var speech: HerdenSpeechRecorder
    let finishDictation: () -> Void

    static let controlNames = [
        "Left Arrow", "Right Arrow", "Backspace", "Control C", "Return", "More",
        "Attach", "Paste", "Dictate text", "Record audio", "Keyboard",
    ]
    static let moreControlNames = [
        "Escape", "Tab", "Ctrl-B", "Up Arrow", "Down Arrow", "Insert text",
        "Dictation Language",
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                repeatingKey(.left, width: 44)
                repeatingKey(.right, width: 44)
                repeatingKey(.backspace, width: 50)
                quickKey(.controlC, title: "Ctrl-C", width: 58)
                quickKey(.enter, systemImage: "return", width: 50)
                moreMenu
            }
            HStack(spacing: 6) {
                Menu {
                    Button("Documents", systemImage: "doc", action: documents)
                    Button("Photos", systemImage: "photo", action: media)
                } label: {
                    label("Attach", image: "paperclip")
                }
                .buttonStyle(TerminalToolbarButtonStyle())
                .disabled(!canUpload)
                .accessibilityIdentifier("terminal-attach")
                Button(action: paste) { label("Paste", image: "doc.on.clipboard") }
                    .buttonStyle(TerminalToolbarButtonStyle())
                    .disabled(!canInput)
                    .accessibilityHint("Pastes clipboard text immediately")
                    .accessibilityIdentifier("terminal-paste")
                Button(action: toggleDictation) {
                    label(isDictating ? "Stop" : "Dictate",
                          image: isDictating ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(TerminalToolbarButtonStyle(isRecording: isDictating))
                .disabled(!canInput)
                .accessibilityHint("Uses Apple speech recognition on this iPhone")
                .accessibilityIdentifier("terminal-dictate")
                Button(action: recordAudio) { label("Audio", image: "waveform") }
                    .buttonStyle(TerminalToolbarButtonStyle())
                    .disabled(!canUpload)
                    .accessibilityHint("Record and review an audio attachment")
                    .accessibilityIdentifier("terminal-record-audio")
                Button(action: toggleKeyboard) {
                    Image(systemName: isKeyboardUp ? "keyboard.chevron.compact.down" : "keyboard")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(TerminalToolbarButtonStyle())
                .disabled(!canInput)
                .accessibilityLabel(isKeyboardUp ? "Hide keyboard" : "Show keyboard")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Brand.elevated)
        .accessibilityIdentifier("terminal-control-deck")
    }

    private func repeatingKey(_ key: AgentQuickKey, width: CGFloat) -> some View {
        TerminalRepeatingArrow(key: key, enabled: canInput) {
            UIDevice.current.playInputClick()
            sendQuickKey(key)
        }
        .frame(width: width, height: 44)
    }

    private func quickKey(
        _ key: AgentQuickKey,
        title: String? = nil,
        systemImage: String? = nil,
        width: CGFloat
    ) -> some View {
        Button {
            sendQuickKey(key)
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                } else {
                    Text(title ?? key.title ?? key.accessibilityLabel)
                        .font(Brand.mono(.caption, weight: .semibold))
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(width: width, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TerminalToolbarButtonStyle())
        .disabled(!canInput)
        .accessibilityLabel(key.accessibilityLabel)
        .accessibilityHint("Sends this key directly to the Agent")
    }

    private func label(_ title: String, image: String) -> some View {
        Label(title, systemImage: image)
            .font(Brand.sans(.caption, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }

    private var moreMenu: some View {
        Menu {
            Button("Insert text (Vim)", action: { sendInput(Data("i".utf8)) })
            Button("Escape", action: { sendQuickKey(.escape) })
            Button("Tab", action: { sendQuickKey(.tab) })
            Button("Ctrl-B", action: { sendInput(Data([0x02])) })
            Button("Up", systemImage: "arrow.up", action: { sendQuickKey(.up) })
            Button("Down", systemImage: "arrow.down", action: { sendQuickKey(.down) })
            Divider()
            Picker("Dictation Language", selection: Binding(
                get: { speech.selectedLocale.identifier },
                set: { finishDictation(); speech.selectLocale(identifier: $0) })
            ) {
                ForEach(speech.supportedLocales, id: \.identifier) { locale in
                    Text(speech.displayName(for: locale)).tag(locale.identifier)
                }
            }
            .disabled(speech.supportedLocales.isEmpty)
        } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44)
        }
        .buttonStyle(TerminalToolbarButtonStyle())
        .disabled(!canInput)
        .accessibilityLabel("More terminal controls")
    }
}

private struct TerminalToolbarButtonStyle: ButtonStyle {
    var isRecording = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isRecording ? Brand.background : Brand.ink)
            .background((isRecording ? Brand.fault : Brand.card).opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Brand.hairline, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// Reuse the terminal pad's hold/release semantics, including cancellation when
/// the finger leaves the key. Updating the action prevents stale-terminal repeats.
struct TerminalRepeatingArrow: UIViewRepresentable {
    let key: AgentQuickKey
    let enabled: Bool
    let action: () -> Void

    func makeUIView(context: Context) -> TerminalKeyButton {
        TerminalKeyButton(configuration: .plain(), repeats: true, action: action)
    }

    func updateUIView(_ button: TerminalKeyButton, context: Context) {
        button.keyAction = action
        button.isEnabled = enabled
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: key.systemImageName ?? "arrow.left")
        configuration.baseForegroundColor = UIColor(Brand.ink)
        configuration.background.backgroundColor = UIColor(Brand.card)
        configuration.background.cornerRadius = 8
        configuration.background.strokeColor = UIColor(Brand.hairline)
        configuration.background.strokeWidth = 1
        button.configuration = configuration
        button.accessibilityLabel = key.accessibilityLabel
        button.accessibilityHint = "Hold to move repeatedly"
        switch key {
        case .left: button.accessibilityIdentifier = "terminal-arrow-left"
        case .right: button.accessibilityIdentifier = "terminal-arrow-right"
        case .backspace: button.accessibilityIdentifier = "terminal-backspace"
        default: button.accessibilityIdentifier = nil
        }
    }

    static func dismantleUIView(_ button: TerminalKeyButton, coordinator: ()) {
        button.cancelTimers()
    }
}
