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

    private var presentation: AgentDirectInputChromeContext.Presentation {
        context.presentation
    }

    private var interactions: AgentDirectInputChromeContext.Interactions {
        context.interactions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                AgentConsoleButton {
                    interactions.dismissKeyboard()
                    interactions.showConsole()
                }
                AgentDetailStatusChrome(
                    status: presentation.status,
                    hostTelemetry: presentation.hostTelemetry,
                    chromeColorScheme: presentation.chromeColorScheme)
                moreMenu
                    .frame(width: 38, height: 30)
                    .padding(.trailing, 8)
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
    }

    private var terminalControlDeck: some View {
        TerminalKeyboard(
            keyboardControl: interactions.keyboardControl,
            isKeyboardUp: presentation.isKeyboardUp,
            canUpload: interactions.actions.canBegin,
            documents: interactions.actions.addFile,
            media: interactions.actions.addImage,
            toggleSystemKeyboard: interactions.toggleKeyboard,
            dismissSystemKeyboard: interactions.dismissKeyboard,
            sendQuickKey: interactions.sendQuickKey,
            sendInput: interactions.sendInput)
    }

    private var moreMenu: some View {
        Menu {
            Button("Select and Copy Text", systemImage: "doc.on.doc") {
                interactions.keyboardControl?.selectText()
            }
            .disabled(interactions.keyboardControl?.terminal == nil)
            Divider()
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

struct AgentConsoleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                HerdenMark(size: 18)
                Text("Agents")
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
        .accessibilityLabel("Back to Agents")
    }
}
