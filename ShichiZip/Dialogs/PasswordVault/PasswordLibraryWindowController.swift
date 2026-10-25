import AppKit
import SwiftUI

@MainActor
final class PasswordLibraryWindowController: NSWindowController, NSWindowDelegate {
    var onWindowWillClose: (() -> Void)?

    private let model: PasswordVaultLibraryModel
    private var languageObserver: NSObjectProtocol?

    init(model: PasswordVaultLibraryModel = PasswordVaultLibraryModel()) {
        self.model = model

        let hostingController = NSHostingController(rootView: PasswordLibraryView(model: model))
        hostingController.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hostingController)
        window.title = SZL10n.string("password.vault.windowTitle")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 1040, height: 680))
        window.minSize = NSSize(width: 860, height: 540)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.identifier = NSUserInterfaceItemIdentifier("passwordVault.window")
        window.center()

        super.init(window: window)
        window.delegate = self

        languageObserver = NotificationCenter.default.addObserver(
            forName: .szLanguageDidChange,
            object: nil,
            queue: .main,
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                window?.title = SZL10n.string("password.vault.windowTitle")
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
        }
    }

    override func showWindow(_ sender: Any?) {
        window?.title = SZL10n.string("password.vault.windowTitle")
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_: Notification) {
        onWindowWillClose?()
    }
}
