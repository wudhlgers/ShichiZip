import AppKit
import SwiftUI

@objc(SZPasswordVaultPicker)
@MainActor
final class PasswordVaultPicker: NSObject {
    /// Compact modal used by password prompts. It browses the library scopes
    /// and returns a password; managing the library lives in the separate
    /// window.
    @objc static func runModal() -> String? {
        runModal(forArchivePath: nil)
    }

    /// When `archivePath` is provided the picker leads with the "This Archive"
    /// scope built from the same matching rules as auto-apply.
    @objc static func runModal(forArchivePath archivePath: String?) -> String? {
        let model = PasswordVaultPickerModel(archivePath: archivePath)
        model.scope = model.defaultScope()
        var pickedPassword: String?
        weak var weakDialog: SZModalDialogController?

        let content = NSHostingView(rootView: PasswordVaultPickerView(
            model: model,
            onPick: { password in
                pickedPassword = password
                weakDialog?.finish(withButtonIndex: 1)
            },
            onSelectionChange: { selected in
                weakDialog?.setButtonEnabled(selected, at: 1)
            },
            onOpenLibrary: {
                (NSApp.delegate as? AppDelegate)?.showPasswordLibrary(nil)
            },
        ))

        let dialog = SZModalDialogController(
            style: .informational,
            title: SZL10n.string("password.vault.pickerTitle"),
            message: nil,
            actions: [
                SZDialogAction(title: SZL10n.string("common.cancel"), roles: .cancel),
                SZDialogAction(title: SZL10n.string("password.vault.usePassword"), roles: .default),
            ],
            accessoryView: content,
            preferredFirstResponder: content,
        )
        weakDialog = dialog
        dialog.setButtonEnabled(false, at: 1)
        guard dialog.runModal() == 1 else { return nil }
        return pickedPassword ?? model.selectedItem?.password
    }
}

struct PasswordVaultPickerView: View {
    @ObservedObject var model: PasswordVaultPickerModel
    let onPick: (String) -> Void
    let onSelectionChange: (Bool) -> Void
    let onOpenLibrary: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var revealedItemIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.scope) { _ in
            model.scopeChanged()
            revealedItemIDs.removeAll()
        }
        .onChange(of: model.searchText) { _ in
            model.pruneSelection()
        }
        .onChange(of: model.selectedItemID) { _ in
            onSelectionChange(model.selectedItem != nil)
        }
        .task {
            searchFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            searchField
            sortMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(model.searchPlaceholder, text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit(submitSelection)
                .accessibilityIdentifier("passwordVault.picker.search")
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("passwordVault.picker.clearSearch")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1),
        )
    }

    private var sortMenu: some View {
        Menu {
            Picker(SZL10n.string("password.vault.sort"), selection: $model.sortOrder) {
                ForEach(PasswordVaultSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(SZL10n.string("password.vault.sort"))
        .accessibilityIdentifier("passwordVault.picker.sort")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let message = model.loadErrorMessage {
            PasswordVaultEmptyState(
                systemImage: "exclamationmark.triangle",
                title: SZL10n.string("password.vault.error.title"),
                message: message,
            )
        } else if model.isEmptyLibrary {
            PasswordVaultEmptyState(
                systemImage: "key.fill",
                title: SZL10n.string("password.vault.emptyTitle"),
                message: SZL10n.string("password.vault.picker.emptyMessage"),
                actionTitle: SZL10n.string("password.vault.picker.openLibrary"),
                action: onOpenLibrary,
            )
        } else {
            HStack(spacing: 0) {
                rail
                Divider()
                listArea
            }
        }
    }

    private var rail: some View {
        List(selection: $model.scope) {
            Section(SZL10n.string("password.vault.sidebar.library")) {
                if model.hasArchiveContext {
                    railRow(.matched)
                }
                railRow(.favorites)
                railRow(.recent)
                railRow(.all)
            }

            let tags = model.visibleTags
            if !tags.isEmpty {
                Section(SZL10n.string("password.vault.picker.tags")) {
                    ForEach(tags, id: \.tag) { entry in
                        railRow(.tag(entry.tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(width: 150)
        .accessibilityIdentifier("passwordVault.picker.rail")
    }

    private func railRow(_ scope: PasswordVaultPickerScope) -> some View {
        let count = model.count(for: scope)
        return HStack(spacing: 8) {
            Label(model.title(for: scope), systemImage: model.systemImage(for: scope))
                .lineLimit(1)
            Spacer(minLength: 6)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .tag(scope)
        .accessibilityIdentifier("passwordVault.picker.scope.\(scopeIdentifier(scope))")
    }

    @ViewBuilder
    private var listArea: some View {
        let items = model.visibleItems
        if items.isEmpty {
            emptyListState
        } else {
            List(selection: $model.selectedItemID) {
                ForEach(items) { item in
                    row(item)
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("passwordVault.picker.list")
        }
    }

    private func row(_ item: PasswordVaultItem) -> some View {
        PasswordVaultItemRow(
            item: item,
            subtitle: subtitle(for: item),
            archiveName: archiveName(for: item),
            revealed: revealedItemIDs.contains(item.id),
            onReveal: { toggleReveal(item.id) },
            revealAccessibilityID: "passwordVault.picker.reveal",
        )
        .tag(item.id)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onPick(item.password)
        })
        .accessibilityIdentifier("passwordVault.picker.item.\(item.id.uuidString)")
    }

    private func toggleReveal(_ id: UUID) {
        if revealedItemIDs.contains(id) {
            revealedItemIDs.remove(id)
        } else {
            revealedItemIDs.insert(id)
        }
    }

    private var emptyListState: some View {
        Group {
            if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PasswordVaultEmptyState(
                    systemImage: "magnifyingglass",
                    title: SZL10n.string("password.vault.noResultsTitle"),
                    message: SZL10n.string("password.vault.noResultsMessage"),
                    actionTitle: SZL10n.string("password.vault.clearSearch"),
                    action: { model.searchText = "" },
                )
            } else {
                PasswordVaultEmptyState(
                    systemImage: model.systemImage(for: model.scope),
                    title: model.title(for: model.scope),
                    message: SZL10n.string("password.vault.picker.scopeEmpty"),
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(String(format: SZL10n.string("password.vault.picker.itemsCount"),
                        model.visibleItems.count))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - Helpers

    private func submitSelection() {
        guard let item = model.selectedItem else { return }
        onPick(item.password)
    }

    private func subtitle(for item: PasswordVaultItem) -> String {
        if let lastUsedAt = item.lastUsedAt {
            return SZL10n.string("password.vault.row.lastUsed", relativeDate(lastUsedAt))
        }
        if !item.note.isEmpty {
            return item.note
        }
        return SZL10n.string("password.vault.row.neverUsed")
    }

    private func archiveName(for item: PasswordVaultItem) -> String? {
        var seen: Set<String> = []
        return model.snapshot.usage
            .filter { $0.itemID == item.id }
            .sorted { $0.date > $1.date }
            .compactMap { record in
                guard seen.insert(record.archiveName).inserted else { return nil }
                return record.archiveName
            }
            .first
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func scopeIdentifier(_ scope: PasswordVaultPickerScope) -> String {
        switch scope {
        case .matched: "matched"
        case .favorites: "favorites"
        case .recent: "recent"
        case .all: "all"
        case let .tag(tag): "tag.\(tag)"
        }
    }
}
