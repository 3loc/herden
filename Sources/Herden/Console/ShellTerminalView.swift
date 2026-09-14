import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/// Local Agent Detail destination for one ordinary herden shell terminal.
/// Ghostty owns direct keyboard input, output, scrollback and resize. There is
/// intentionally no Composer, Agent switcher, notification, or Agent
/// operation on this surface.
///
/// Its app-owned keyboard chrome is the exact same direct-input deck used by an
/// Agent terminal. The deck remains visible above the system keyboard and when
/// that keyboard is dismissed.
struct ShellTerminalView: View {
    let store: ShellTerminalStore
    let terminal: TerminalSettings
    let activity: AppActivityCoordinator
    let isReturning: Bool
    var title = "Terminal"
    var backLabel = "Back to Agent"
    /// Nil hides the Close Terminal action entirely (previews, tests).
    var isClosingTerminal: Bool = false
    var onCloseTerminal: (@MainActor () -> Void)? = nil
    var closeActionTitle = "Close Terminal"
    var closeConfirmationTitle = "Close Terminal?"
    var closeConfirmationMessage =
        "This closes the tab on the Host, ending anything running in it. "
        + "Going Back instead leaves it for desktop handoff."
    var stageImage: ImageStager? = nil
    var stageFile: FileStager? = nil
    let onBack: @MainActor () async -> Void

    @State private var keyboardControl = TerminalKeyboardControl()
    @State private var keyboardInset = TerminalKeyboardInset()
    @State private var isConfirmingClose = false
    @State private var staging: ComposerStagingStore?
    @State private var isSelectingFile = false
    @State private var isSelectingPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isOnStage = false
    @Environment(\.colorScheme) private var colorScheme

    private var terminalScreen: TerminalScreenView {
        var screen = TerminalScreenView(feed: store.terminalFeed)
        screen.onSizeChanged = { cols, rows in
            store.viewDidResize(cols: cols, rows: rows)
        }
        screen.onSend = { store.send($0) }
        screen.onNavigateBack = {
            guard !isReturning else { return }
            Task { await onBack() }
        }
        screen.onScroll = { sequence, rows in
            store.scroll(sequence, rows: rows)
        }
        screen.onPaste = { text, bracketed in
            store.requestPaste(text, bracketedPaste: bracketed)
        }
        screen.keyboardControl = keyboardControl
        screen.isLocalInputEnabled = true
        // A Space is a direct-input terminal, so entering it should be ready
        // to type without the extra tap Agent surfaces historically needed.
        // TerminalScreenView performs the claim only after the UIKit surface
        // reaches a window, when becomeFirstResponder can actually succeed.
        screen.claimsKeyboard = { true }
        // Resolve the palette here rather than handing libghostty both slots
        // and trusting it to follow the UIKit trait: it does not re-resolve
        // when the app's appearance override changes, which left the terminal
        // black inside light chrome. A resolved theme also changes identity on
        // a colorScheme change, so `applyTheme` actually reapplies it.
        screen.theme = terminal.themes.resolvedTheme(for: colorScheme)
        screen.fontSize = terminal.zoom.fontSize
        screen.fontFamily = terminal.fonts.familyName
        screen.onFontSizeChanged = { terminal.zoom.setFontSize($0) }
        return screen
    }

    /// The same bottom row an Agent terminal has, in the same order: the
    /// button back to the Console, what this surface is, then its own actions
    /// behind one ellipsis. A Space has no Agent status to report, so the
    /// middle slot carries the terminal's name instead.
    private var terminalStatusRow: some View {
        HStack(spacing: 4) {
            AgentConsoleButton {
                keyboardControl.dismissKeyboard()
                guard !isReturning else { return }
                Task { await onBack() }
            }
            Text(title)
                .font(Brand.sans(.caption, weight: .semibold))
                .foregroundStyle(Brand.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 8)
                .accessibilityIdentifier("terminal-name")
            Spacer(minLength: 8)
            moreMenu
                .frame(width: 38, height: 30)
                .padding(.trailing, 8)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Select and Copy Text", systemImage: "doc.on.doc") {
                keyboardControl.selectText()
            }
            if onCloseTerminal != nil {
                Divider()
                Button(closeActionTitle, systemImage: "trash", role: .destructive) {
                    isConfirmingClose = true
                }
                .disabled(isClosingTerminal || isReturning)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Brand.ink)
        .accessibilityLabel("More")
        .accessibilityIdentifier("terminal-more")
    }

    /// A raised system keyboard gets its measured footprint; the Herden deck
    /// itself is ordinary app content and therefore needs no keyboard mode.
    private var keyboardPresentation: AgentComposerKeyboardPresentation {
        Self.keyboardPresentation(
            insetHeight: keyboardInset.height,
            keyboardIsUp: keyboardControl.isKeyboardUp)
    }

    /// UIKit can briefly publish a zero keyboard inset while Ghostty remains
    /// first responder. Preserve the system-keyboard presentation through
    /// that transient so terminal output does not jump.
    static func keyboardPresentation(
        insetHeight: CGFloat,
        keyboardIsUp: Bool
    ) -> AgentComposerKeyboardPresentation {
        if insetHeight > 0 || keyboardIsUp { return .system }
        return .hidden
    }

    private var keyboardLayout: AgentComposerKeyboardLayout {
        AgentComposerKeyboardLayout(
            currentHeight: keyboardInset.height,
            lastPresentedHeight: keyboardInset.lastPresentedHeight,
            presentation: keyboardPresentation)
    }

    var body: some View {
        terminalScreen
            .id(store.terminalID)
            .overlay { statusOverlay }
            .safeAreaInset(edge: .top, spacing: 0) {
                TerminalTopControls(
                    zoom: terminal.zoom,
                    backLabel: backLabel,
                    onBack: { guard !isReturning else { return }; Task { await onBack() } })
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    terminalStatusRow
                    if let staging, let presentation = staging.presentation {
                        AttachmentStatusBar(
                            icon: presentation.icon,
                            title: presentation.title,
                            accessibilityLabel: presentation.accessibilityLabel
                        ) {
                            ForEach(presentation.commands, id: \.self) { command in
                                Button(commandTitle(command)) { staging.perform(command) }
                            }
                        }
                    }
                    TerminalKeyboard(
                        keyboardControl: keyboardControl,
                        isKeyboardUp: keyboardControl.isKeyboardUp,
                        canUpload: staging?.canBegin == true,
                        documents: { isSelectingFile = true },
                        media: { isSelectingPhoto = true },
                        recordAudio: { beginAttachment(.recording($0)) },
                        toggleSystemKeyboard: { keyboardControl.toggleKeyboard() },
                        dismissSystemKeyboard: { keyboardControl.dismissKeyboard() },
                        sendQuickKey: { keyboardControl.sendQuickKey($0) },
                        sendInput: { keyboardControl.sendInput($0) })
                }
                .padding(.vertical, 8)
                .background(Brand.elevated)
            }
            .padding(.bottom, keyboardLayout.contentInset)
            // Keyboard avoidance is owned by `TerminalKeyboardInset`; UIKit's
            // keyboard safe area would resize Ghostty a second time.
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .background(
                terminal.themes.selection(for: colorScheme)
                    .surfaceBackground(for: colorScheme)
            )
            .toolbarColorScheme(
                terminal.themes.selection(for: colorScheme)
                    .chromeColorScheme(for: colorScheme),
                for: .navigationBar
            )
            .navigationBarBackButtonHidden(true)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog(
                closeConfirmationTitle,
                isPresented: $isConfirmingClose,
                titleVisibility: .visible
            ) {
                Button(closeActionTitle, role: .destructive) {
                    onCloseTerminal?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(closeConfirmationMessage)
            }
            .sheet(
                isPresented: Binding(
                    get: { store.pendingPaste != nil },
                    set: { if !$0 { store.cancelPaste() } })
            ) {
                pasteReviewSheet
            }
            .alert(
                "Paste Blocked",
                isPresented: Binding(
                    get: { store.pasteErrorMessage != nil },
                    set: { if !$0 { store.clearPasteError() } })
            ) {
                Button("OK", role: .cancel) { store.clearPasteError() }
            } message: {
                Text(store.pasteErrorMessage ?? "")
            }
            .onChange(of: activity.activationCount, initial: true) { _, _ in
                store.didBecomeActive(
                    afterPossibleSuspension: activity.lastAbsenceMayHaveSuspended)
            }
            .onAppear {
                isOnStage = true
                if staging == nil, let stageImage, let stageFile {
                    staging = ComposerStagingStore(stageImage: stageImage, stageFile: stageFile)
                }
                store.rejoin()
            }
            .onDisappear {
                isOnStage = false
                if let staging { Task { await staging.leave() } }
                store.leave()
            }
            .photosPicker(isPresented: $isSelectingPhoto, selection: $selectedPhoto, matching: .images)
            .fileImporter(isPresented: $isSelectingFile, allowedContentTypes: [.data]) { result in
                guard case .success(let url) = result else { return }
                beginAttachment(.file(url))
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                selectedPhoto = nil
                beginAttachment(.photo(PhotosPickerImageSelection(item: item)))
            }
            .onChange(of: activity.phase) { _, phase in
                if phase == .suspended { staging?.didEnterBackground() }
            }
    }

    @discardableResult
    private func beginAttachment(_ source: ComposerStagingStore.Source) -> Bool {
        let generation = store.input.liveGeneration
        return staging?.begin(source, insertText: { [weak store, weak keyboardControl] path in
            guard isOnStage, let store, let generation,
                store.input.liveGeneration == generation,
                let keyboardControl, keyboardControl.terminal != nil
            else { return false }
            keyboardControl.paste(path)
            return true
        }) ?? false
    }

    private func commandTitle(_ command: ComposerStagingStore.Command) -> String {
        switch command {
        case .cancel: "Cancel"
        case .retry: "Retry"
        case .copyPath: "Copy Path"
        case .dismiss: "Dismiss"
        }
    }

    private var themePalette: TerminalThemePalette {
        terminal.themes.selection(for: colorScheme).palette(for: colorScheme)
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if let presentation = TerminalStatusPresentation(status: store.terminalStatus) {
            switch presentation.kind {
            case .connecting:
                // Nothing. Connecting is the ordinary way into a terminal, not
                // a condition worth a modal over the screen you just opened —
                // and an Agent reattaches fast enough that the dialog only ever
                // read as a flash. A failure still gets its dialog below.
                EmptyView()
            case .ended:
                TerminalStatusDialog(
                    glyph: .symbol("cable.connector.slash"),
                    title: presentation.title,
                    message: presentation.message,
                    palette: themePalette,
                    dimsBackground: presentation.dimsBackground
                ) {
                    Button("Reattach") { store.retryTerminal() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var pasteReviewSheet: some View {
        if let review = store.pendingPaste {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(review.lineCount) lines, \(review.characterCount) characters")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(review.preview)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(.quaternary, in: .rect(cornerRadius: 10))
                }
                .padding()
                .navigationTitle("Review Paste")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { store.cancelPaste() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Paste") { store.confirmPaste() }
                            .disabled(!store.canConfirmPaste)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}
