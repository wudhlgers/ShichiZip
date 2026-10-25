import Foundation
import SwiftUI

enum PasswordVaultSidebarSelection: Hashable {
    case all
    case favorites
    case recent
    case history

    var title: String {
        switch self {
        case .all: SZL10n.string("password.vault.sidebar.all")
        case .favorites: SZL10n.string("password.vault.sidebar.favorites")
        case .recent: SZL10n.string("password.vault.sidebar.recent")
        case .history: SZL10n.string("password.vault.sidebar.history")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "key.fill"
        case .favorites: "star.fill"
        case .recent: "clock.arrow.circlepath"
        case .history: "list.bullet.rectangle"
        }
    }
}

struct PasswordVaultEditorContext: Identifiable {
    let id = UUID()
    let itemID: UUID?
    var draft: PasswordVaultItemDraft
}

struct PasswordVaultDeleteRequest: Identifiable {
    let id = UUID()
    let itemIDs: Set<UUID>
    let message: String
}

enum PasswordVaultAlert: Identifiable {
    case error(String)
    case delete(PasswordVaultDeleteRequest)

    var id: String {
        switch self {
        case let .error(message): "error.\(message)"
        case let .delete(request): "delete.\(request.id)"
        }
    }
}

@MainActor
final class PasswordVaultLibraryModel: ObservableObject {
    private static let sortOrderKey = "PasswordVault.SortOrder"

    @Published private(set) var snapshot = PasswordVaultSnapshot()
    @Published var sidebarSelection: PasswordVaultSidebarSelection? = .all
    @Published var selectedItemIDs: Set<UUID> = []
    @Published var selectedUsageID: UUID?
    @Published var searchText = ""
    @Published var sortOrder: PasswordVaultSortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey) }
    }

    @Published var editor: PasswordVaultEditorContext?
    @Published var alert: PasswordVaultAlert?
    @Published var showsClearHistoryConfirmation = false

    private let repository: PasswordVaultRepository
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(repository: PasswordVaultRepository = .shared,
         defaults: UserDefaults = SZSharedUserDefaults.defaults)
    {
        self.repository = repository
        self.defaults = defaults
        sortOrder = PasswordVaultSortOrder(rawValue: defaults.string(forKey: Self.sortOrderKey) ?? "")
            ?? .lastUsed

        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .passwordVaultDidChange,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }
    }

    isolated deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Derived data

    var allItems: [PasswordVaultItem] { snapshot.items }
    var allUsage: [PasswordVaultUsage] { snapshot.usage }

    var visibleItems: [PasswordVaultItem] {
        let filtered = baseItems.filter(matchesSearch)
        return sorted(filtered)
    }

    var visibleUsage: [PasswordVaultUsage] {
        guard sidebarSelection == .history else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.usage.filter { record in
            guard !query.isEmpty else { return true }
            let itemTitle = item(withID: record.itemID)?.title ?? ""
            return itemTitle.localizedCaseInsensitiveContains(query)
                || record.archiveName.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedItem: PasswordVaultItem? {
        guard let id = selectedItemIDs.first else { return nil }
        return item(withID: id)
    }

    var selectedUsage: PasswordVaultUsage? {
        guard let selectedUsageID else { return nil }
        return snapshot.usage.first { $0.id == selectedUsageID }
    }

    func item(withID id: UUID) -> PasswordVaultItem? {
        snapshot.items.first { $0.id == id }
    }

    func usage(for itemID: UUID) -> [PasswordVaultUsage] {
        snapshot.usage
            .filter { $0.itemID == itemID }
            .sorted { $0.date > $1.date }
    }

    func archiveNames(for itemID: UUID) -> [String] {
        var seen: Set<String> = []
        return usage(for: itemID).compactMap { record in
            guard seen.insert(record.archiveName).inserted else { return nil }
            return record.archiveName
        }
    }

    func count(for selection: PasswordVaultSidebarSelection) -> Int {
        switch selection {
        case .all: snapshot.items.count
        case .favorites: snapshot.items.filter(\.isFavorite).count
        case .recent: snapshot.items.filter { $0.lastUsedAt != nil }.count
        case .history: snapshot.usage.count
        }
    }

    func sidebarSelectionChanged() {
        selectedItemIDs.removeAll()
        selectedUsageID = nil
    }

    func pruneSelection() {
        let visibleIDs = Set(visibleItems.map(\.id))
        selectedItemIDs.formIntersection(visibleIDs)
        if let selectedUsageID, !visibleUsage.contains(where: { $0.id == selectedUsageID }) {
            self.selectedUsageID = nil
        }
    }

    // MARK: - Editing

    func beginAdding() {
        editor = PasswordVaultEditorContext(itemID: nil, draft: PasswordVaultItemDraft())
    }

    func beginEditing(_ item: PasswordVaultItem) {
        editor = PasswordVaultEditorContext(itemID: item.id, draft: PasswordVaultItemDraft(item: item))
    }

    func addItem(_ draft: PasswordVaultItemDraft) throws {
        let item = try repository.addItem(draft)
        reload()
        selectedItemIDs = [item.id]
    }

    func updateItem(id: UUID, with draft: PasswordVaultItemDraft) throws {
        let item = try repository.updateItem(id: id, with: draft)
        reload()
        selectedItemIDs = [item.id]
    }

    func toggleFavorite(_ item: PasswordVaultItem) {
        do {
            try repository.setFavorite(!item.isFavorite, for: item.id)
            reload()
        } catch {
            present(error)
        }
    }

    func requestDelete(_ items: [PasswordVaultItem]) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }
        let message = items.count == 1
            ? SZL10n.string("password.vault.delete.message", items[0].title)
            : SZL10n.string("password.vault.delete.messageMultiple", items.count)
        alert = .delete(PasswordVaultDeleteRequest(itemIDs: ids, message: message))
    }

    func confirmDelete() {
        guard case let .delete(request) = alert else { return }
        alert = nil
        do {
            try repository.deleteItems(withIDs: request.itemIDs)
            selectedItemIDs.subtract(request.itemIDs)
            reload()
        } catch {
            present(error)
        }
    }

    func copyPassword(_ item: PasswordVaultItem) {
        PasswordVaultClipboard.shared.copy(item.password)
    }

    func clearHistory() {
        showsClearHistoryConfirmation = false
        do {
            try repository.clearHistory()
            selectedUsageID = nil
            reload()
        } catch {
            present(error)
        }
    }

    func reload() {
        do {
            snapshot = try repository.snapshot()
            pruneSelection()
        } catch {
            present(error)
        }
    }

    func present(_ error: Error) {
        alert = .error((error as? PasswordVaultError)?.message ?? error.localizedDescription)
    }

    // MARK: - Filtering

    private var baseItems: [PasswordVaultItem] {
        switch sidebarSelection {
        case .all, nil:
            snapshot.items
        case .favorites:
            snapshot.items.filter(\.isFavorite)
        case .recent:
            snapshot.items.filter { $0.lastUsedAt != nil }
        case .history:
            []
        }
    }

    private func matchesSearch(_ item: PasswordVaultItem) -> Bool {
        PasswordVaultSearch.matches(searchText,
                                    item: item,
                                    archiveNames: archiveNames(for: item.id))
    }

    private func sorted(_ items: [PasswordVaultItem]) -> [PasswordVaultItem] {
        PasswordVaultSorting.sorted(items, by: sortOrder)
    }
}
