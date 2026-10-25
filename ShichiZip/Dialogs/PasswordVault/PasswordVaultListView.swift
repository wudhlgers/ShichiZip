import AppKit
import SwiftUI

struct PasswordVaultListPane: View {
    @ObservedObject var model: PasswordVaultLibraryModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(model.sidebarSelection?.title ?? SZL10n.string("password.vault.sidebar.all"))
                    .font(.headline)
                Spacer(minLength: 8)
                if model.sidebarSelection == .history, !model.allUsage.isEmpty {
                    Button {
                        model.showsClearHistoryConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(SZL10n.string("password.vault.clearHistory"))
                    .accessibilityIdentifier("passwordVault.clearHistory")
                }
                sortMenu
            }

            searchField
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
        .accessibilityIdentifier("passwordVault.sort")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(SZL10n.string("password.vault.searchPlaceholder"), text: $model.searchText)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("passwordVault.search")
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("passwordVault.clearSearch")
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

    @ViewBuilder
    private var content: some View {
        if model.sidebarSelection == .history {
            historyContent
        } else {
            itemContent
        }
    }

    @ViewBuilder
    private var itemContent: some View {
        if model.visibleItems.isEmpty {
            emptyState
        } else {
            List(selection: $model.selectedItemIDs) {
                ForEach(model.visibleItems) { item in
                    PasswordVaultItemRow(
                        item: item,
                        subtitle: subtitle(for: item),
                        archiveName: model.archiveNames(for: item.id).first,
                    )
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        model.beginEditing(item)
                    })
                    .contextMenu {
                        Button(SZL10n.string("password.vault.copyPassword")) {
                            model.copyPassword(item)
                        }
                        Button(SZL10n.string("password.vault.edit")) {
                            model.beginEditing(item)
                        }
                        Button(item.isFavorite
                            ? SZL10n.string("password.vault.removeFavorite")
                            : SZL10n.string("password.vault.addFavorite"))
                        {
                            model.toggleFavorite(item)
                        }
                        Divider()
                        Button(SZL10n.string("password.vault.delete"), role: .destructive) {
                            let targets = model.selectedItemIDs.contains(item.id)
                                ? model.allItems.filter { model.selectedItemIDs.contains($0.id) }
                                : [item]
                            model.requestDelete(targets)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("passwordVault.itemList")
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if model.visibleUsage.isEmpty {
            PasswordVaultEmptyState(
                systemImage: "list.bullet.rectangle",
                title: SZL10n.string("password.vault.history.emptyTitle"),
                message: SZL10n.string("password.vault.history.emptyMessage"),
            )
        } else {
            List(selection: $model.selectedUsageID) {
                ForEach(historyGroups, id: \.day) { group in
                    Section {
                        ForEach(group.records) { record in
                            PasswordVaultHistoryRow(
                                record: record,
                                item: model.item(withID: record.itemID),
                            )
                            .tag(record.id)
                        }
                    } header: {
                        Text(group.day, format: .dateTime.weekday(.wide).month().day())
                    }
                }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("passwordVault.historyList")
        }
    }

    private var emptyState: some View {
        Group {
            if !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PasswordVaultEmptyState(
                    systemImage: "magnifyingglass",
                    title: SZL10n.string("password.vault.noResultsTitle"),
                    message: SZL10n.string("password.vault.noResultsMessage"),
                    actionTitle: SZL10n.string("password.vault.clearSearch"),
                    action: { model.searchText = "" },
                )
            } else if model.allItems.isEmpty {
                PasswordVaultEmptyState(
                    systemImage: "key.fill",
                    title: SZL10n.string("password.vault.emptyTitle"),
                    message: SZL10n.string("password.vault.emptyMessage"),
                    actionTitle: SZL10n.string("password.vault.add"),
                    action: { model.beginAdding() },
                )
            } else if model.sidebarSelection == .favorites {
                PasswordVaultEmptyState(
                    systemImage: "star",
                    title: SZL10n.string("password.vault.favorites.emptyTitle"),
                    message: SZL10n.string("password.vault.favorites.emptyMessage"),
                )
            } else if model.sidebarSelection == .recent {
                PasswordVaultEmptyState(
                    systemImage: "clock.arrow.circlepath",
                    title: SZL10n.string("password.vault.recent.emptyTitle"),
                    message: SZL10n.string("password.vault.recent.emptyMessage"),
                )
            } else {
                PasswordVaultEmptyState(
                    systemImage: model.sidebarSelection?.systemImage ?? "key.fill",
                    title: SZL10n.string("password.vault.emptyTitle"),
                    message: SZL10n.string("password.vault.emptyMessage"),
                )
            }
        }
    }

    private var historyGroups: [(day: Date, records: [PasswordVaultUsage])] {
        let grouped = Dictionary(grouping: model.visibleUsage) {
            Calendar.current.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day, default: []].sorted { $0.date > $1.date })
        }
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

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PasswordVaultItemRow: View {
    let item: PasswordVaultItem
    let subtitle: String
    let archiveName: String?
    /// Picker rows get an inline reveal toggle; library rows keep the masked
    /// dots and reveal only in the detail pane.
    var revealed = false
    var onReveal: (() -> Void)? = nil
    var revealAccessibilityID: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.resolvedIconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10)),
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                }
                HStack(spacing: 5) {
                    Text(subtitle)
                        .lineLimit(1)
                    if let archiveName {
                        Text("·")
                        Text(archiveName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(revealed ? item.password : item.maskedPassword)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(revealed ? .primary : .tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let onReveal {
                Button {
                    onReveal()
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help(SZL10n.string(revealed
                    ? "password.vault.hidePassword"
                    : "password.vault.showPassword"))
                .accessibilityIdentifier(revealAccessibilityID ?? "")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("passwordVault.item.\(item.id.uuidString)")
    }
}

private struct PasswordVaultHistoryRow: View {
    let record: PasswordVaultUsage
    let item: PasswordVaultItem?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item?.resolvedIconName ?? "key.fill")
                .font(.system(size: 15))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item?.title ?? SZL10n.string("password.vault.untitled"))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(record.archiveName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(record.date, format: .dateTime.hour().minute())
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("passwordVault.history.\(record.id.uuidString)")
    }
}
