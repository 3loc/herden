import SwiftUI
import UIKit

@MainActor
struct AgentDirectInputChromeContext {
    struct Presentation {
        let status: AgentStatus
        let hostTelemetry: HostTelemetryPresentation?
        let chromeColorScheme: ColorScheme
        let isKeyboardUp: Bool
        let isToolsKeyboardPresented: Bool
    }

    struct Interactions {
        let switcher: TerminalAgentSwitcher
        let actions: AgentComposerActions
        let showConsole: () -> Void
        let toggleKeyboard: () -> Void
        let dismissKeyboard: () -> Void
        let switchKeyboard: (() -> Void)?
        let sendQuickKey: (AgentQuickKey) -> Void
        let sendInput: (Data) -> Void
        var keyboardControl: TerminalKeyboardControl? = nil
    }

    let presentation: Presentation
    let interactions: Interactions
}

/// Herden writes directly into the attached PTY: there is no second composer
/// or hidden draft whose contents can disagree with the terminal.
struct AgentDirectInputChrome: View {
    let context: AgentDirectInputChromeContext
    @StateObject private var speech = HerdenSpeechRecorder()
    @State private var dictationInput = HerdenDictationInputState()

    private var presentation: AgentDirectInputChromeContext.Presentation {
        context.presentation
    }

    private var interactions: AgentDirectInputChromeContext.Interactions {
        context.interactions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                AgentConsoleButton(action: showConsole)
                AgentDetailStatusChrome(
                    status: presentation.status,
                    hostTelemetry: presentation.hostTelemetry,
                    chromeColorScheme: presentation.chromeColorScheme)
                TerminalPasteButton { text in
                    finishDictation()
                    interactions.keyboardControl?.paste(text)
                }
                .disabled(interactions.keyboardControl?.terminal == nil)
                Menu {
                    Button("Add File", systemImage: "doc") {
                        finishDictation()
                        interactions.actions.addFile()
                    }
                    Button("Add Photo", systemImage: "photo") {
                        finishDictation()
                        interactions.actions.addImage()
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .disabled(!interactions.actions.canBegin || interactions.keyboardControl?.terminal == nil)
                .accessibilityLabel("Add attachment")
                .accessibilityHint("Uploads a file or photo and pastes its path without Return")
                .accessibilityIdentifier("terminal-attachments")
                moreMenu
                    .frame(width: 38, height: 30)
                    .padding(.trailing, 8)
            }

            if case let .unavailable(message) = speech.state {
                speechFailure(message)
            }

            terminalControlDeck

            TerminalAgentSwitcherRow(
                switcher: interactions.switcher,
                isKeyboardUp: presentation.isKeyboardUp,
                toggleKeyboard: interactions.toggleKeyboard,
                isToolsKeyboardPresented: presentation.isToolsKeyboardPresented,
                switchKeyboard: interactions.switchKeyboard,
                modeControl: nil)
        }
        .padding(.vertical, 8)
        .background(Brand.elevated)
        .task { speech.prepareLocales() }
        .onAppear { interactions.keyboardControl?.onPromptEditing = { finishDictation() } }
        .onDisappear {
            finishDictation()
            interactions.keyboardControl?.onPromptEditing = nil
        }
        .onChange(of: speech.transcript) { _, transcript in
            let bytes = dictationInput.apply(transcript, locale: speech.selectedLocale)
            if !bytes.isEmpty { interactions.sendInput(bytes) }
        }
        .onChange(of: speech.state) { _, state in
            if state != .preparing, state != .recording { dictationInput.end() }
        }
        .onChange(of: presentation.isKeyboardUp) { _, isUp in
            if isUp, dictationInput.isActive { finishDictation() }
        }
    }

    private var terminalControlDeck: some View {
        TerminalDirectInputDeck(
            isKeyboardUp: presentation.isKeyboardUp,
            isDictating: dictationInput.isActive,
            toggleKeyboard: toggleKeyboard,
            toggleDictation: toggleDictation,
            sendQuickKey: { key in
                finishDictation()
                interactions.sendQuickKey(key)
            },
            sendInput: { data in
                finishDictation()
                interactions.sendInput(data)
            })
    }

    private func showConsole() {
        finishDictation()
        interactions.dismissKeyboard()
        interactions.showConsole()
    }

    private func toggleKeyboard() {
        finishDictation()
        interactions.toggleKeyboard()
    }

    private func toggleDictation() {
        if dictationInput.isActive {
            finishDictation()
            return
        }
        interactions.dismissKeyboard()
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

    private var moreMenu: some View {
        Menu {
            Button("Select and Copy Text", systemImage: "doc.on.doc") {
                finishDictation()
                interactions.keyboardControl?.selectText()
            }
            .disabled(interactions.keyboardControl?.terminal == nil)
            Divider()
            if !speech.supportedLocales.isEmpty {
                Picker("Dictation Language", selection: dictationLocaleBinding) {
                    ForEach(speech.supportedLocales, id: \.identifier) { locale in
                        Text(speech.displayName(for: locale))
                            .tag(locale.identifier)
                    }
                }
                Divider()
            }
            AgentActionMenuContent(
                actions: interactions.actions,
                sections: AgentActionMenuPolicy.directInputMoreSections,
                includesDraftOwnedItems: false)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .accessibilityHint("Opens Agent actions")
    }

    private var dictationLocaleBinding: Binding<String> {
        Binding(
            get: { speech.selectedLocale.identifier },
            set: { speech.selectLocale(identifier: $0) })
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

    static let keyAccessibilityLabels = [
        "Esc", "Ctrl-B", "Control C", "Backspace",
        "h", "j", "k", "l", "/", "$",
        "i", "a", "v", "Keyboard", "Dictate", "Return",
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
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 9)
        .background(Brand.elevated)
        .accessibilityIdentifier("terminal-control-deck")
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

struct AgentConsoleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                HerdenMark(size: 18)
                Text("Spaces")
                    .font(Brand.sans(.caption, weight: .semibold))
            }
            .foregroundStyle(Brand.ink)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(Brand.card)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Brand.hairline, lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to Spaces and Agents")
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
