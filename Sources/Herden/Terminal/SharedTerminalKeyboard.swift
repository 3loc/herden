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

/// One grid, three rows, every row edge to edge. Rows 1 and 3 share the same
/// seven columns so the keys line up vertically; row 2 carries the four
/// labelled actions plus a Return key spanning two of those columns.
///
/// Ordering is deliberate. Escape opens row 1 and Backspace closes it, the way
/// they sit on a physical keyboard, with the four arrows as one contiguous
/// cluster between them. Tab opens row 3 beside the shell characters, and the
/// two set-once controls — dictation language and the system keyboard — close
/// it. Font size is not here: it belongs to the screen's top controls, beside
/// the terminal it resizes.
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
        "Escape", "Left Arrow", "Right Arrow", "Up Arrow", "Down Arrow",
        "Control C", "Backspace",
        "Attach", "Paste", "Dictate text", "Record audio", "Return",
        "Tab", "Slash", "Dollar sign", "Dictation Language", "Keyboard",
    ]

    var body: some View {
        GeometryReader { proxy in
            let layout = TerminalDeckLayout(width: proxy.size.width)
            VStack(spacing: TerminalDeckLayout.spacing) {
                terminalKeyRow(layout)
                actionRow(layout)
                shellRow(layout)
            }
        }
        .frame(height: TerminalDeckLayout.height)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Brand.elevated)
        .accessibilityIdentifier("terminal-control-deck")
    }

    /// Escape, the arrow cluster, Ctrl-C and Backspace: the keys the system
    /// keyboard does not have at all.
    private func terminalKeyRow(_ layout: TerminalDeckLayout) -> some View {
        HStack(spacing: TerminalDeckLayout.spacing) {
            quickKey(.escape, title: "Esc", width: layout.column)
            repeatingKey(.left, width: layout.column)
            repeatingKey(.right, width: layout.column)
            repeatingKey(.up, width: layout.column)
            repeatingKey(.down, width: layout.column)
            quickKey(.controlC, title: "Ctrl-C", width: layout.column)
            repeatingKey(.backspace, width: layout.column)
        }
    }

    private func actionRow(_ layout: TerminalDeckLayout) -> some View {
        HStack(spacing: TerminalDeckLayout.spacing) {
            Menu {
                Button("Documents", systemImage: "doc", action: documents)
                Button("Photos", systemImage: "photo", action: media)
            } label: {
                label("Attach", image: "paperclip", width: layout.actionKey)
            }
            .buttonStyle(TerminalToolbarButtonStyle())
            .disabled(!canUpload)
            .accessibilityIdentifier("terminal-attach")
            Button(action: paste) {
                label("Paste", image: "doc.on.clipboard", width: layout.actionKey)
            }
            .buttonStyle(TerminalToolbarButtonStyle())
            .disabled(!canInput)
            .accessibilityHint("Pastes clipboard text immediately")
            .accessibilityIdentifier("terminal-paste")
            Button(action: toggleDictation) {
                label(isDictating ? "Stop" : "Dictate",
                      image: isDictating ? "stop.fill" : "mic.fill",
                      width: layout.actionKey)
            }
            .buttonStyle(TerminalToolbarButtonStyle(isRecording: isDictating))
            .disabled(!canInput)
            .accessibilityHint("Uses Apple speech recognition on this iPhone")
            .accessibilityIdentifier("terminal-dictate")
            Button(action: recordAudio) {
                label("Audio", image: "waveform", width: layout.actionKey)
            }
            .buttonStyle(TerminalToolbarButtonStyle())
            .disabled(!canUpload)
            .accessibilityHint("Record and review an audio attachment")
            .accessibilityIdentifier("terminal-record-audio")
            quickKey(.enter, systemImage: "return", width: layout.returnKey)
        }
    }

    /// Tab and the two shell characters the iOS keyboard buries, then the
    /// controls that are set once and left alone.
    private func shellRow(_ layout: TerminalDeckLayout) -> some View {
        HStack(spacing: TerminalDeckLayout.spacing) {
            quickKey(.tab, title: "Tab", width: layout.column)
            quickTextKey("/", accessibilityLabel: "Slash", width: layout.column)
            quickTextKey("$", accessibilityLabel: "Dollar sign", width: layout.column)
            Spacer(minLength: 0)
            languageMenu(width: layout.column)
            Button(action: toggleKeyboard) {
                Image(systemName: isKeyboardUp ? "keyboard.chevron.compact.down" : "keyboard")
                    .frame(width: layout.column, height: TerminalDeckLayout.keyHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TerminalToolbarButtonStyle())
            .disabled(!canInput)
            .accessibilityLabel(isKeyboardUp ? "Hide keyboard" : "Show keyboard")
        }
    }

    private func repeatingKey(_ key: AgentQuickKey, width: CGFloat) -> some View {
        TerminalRepeatingArrow(key: key, enabled: canInput) {
            UIDevice.current.playInputClick()
            sendQuickKey(key)
        }
        .frame(width: width, height: TerminalDeckLayout.keyHeight)
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
            .frame(width: width, height: TerminalDeckLayout.keyHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(TerminalToolbarButtonStyle())
        .disabled(!canInput)
        .accessibilityLabel(key.accessibilityLabel)
        .accessibilityHint("Sends this key directly to the Agent")
    }

    private func quickTextKey(
        _ text: String,
        accessibilityLabel: String,
        width: CGFloat
    ) -> some View {
        Button { sendInput(Data(text.utf8)) } label: {
            Text(text)
                .font(Brand.mono(.body, weight: .semibold))
                .frame(width: width, height: TerminalDeckLayout.keyHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(TerminalToolbarButtonStyle())
        .disabled(!canInput)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Inserts this shell character")
    }

    private func label(_ title: String, image: String, width: CGFloat) -> some View {
        Label(title, systemImage: image)
            .font(Brand.sans(.caption, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: width, height: TerminalDeckLayout.keyHeight)
            .contentShape(Rectangle())
    }

    private func languageMenu(width: CGFloat) -> some View {
        Menu {
            Picker("Dictation Language", selection: Binding(
                get: { speech.selectedLocale.identifier },
                set: { finishDictation(); speech.selectLocale(identifier: $0) })
            ) {
                ForEach(speech.supportedLocales, id: \.identifier) { locale in
                    Text(speech.displayName(for: locale)).tag(locale.identifier)
                }
            }
        } label: {
            Image(systemName: "character.bubble")
                .frame(width: width, height: TerminalDeckLayout.keyHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(TerminalToolbarButtonStyle())
        .disabled(speech.supportedLocales.isEmpty)
        .accessibilityLabel("Dictation Language")
        .accessibilityIdentifier("terminal-dictation-language")
    }
}

/// The deck's column geometry, as a pure value so the three rows can be proven
/// to share one grid without hosting SwiftUI. Every row spans the full width:
/// a row of fixed-width keys narrower than the deck reads as a mistake, and
/// that is exactly what the previous hardcoded widths produced.
struct TerminalDeckLayout: Equatable {
    static let spacing: CGFloat = 6
    static let keyHeight: CGFloat = 46
    static let columns = 7
    /// Three key rows plus the two gaps between them.
    static let height: CGFloat = 3 * keyHeight + 2 * spacing

    let width: CGFloat

    /// One column of the seven rows 1 and 3 are laid out on.
    var column: CGFloat {
        guard width > 0 else { return 0 }
        return (width - CGFloat(Self.columns - 1) * Self.spacing) / CGFloat(Self.columns)
    }

    /// Return spans two columns and the gap between them.
    var returnKey: CGFloat { column * 2 + Self.spacing }

    /// The four labelled actions divide whatever Return leaves.
    var actionKey: CGFloat {
        guard width > 0 else { return 0 }
        return (width - 4 * Self.spacing - returnKey) / 4
    }
}

/// A compact instrument for the adjustment people make while reading the live
/// terminal. It sits in the screen's top controls, beside the terminal it
/// resizes rather than down among the typing keys, and reads the same in Agent
/// and Space terminals. The current value confirms the tap without opening
/// Appearance or covering the terminal with a transient message.
struct TerminalFontSizeControls: View {
    let zoom: TerminalZoomSettings

    private enum Layout {
        static let height: CGFloat = 34
        static let buttonWidth: CGFloat = 40
        static let valueWidth: CGFloat = 46
    }

    var body: some View {
        HStack(spacing: 0) {
            sizeButton(
                symbol: "minus",
                label: "Decrease terminal font size",
                delta: -1,
                disabled: zoom.fontSize <= TerminalZoomSettings.range.lowerBound)
            Divider().frame(height: 16)
            Text("\(Int(zoom.fontSize)) pt")
                .font(Brand.mono(.caption, weight: .semibold))
                .foregroundStyle(Brand.muted)
                .monospacedDigit()
                .frame(width: Layout.valueWidth, height: Layout.height)
                .accessibilityHidden(true)
            Divider().frame(height: 16)
            sizeButton(
                symbol: "plus",
                label: "Increase terminal font size",
                delta: 1,
                disabled: zoom.fontSize >= TerminalZoomSettings.range.upperBound)
        }
        .background(Brand.card, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Brand.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func sizeButton(
        symbol: String,
        label: String,
        delta: Float,
        disabled: Bool
    ) -> some View {
        Button { zoom.adjust(by: delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: Layout.buttonWidth, height: Layout.height)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Brand.ink)
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(zoom.fontSize)) points")
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
