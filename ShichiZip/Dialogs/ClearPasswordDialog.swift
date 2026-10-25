import SwiftUI

@MainActor
final class ClearPasswordDialog: NSObject {
    enum Outcome {
        /// Replace the original archive file with the password-free rebuild.
        case replaceInPlace
        /// Write the password-free rebuild to a new file chosen afterwards.
        case saveAsNew
    }

    /// Returns nil when cancelled.
    static func run(forArchive archiveURL: URL, parentWindow: NSWindow?) async -> Outcome? {
        let model = Model()
        let content = NSHostingView(rootView: Content(model: model,
                                                      fileName: archiveURL.lastPathComponent))
        let dialog = SZModalDialogController(
            style: .informational,
            title: SZL10n.string("app.archive.clearPassword.title"),
            message: nil,
            actions: [
                SZDialogAction(title: SZL10n.string("common.cancel"), roles: .cancel),
                SZDialogAction(title: SZL10n.string("common.ok"), roles: .default),
            ],
            accessoryView: content,
            preferredFirstResponder: nil,
        )
        var result: Outcome?
        dialog.shouldFinishHandler = { buttonIndex in
            guard buttonIndex == 1 else { return true }
            result = model.saveAsNew ? .saveAsNew : .replaceInPlace
            return true
        }
        defer { dialog.shouldFinishHandler = nil }

        if let parentWindow {
            let buttonIndex = await withCheckedContinuation { continuation in
                dialog.beginSheetModal(for: parentWindow) { index in
                    continuation.resume(returning: index)
                }
            }
            return buttonIndex == 1 ? result : nil
        }
        return dialog.runModal() == 1 ? result : nil
    }

    private final class Model: ObservableObject {
        @Published var saveAsNew = false
    }

    private struct Content: View {
        @ObservedObject var model: Model

        let fileName: String

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(SZL10n.string("app.archive.clearPassword.confirm", fileName))
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(SZL10n.string("app.archive.clearPassword.saveAsNew"), isOn: $model.saveAsNew)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("clearPassword.saveAsNew")
            }
            .frame(width: 380)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
