import AppKit

/// Owns the password clipboard lifecycle. A copied password is cleared after
/// a short delay, but only when the pasteboard still contains what this app
/// wrote — copying something else in the meantime must never be clobbered.
@MainActor
final class PasswordVaultClipboard {
    static let shared = PasswordVaultClipboard()

    static let defaultClearDelay: TimeInterval = 30

    private let pasteboard: NSPasteboard
    private let defaultClearDelay: TimeInterval
    private var clearTask: Task<Void, Never>?
    private var ownedChangeCount: Int?

    init(pasteboard: NSPasteboard = .general,
         clearDelay: TimeInterval = PasswordVaultClipboard.defaultClearDelay)
    {
        self.pasteboard = pasteboard
        defaultClearDelay = clearDelay
    }

    func copy(_ password: String, clearAfter delay: TimeInterval? = nil) {
        clearTask?.cancel()
        clearTask = nil

        pasteboard.clearContents()
        pasteboard.setString(password, forType: .string)
        ownedChangeCount = pasteboard.changeCount

        let delay = max(0, delay ?? defaultClearDelay)
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.clearIfOwned()
        }
    }

    /// Clears the pasteboard only if it still holds this app's copied password.
    func clearIfOwned() {
        clearTask?.cancel()
        clearTask = nil

        guard let ownedChangeCount else { return }
        self.ownedChangeCount = nil

        guard pasteboard.changeCount == ownedChangeCount else { return }
        pasteboard.clearContents()
    }
}
