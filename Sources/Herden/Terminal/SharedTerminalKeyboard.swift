import SwiftUI
import UIKit

/// The single complete keyboard for Agent and Space terminals.
struct TerminalKeyboard: View {
    let keyboardControl: TerminalKeyboardControl?
    let isKeyboardUp: Bool
    let canUpload: Bool
    let documents: () -> Void
    let media: () -> Void
    let toggleSystemKeyboard: () -> Void
    let dismissSystemKeyboard: () -> Void
    let sendQuickKey: (AgentQuickKey) -> Void
    let sendInput: (Data) -> Void
    @StateObject private var speech = HerdenSpeechRecorder()
    @State private var dictationInput = HerdenDictationInputState()

    var body: some View {
        VStack(spacing: 6) {
            if case let .unavailable(message) = speech.state {
                speechFailure(message)
            }
            TerminalDirectInputDeck(
                isKeyboardUp: isKeyboardUp,
                isDictating: dictationInput.isActive,
                toggleKeyboard: {
                    finishDictation()
                    toggleSystemKeyboard()
                },
                toggleDictation: toggleDictation,
                sendQuickKey: { key in
                    finishDictation()
                    sendQuickKey(key)
                },
                sendInput: { data in
                    finishDictation()
                    sendInput(data)
                },
                attachments: TerminalAttachmentRow(
                    canUpload: canUpload && keyboardControl?.terminal != nil,
                    canPaste: keyboardControl?.terminal != nil,
                    documents: {
                        finishDictation()
                        documents()
                    },
                    media: {
                        finishDictation()
                        media()
                    },
                    paste: {
                        finishDictation()
                        keyboardControl?.paste($0)
                    }),
                speech: speech,
                finishDictation: finishDictation)
        }
        .accessibilityIdentifier("terminal-keyboard")
        .task { speech.prepareLocales() }
        .onAppear { keyboardControl?.onPromptEditing = { finishDictation() } }
        .onDisappear {
            finishDictation()
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
        .onChange(of: keyboardControl?.terminal) { _, _ in finishDictation() }
    }

    private func toggleDictation() {
        if dictationInput.isActive {
            finishDictation()
            return
        }
        dismissSystemKeyboard()
        dictationInput.begin()
        Task {
            await speech.start()
            if speech.state != .preparing, speech.state != .recording {
                dictationInput.end()
            }
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

/// A compact attachment row shared by Agent and Space terminal keyboards.
struct TerminalAttachmentRow: View {
    let canUpload: Bool
    let canPaste: Bool
    let documents: () -> Void
    let media: () -> Void
    let paste: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            actionButton("Documents", image: "doc", color: Brand.uploadOrange,
                         enabled: canUpload, action: documents)
                .accessibilityIdentifier("terminal-documents")
            actionButton("Media", image: "photo", color: Brand.uploadOrange,
                         enabled: canUpload, action: media)
                .accessibilityIdentifier("terminal-media")
            actionButton("Paste", image: "doc.on.clipboard", color: Brand.amber,
                         enabled: canPaste) {
                guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
                paste(text)
            }
            .accessibilityLabel("Paste")
            .accessibilityHint("Pastes clipboard text immediately")
            .accessibilityIdentifier("terminal-paste")
        }
        .accessibilityIdentifier("terminal-attachment-row")
    }

    private func actionButton(_ title: String, image: String, color: Color,
                              enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: image)
                .font(Brand.sans(.caption, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .foregroundStyle(Brand.background)
                .background(color)
                .clipShape(.rect(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// The one direct-input deck used by both Agent and ordinary Space terminals.
/// Keeping the actual controls shared prevents the two terminal surfaces from
/// silently drifting into different keyboards again.
struct TerminalDirectInputDeck: View {
    let isKeyboardUp: Bool
    let isDictating: Bool
    let toggleKeyboard: () -> Void
    let toggleDictation: () -> Void
    let sendQuickKey: (AgentQuickKey) -> Void
    let sendInput: (Data) -> Void
    let attachments: TerminalAttachmentRow
    @ObservedObject var speech: HerdenSpeechRecorder
    let finishDictation: () -> Void

    /// Stable control inventory shared by regression tests and both terminal
    /// destinations. Keyboard and Dictate have state-dependent spoken labels.
    static let controlNames = [
        "Esc", "Ctrl-B", "Control C", "Backspace",
        "h", "j", "k", "l", "/", "$",
        "i", "a", "v", "Keyboard", "Dictate", "Dictation Language", "Return",
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                key("Esc", bytes: [0x1B], tone: .modifier)
                key("Ctrl-B", bytes: [0x02], tone: .modifier)
                quickKey("Ctrl-C", key: .controlC, tone: .modifier)
                key("⌫", accessibilityLabel: "Backspace", bytes: [0x7F], tone: .modifier)
            }
            HStack(spacing: 6) {
                key("h", text: "h")
                key("j", text: "j")
                key("k", text: "k")
                key("l", text: "l")
                key("/", text: "/")
                key("$", text: "$")
            }
            HStack(spacing: 6) {
                key("i", text: "i")
                key("a", text: "a")
                key("v", text: "v")
                languageMenu
                deckButton(
                    systemImage: isKeyboardUp ? "keyboard.chevron.compact.down" : "keyboard",
                    accessibilityLabel: isKeyboardUp ? "Hide keyboard" : "Show keyboard",
                    tone: .modifier,
                    action: toggleKeyboard)
                deckButton(
                    systemImage: isDictating ? "stop.fill" : "mic.fill",
                    accessibilityLabel: isDictating ? "Stop dictation" : "Dictate",
                    tone: isDictating ? .recording : .modifier,
                    action: toggleDictation)
                key("↵", accessibilityLabel: "Return", bytes: [0x0D], tone: .accent)
            }
            attachments
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 9)
        .background(Brand.elevated)
        .accessibilityIdentifier("terminal-control-deck")
    }

    private var languageMenu: some View {
        Menu {
            Picker("Dictation Language", selection: Binding(
                get: { speech.selectedLocale.identifier },
                set: {
                    finishDictation()
                    speech.selectLocale(identifier: $0)
                })
            ) {
                ForEach(speech.supportedLocales, id: \.identifier) { locale in
                    Text(speech.displayName(for: locale)).tag(locale.identifier)
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(Brand.sans(.caption, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(TerminalDeckKeyButtonStyle(tone: .modifier))
        .disabled(speech.supportedLocales.isEmpty)
        .accessibilityLabel("Dictation Language")
        .accessibilityValue(speech.displayName(for: speech.selectedLocale))
        .accessibilityIdentifier("terminal-language")
    }

    private func key(
        _ label: String,
        accessibilityLabel: String? = nil,
        text: String,
        tone: TerminalDeckKeyTone = .standard
    ) -> some View {
        deckButton(
            label: label,
            accessibilityLabel: accessibilityLabel ?? label,
            tone: tone
        ) { send(Data(text.utf8)) }
    }

    private func quickKey(
        _ label: String,
        key: AgentQuickKey,
        tone: TerminalDeckKeyTone
    ) -> some View {
        deckButton(
            label: label,
            accessibilityLabel: key.accessibilityLabel,
            tone: tone
        ) {
            UIDevice.current.playInputClick()
            sendQuickKey(key)
        }
    }

    private func key(
        _ label: String,
        accessibilityLabel: String? = nil,
        bytes: [UInt8],
        tone: TerminalDeckKeyTone = .standard
    ) -> some View {
        deckButton(
            label: label,
            accessibilityLabel: accessibilityLabel ?? label,
            tone: tone
        ) { send(Data(bytes)) }
    }

    private func deckButton(
        label: String? = nil,
        systemImage: String? = nil,
        accessibilityLabel: String,
        tone: TerminalDeckKeyTone,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let label { Text(label) }
                else if let systemImage { Image(systemName: systemImage) }
            }
            .font(Brand.mono(.caption, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(TerminalDeckKeyButtonStyle(tone: tone))
        .accessibilityLabel(accessibilityLabel)
    }

    private func send(_ data: Data) {
        UIDevice.current.playInputClick()
        sendInput(data)
    }
}

private enum TerminalDeckKeyTone {
    case standard
    case modifier
    case accent
    case recording
}

private struct TerminalDeckKeyButtonStyle: ButtonStyle {
    let tone: TerminalDeckKeyTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.72 : 1))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(border, lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect)
    }

    private var background: Color {
        switch tone {
        case .standard, .modifier: Brand.card
        case .accent: Brand.vine
        case .recording: Brand.fault
        }
    }

    private var foreground: Color {
        switch tone {
        case .accent, .recording: Brand.background
        case .standard, .modifier: Brand.ink
        }
    }

    private var border: Color {
        switch tone {
        case .modifier: Brand.subtle.opacity(0.8)
        case .standard: Brand.hairline
        case .accent: Brand.vineLight.opacity(0.7)
        case .recording: Brand.fault
        }
    }
}
