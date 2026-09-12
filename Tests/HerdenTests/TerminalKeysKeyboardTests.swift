import Foundation
import Testing
import UIKit

@testable import Herden

@MainActor
@Suite("Keys keyboard")
struct TerminalKeysKeyboardTests {
    @Test func spacesAndAgentsUseTheSameStandardIOSKeyboardProfile() {
        let composer = AgentComposerUITextView()
        let terminal = TerminalScreenView.makeConfiguredTerminal(
            notificationCenter: NotificationCenter())

        let inputs: [any UITextInputTraits] = [composer, terminal]
        for input in inputs {
            #expect(input.keyboardType == .default)
            #expect(input.autocapitalizationType == UITextAutocapitalizationType.none)
            #expect(input.autocorrectionType == .no)
            #expect(input.spellCheckingType == .no)
            #expect(input.smartDashesType == .no)
            #expect(input.smartQuotesType == .no)
            #expect(input.smartInsertDeleteType == .no)
            #expect(input.inlinePredictionType == .no)
        }
    }

    @Test func composerSuppressesTheSystemKeyboardBehindTheToolsDock() throws {
        let textView = AgentComposerUITextView()

        textView.updateKeyboard(presentation: .system)
        #expect(textView.inputView == nil)
        // UIKit owns its candidate and paste area. Adding an accessory here
        // changes the keyboard stack's frame during an in-place replacement.
        #expect(textView.inputAccessoryView == nil)

        textView.updateKeyboard(presentation: .tools)
        let suppressedSystemKeyboard = try #require(
            textView.inputView as? TerminalSuppressedSoftKeyboardView)
        #expect(suppressedSystemKeyboard.intrinsicContentSize.height == 0)
        #expect(textView.inputAccessoryView == nil)

        textView.updateKeyboard(presentation: .system)
        #expect(textView.inputView == nil)
        #expect(textView.inputAccessoryView == nil)

        textView.updateKeyboard(presentation: .tools)
        #expect(textView.inputView === suppressedSystemKeyboard)
    }

    /// The terminal makes the same move the Composer does: Keys mode only
    /// suppresses the software keyboard, and nothing rides the keyboard in
    /// either mode. A real input view here is the regression this replaces —
    /// swapping one tears down the IME's candidate row for good.
    @Test func keysModeSuppressesTheSystemKeyboardInPlace() throws {
        let terminal = TerminalScreenView.makeConfiguredTerminal(
            notificationCenter: NotificationCenter())
        #expect(terminal.keyboardMode == .text)
        #expect(terminal.inputView == nil)
        #expect(terminal.inputAccessoryView == nil)

        terminal.setKeyboardMode(.controls)
        let suppressed = try #require(
            terminal.inputView as? TerminalSuppressedSoftKeyboardView)
        #expect(suppressed.intrinsicContentSize.height == 0)
        #expect(terminal.inputAccessoryView == nil)
        #expect(terminal.keyboardMode == .controls)

        terminal.setKeyboardMode(.text)
        #expect(terminal.inputView == nil)
        #expect(terminal.keyboardMode == .text)
    }

    @Test func controlPadKeysFireTheClosureWhenTheFingerLifts() throws {
        var sent: [TerminalControlKey] = []
        let pad = TerminalControlPadView { sent.append($0) }
        let escape = try #require(Self.button(labelled: "Escape", in: pad))

        // A key fires on release, not on touch down: the pad's ancestor may
        // claim the gesture, and a swipe that starts on a key must not also
        // send an Esc down the wire.
        escape.sendActions(for: .touchDown)
        #expect(sent.isEmpty)
        escape.sendActions(for: .touchUpInside)
        #expect(sent == [.escape])

        escape.sendActions(for: .touchDown)
        escape.sendActions(for: .touchDragExit)
        #expect(sent == [.escape])
    }

    @Test func controlPadCoversEveryControlKey() {
        let pad = TerminalControlPadView { _ in }
        let labels = Set(Self.buttons(in: pad).compactMap(\.accessibilityLabel))

        #expect(labels == Set(TerminalControlKey.allCases.map(\.accessibilityLabel)))
    }

    /// Skills sits right beside the control keys when the agent has a skills
    /// source; without one the tab does not exist at all.
    @Test func skillsTabAppearsOnlyWithASkillsContext() throws {
        let suiteName = "hm-keys-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = TerminalSettings(
            themes: TerminalThemeSettings(defaults: defaults),
            zoom: TerminalZoomSettings(defaults: defaults),
            fonts: TerminalFontSettings(defaults: defaults),
            snippets: SnippetStore(defaults: defaults))

        let plain = TerminalKeysContext(settings: settings, manageSnippets: {})
        #expect(plain.tabs == [.controls, .snippets, .appearance])

        let withSkills = TerminalKeysContext(
            settings: settings,
            skills: TerminalSkillsContext(store: SkillsPaneStore { _ in [] }),
            manageSnippets: {})
        #expect(withSkills.tabs == [.controls, .skills, .snippets, .appearance])
    }

    /// UIKit can briefly zero the measured inset while Ghostty remains first
    /// responder. The shared deck stays mounted, and the terminal must retain
    /// its system-keyboard layout through that frame.
    @Test func aTransientZeroInsetKeepsTheSystemKeyboardLayout() {
        #expect(
            ShellTerminalView.keyboardPresentation(
                insetHeight: 0, keyboardIsUp: true) == .system)

        #expect(
            ShellTerminalView.keyboardPresentation(
                insetHeight: 336, keyboardIsUp: true) == .system)
        // A real dismissal resigns first responder before its will-hide.
        #expect(
            ShellTerminalView.keyboardPresentation(
                insetHeight: 0, keyboardIsUp: false) == .hidden)
    }

    @Test func agentAndSpaceTerminalsShareTheFullControlDeck() {
        #expect(Set(TerminalDirectInputDeck.controlNames) == Set([
            "Escape", "Left Arrow", "Right Arrow", "Up Arrow", "Down Arrow",
            "Control C", "Backspace",
            "Attach", "Paste", "Dictate text", "Record audio", "Return",
            "Tab", "Slash", "Dollar sign", "Dictation Language", "Keyboard",
        ]))
    }

    /// Every key reachable without opening a menu. The deck has no overflow:
    /// the keys it does not show are not hidden behind an ellipsis, they are
    /// gone. Ctrl-B and the Vim insert shortcut went with it.
    @Test func theDeckHasNoOverflowMenu() {
        #expect(!TerminalDirectInputDeck.controlNames.contains("More"))
        #expect(!TerminalDirectInputDeck.controlNames.contains("Ctrl-B"))
        #expect(!TerminalDirectInputDeck.controlNames.contains("Insert text"))
    }

    /// The three rows share one grid and each spans the deck exactly. Fixed
    /// widths that summed to less than the deck were what made the previous
    /// keyboard read as misaligned.
    @Test func everyDeckRowSpansTheFullWidth() {
        for width in [320.0, 375.0, 414.0, 430.0] as [CGFloat] {
            let layout = TerminalDeckLayout(width: width)
            let spacing = TerminalDeckLayout.spacing

            let terminalKeyRow = layout.column * 7 + spacing * 6
            #expect(abs(terminalKeyRow - width) < 0.001, "row 1 at \(width)")

            let actionRow = layout.actionKey * 4 + layout.returnKey + spacing * 4
            #expect(abs(actionRow - width) < 0.001, "row 2 at \(width)")

            // Return spans two of row 1's columns, so it lines up with them.
            #expect(layout.returnKey == layout.column * 2 + spacing)
            #expect(layout.actionKey > layout.column)
        }
    }

    /// A deck asked to lay out before it has a width must not produce negative
    /// key widths, which SwiftUI reports as a constraint failure.
    @Test func aZeroWidthDeckProducesNoNegativeKeys() {
        let layout = TerminalDeckLayout(width: 0)
        #expect(layout.column == 0)
        #expect(layout.actionKey == 0)
    }

    @Test func everyTabHasItsOwnIconAndLabel() {
        let icons = Set(TerminalKeysTab.allCases.map(\.systemImageName))
        let labels = Set(TerminalKeysTab.allCases.map(\.accessibilityLabel))

        #expect(icons.count == TerminalKeysTab.allCases.count)
        #expect(labels.count == TerminalKeysTab.allCases.count)
        for icon in icons {
            #expect(UIImage(systemName: icon) != nil, "missing SF Symbol \(icon)")
        }
    }

    private static func buttons(in view: UIView) -> [UIButton] {
        view.subviews.flatMap { subview -> [UIButton] in
            if let button = subview as? UIButton { return [button] }
            return buttons(in: subview)
        }
    }

    private static func button(labelled label: String, in view: UIView) -> UIButton? {
        buttons(in: view).first { $0.accessibilityLabel == label }
    }
}
