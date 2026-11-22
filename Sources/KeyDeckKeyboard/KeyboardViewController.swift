import KeyDeckKit
import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardRootView>?
    private var viewModel: KeyboardViewModel?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()

        let vm = KeyboardViewModel(
            hasFullAccess: { [weak self] in self?.hasFullAccess ?? false },
            needsInputModeSwitchKey: { [weak self] in self?.needsInputModeSwitchKey ?? true },
            readContext: { [weak self] in self?.captureTextContext() ?? TextContextSnapshot() },
            insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            deleteBackwardCount: { [weak self] count in
                guard let proxy = self?.textDocumentProxy, count > 0 else { return }
                for _ in 0..<count {
                    proxy.deleteBackward()
                }
            },
            advanceKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            openURL: { [weak self] url in self?.openContainerURL(url) },
            onHeightModeChanged: { [weak self] isExpanded in
                self?.updateKeyboardHeight(expanded: isExpanded)
            }
        )
        self.viewModel = vm

        let rootView = KeyboardRootView(viewModel: vm)
        let host = UIHostingController(rootView: rootView)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        self.hostingController = host

        let constraint = view.heightAnchor.constraint(equalToConstant: 254)
        constraint.priority = .defaultHigh
        constraint.isActive = true
        self.heightConstraint = constraint
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel?.onAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel?.onDisappear()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        viewModel?.refreshContextIndicators()
    }

    private func updateKeyboardHeight(expanded: Bool) {
        let target: CGFloat = expanded ? 344 : 254
        guard heightConstraint?.constant != target else { return }
        heightConstraint?.constant = target
        view.layoutIfNeeded()
    }

    private func captureTextContext() -> TextContextSnapshot {
        let proxy = textDocumentProxy
        // Never capture or forward text from password / secure entry fields
        if proxy.isSecureTextEntry == true {
            return TextContextSnapshot()
        }
        return TextContextSnapshot(
            beforeCursor: proxy.documentContextBeforeInput ?? "",
            afterCursor: proxy.documentContextAfterInput ?? "",
            selectedText: proxy.selectedText ?? ""
        )
    }

    private func openContainerURL(_ url: URL) {
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:")
        let modernSelector = NSSelectorFromString("openURL:options:completionHandler:")

        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return
            }
            if current.responds(to: modernSelector) {
                current.perform(modernSelector, with: url, with: nil)
                return
            }
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }
}
