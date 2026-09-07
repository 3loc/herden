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
        let toggleKeyboard: () -> Void
        let dismissKeyboard: () -> Void
        let switchKeyboard: (() -> Void)?
        let sendQuickKey: (AgentQuickKey) -> Void
        let sendInput: (Data) -> Void
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
                AgentDetailStatusChrome(
                    status: presentation.status,
                    hostTelemetry: presentation.hostTelemetry,
                    chromeColorScheme: presentation.chromeColorScheme)
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
        .task { speech.prepareLocales() }
        .onDisappear { finishDictation() }
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
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                key("Esc", bytes: [0x1B], tone: .modifier)
                key("Ctrl-B", bytes: [0x02], tone: .modifier)
                key("Ctrl-C", bytes: [0x03], tone: .modifier)
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
                    systemImage: presentation.isKeyboardUp
                        ? "keyboard.chevron.compact.down" : "keyboard",
                    accessibilityLabel: presentation.isKeyboardUp
                        ? "Hide keyboard" : "Show keyboard",
                    tone: .modifier,
                    action: toggleKeyboard)
                deckButton(
                    systemImage: dictationInput.isActive ? "stop.fill" : "mic.fill",
                    accessibilityLabel: dictationInput.isActive ? "Stop dictation" : "Dictate",
                    tone: dictationInput.isActive ? .recording : .modifier,
                    action: toggleDictation)
                key("↵", accessibilityLabel: "Return", bytes: [0x0D], tone: .accent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color(uiColor: .secondarySystemBackground))
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
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(TerminalDeckKeyButtonStyle(tone: tone))
        .accessibilityLabel(accessibilityLabel)
    }

    private func send(_ data: Data) {
        finishDictation()
        UIDevice.current.playInputClick()
        interactions.sendInput(data)
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
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
    }

    private var moreMenu: some View {
        Menu {
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
            .background(background.opacity(configuration.isPressed ? 0.62 : 1))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(border, lineWidth: 1)
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect)
    }

    private var background: Color {
        switch tone {
        case .standard: Color(uiColor: .tertiarySystemBackground)
        case .modifier: Color(uiColor: .secondarySystemFill)
        case .accent: Color.accentColor
        case .recording: Color.red
        }
    }

    private var foreground: Color {
        switch tone {
        case .accent, .recording: .white
        case .standard, .modifier: .primary
        }
    }

    private var border: Color {
        switch tone {
        case .recording: .red
        case .accent: Color.accentColor.opacity(0.75)
        case .standard, .modifier: Color(uiColor: .separator).opacity(0.65)
        }
    }
}
