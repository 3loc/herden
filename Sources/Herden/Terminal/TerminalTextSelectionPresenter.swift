import GhosttyTerminal
import UIKit

@MainActor
enum TerminalTextSelectionPresenter {
    static func present(_ request: TerminalTextSelectionRequest, from sourceView: UIView) {
        let captured = (sourceView as? UITerminalView).flatMap(readAllSelectableText)
        let text = captured ?? request.text
        let anchorRange = captured.map {
            selectionAnchor(
                in: $0, viewportText: request.text, viewportAnchor: request.anchorRange)
        } ?? request.anchorRange
        present(
            text: text, anchorRange: anchorRange,
            includesScrollback: captured != nil, from: sourceView)
    }

    static func present(
        text: String, anchorRange: NSRange? = nil,
        includesScrollback: Bool = false, from sourceView: UIView
    ) {
        guard let presentingViewController = sourceView.nearestPresentingViewController else {
            return
        }

        let selection = TerminalTextSelectionViewController(
            text: text,
            anchorRange: anchorRange,
            includesScrollback: includesScrollback)
        let navigation = UINavigationController(rootViewController: selection)
        navigation.modalPresentationStyle = .pageSheet
        navigation.sheetPresentationController?.detents = [.large()]
        presentingViewController.present(navigation, animated: true)
    }

    /// Ghostty's native selection covers the primary screen's scrollback and
    /// the complete active alternate screen. The wrapper's viewport snapshot
    /// omits shell history and can be shorter than the drawn grid. The pinned
    /// wrapper exposes native selection through binding actions. Herden sets
    /// `selection-clear-on-copy` on its terminal surfaces, so Ghostty clears
    /// the highlight after the snapshot. Preserve every pasteboard item until
    /// the user explicitly chooses Copy in the selection window.
    static func readAllSelectableText(_ terminal: UITerminalView) -> String? {
        let previousItems = UIPasteboard.general.items
        defer { UIPasteboard.general.items = previousItems }
        guard terminal.performBindingAction("select_all"),
              terminal.performBindingAction("copy_to_clipboard")
        else { return nil }
        let text = UIPasteboard.general.string
        return text?.isEmpty == false ? text : nil
    }

    static func selectionAnchor(
        in text: String, viewportText: String, viewportAnchor: NSRange?
    ) -> NSRange {
        let full = text as NSString
        let viewport = viewportText as NSString
        guard let viewportAnchor,
              viewportAnchor.location >= 0,
              viewportAnchor.length > 0,
              viewportAnchor.location <= viewport.length,
              viewportAnchor.length <= viewport.length - viewportAnchor.location
        else { return NSRange(location: full.length, length: 0) }
        let viewportRange = full.range(of: viewportText, options: .backwards)
        if viewportRange.location != NSNotFound {
            return NSRange(
                location: viewportRange.location + viewportAnchor.location,
                length: viewportAnchor.length)
        }
        let word = viewport.substring(with: viewportAnchor)
        let wordRange = full.range(of: word, options: .backwards)
        return wordRange.location == NSNotFound
            ? NSRange(location: full.length, length: 0) : wordRange
    }
}

@MainActor
final class TerminalCopyTextView: UITextView {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) { return false }
        return super.canPerformAction(action, withSender: sender)
    }

    @IBAction override func copy(_ sender: Any?) {}
}

@MainActor
final class TerminalTextSelectionViewController: UIViewController, UITextViewDelegate {
    private let text: String
    private let anchorRange: NSRange?
    private let includesScrollback: Bool
    private let textView = TerminalCopyTextView()
    private let scopeLabel = UILabel()
    private let writeClipboard: (String) -> Void

    init(
        text: String,
        anchorRange: NSRange?,
        includesScrollback: Bool = false,
        writeClipboard: @escaping (String) -> Void = { UIPasteboard.general.string = $0 }
    ) {
        self.text = text
        self.anchorRange = anchorRange
        self.includesScrollback = includesScrollback
        self.writeClipboard = writeClipboard
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Terminal Text"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Copy All", style: .plain, target: self, action: #selector(copyText))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissSelection))

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.delegate = self
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.text = text
        textView.accessibilityIdentifier = "terminal.text-selection"
        view.addSubview(textView)

        scopeLabel.translatesAutoresizingMaskIntoConstraints = false
        scopeLabel.font = .preferredFont(forTextStyle: .footnote)
        scopeLabel.textColor = .secondaryLabel
        scopeLabel.numberOfLines = 0
        scopeLabel.textAlignment = .center
        let lineCount = text.isEmpty ? 0 : text.split(
            separator: "\n", omittingEmptySubsequences: false).count
        scopeLabel.text = includesScrollback
            ? "Captured \(lineCount) lines. Select a passage to copy it. "
                + "For older Agent history, scroll the Agent first."
            : "Current screen only. Select a passage to copy it. "
                + "Scroll the terminal first for older lines."
        view.addSubview(scopeLabel)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: scopeLabel.topAnchor, constant: -8),
            scopeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            scopeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            scopeLabel.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        let textLength = (text as NSString).length
        let normalizedAnchor = Self.normalizedSelectionRange(
            anchorRange, textLength: textLength)
        textView.selectedRange = NSRange(
            location: anchorRange == nil ? textLength : normalizedAnchor.location,
            length: 0)
        textViewDidChangeSelection(textView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.scrollRangeToVisible(textView.selectedRange)
    }

    static func normalizedSelectionRange(_ range: NSRange?, textLength: Int) -> NSRange {
        guard let range,
            range.location >= 0,
            range.length >= 0,
            range.location <= textLength,
            range.length <= textLength - range.location
        else {
            return NSRange(location: 0, length: textLength)
        }
        return range
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        let button = navigationItem.leftBarButtonItem
        button?.isEnabled = !textView.text.isEmpty
        button?.title = textView.selectedRange.length > 0
            ? "Copy Selection" : "Copy All"
    }

    func textView(
        _ textView: UITextView, editMenuForTextIn range: NSRange,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        UIMenu(children: [])
    }

    @available(iOS 26.0, *)
    func textView(
        _ textView: UITextView, editMenuForTextInRanges ranges: [NSValue],
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        UIMenu(children: [])
    }

    @objc func copyText() {
        guard let content = textView.text, !content.isEmpty else { return }
        let range = textView.selectedRange
        let copied = range.length > 0
            ? (content as NSString).substring(with: range)
            : content
        writeClipboard(copied)
        dismiss(animated: true)
    }

    @objc private func dismissSelection() {
        dismiss(animated: true)
    }
}

extension UIView {
    fileprivate var nearestPresentingViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController.topmostPresentedViewController
            }
            responder = current.next
        }
        return window?.rootViewController?.topmostPresentedViewController
    }
}

extension UIViewController {
    fileprivate var topmostPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topmostPresentedViewController
        }
        if let navigation = self as? UINavigationController,
            let visible = navigation.visibleViewController
        {
            return visible.topmostPresentedViewController
        }
        if let tab = self as? UITabBarController,
            let selected = tab.selectedViewController
        {
            return selected.topmostPresentedViewController
        }
        return self
    }
}
