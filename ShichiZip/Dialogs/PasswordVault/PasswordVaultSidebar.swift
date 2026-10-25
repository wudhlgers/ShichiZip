import SwiftUI

struct PasswordVaultSidebar: View {
    @ObservedObject var model: PasswordVaultLibraryModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section(SZL10n.string("password.vault.sidebar.library")) {
                row(.all)
                row(.favorites)
                row(.recent)
            }

            Section {
                row(.history)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                Text(SZL10n.string("password.vault.keychainNote"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
    }

    private func row(_ selection: PasswordVaultSidebarSelection) -> some View {
        let count = model.count(for: selection)
        return HStack(spacing: 8) {
            Label(selection.title, systemImage: selection.systemImage)
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .tag(selection)
        .accessibilityIdentifier("passwordVault.sidebar.\(identifier(for: selection))")
    }

    private func identifier(for selection: PasswordVaultSidebarSelection) -> String {
        switch selection {
        case .all: "all"
        case .favorites: "favorites"
        case .recent: "recent"
        case .history: "history"
        }
    }
}
