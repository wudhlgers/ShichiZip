import AppKit
import SwiftUI

struct PasswordLibraryView: View {
    @ObservedObject var model: PasswordVaultLibraryModel

    var body: some View {
        NavigationSplitView {
            PasswordVaultSidebar(model: model)
        } content: {
            PasswordVaultListPane(model: model)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
        } detail: {
            PasswordVaultDetailPane(model: model)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.beginAdding()
                } label: {
                    Label(SZL10n.string("password.vault.add"), systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help(SZL10n.string("password.vault.add"))
                .accessibilityIdentifier("passwordVault.add")
            }
        }
        .sheet(item: $model.editor) { context in
            PasswordVaultEditorView(model: model, context: context)
        }
        .alert(item: $model.alert) { alert in
            switch alert {
            case let .error(message):
                Alert(
                    title: Text(SZL10n.string("password.vault.error.title")),
                    message: Text(message),
                    dismissButton: .default(Text(SZL10n.string("common.ok"))),
                )
            case let .delete(request):
                Alert(
                    title: Text(SZL10n.string("password.vault.delete.title")),
                    message: Text(request.message),
                    primaryButton: .destructive(Text(SZL10n.string("password.vault.delete"))) {
                        model.confirmDelete()
                    },
                    secondaryButton: .cancel(Text(SZL10n.string("common.cancel"))),
                )
            }
        }
        .confirmationDialog(
            SZL10n.string("password.vault.clearHistory.title"),
            isPresented: $model.showsClearHistoryConfirmation,
            titleVisibility: .visible,
        ) {
            Button(SZL10n.string("password.vault.clearHistory"), role: .destructive) {
                model.clearHistory()
            }
            Button(SZL10n.string("common.cancel"), role: .cancel) {}
        } message: {
            Text(SZL10n.string("password.vault.clearHistory.message"))
        }
        .onChange(of: model.sidebarSelection) { _ in
            model.sidebarSelectionChanged()
        }
        .onChange(of: model.searchText) { _ in
            model.pruneSelection()
        }
        .frame(minWidth: 860, minHeight: 540)
    }
}

struct PasswordVaultEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
