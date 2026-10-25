import AppKit
import Foundation

/// A picker scope: the "mini vault browser" navigation shown in the rail.
enum PasswordVaultPickerScope: Hashable {
    case matched
    case favorites
    case recent
    case all
    case tag(String)
}

@MainActor
final class PasswordVaultPickerModel: ObservableObject {
    private static let sortOrderKey = "PasswordVault.PickerSortOrder"
    private static let maxVisibleTags = 12

    @Published private(set) var snapshot = PasswordVaultSnapshot()
    @Published var scope: PasswordVaultPickerScope = .all
    @Published var selectedItemID: UUID?
    @Published var searchText = ""
    @Published var sortOrder: PasswordVaultSortOrder {
        didSet { defaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey) }
    }

    @Published private(set) var loadErrorMessage: String?

    /// Archive file path the picker was opened for; nil disables the
    /// "This Archive" scope.
    let archivePath: String?

    private let repository: PasswordVaultRepository
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(repository: PasswordVaultRepository = .shared,
         defaults: UserDefaults = SZSharedUserDefaults.defaults,
         archivePath: String? = nil)
    {
        self.repository = repository
        self.defaults = defaults
        self.archivePath = archivePath
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

    // MARK: - Loading

    func reload() {
        do {
            snapshot = try repository.snapshot()
            pruneSelection()
        } catch {
            loadErrorMessage = (error as? PasswordVaultError)?.message ?? error.localizedDescription
        }
    }

    var isEmptyLibrary: Bool {
        snapshot.items.isEmpty
    }

    // MARK: - Scopes

    var hasArchiveContext: Bool {
        archivePath != nil
    }

    var matchedItemIDs: Set<UUID> {
        guard let archivePath else { return [] }
        return PasswordVaultMatching.matchedItemIDs(archivePath: archivePath, snapshot: snapshot)
    }

    func count(for scope: PasswordVaultPickerScope) -> Int {
        switch scope {
        case .matched: matchedItemIDs.count
        case .favorites: snapshot.items.filter(\.isFavorite).count
        case .recent: snapshot.items.filter { $0.lastUsedAt != nil }.count
        case .all: snapshot.items.count
        case let .tag(tag): snapshot.items.filter { $0.tags.contains(tag) }.count
        }
    }

    func items(for scope: PasswordVaultPickerScope) -> [PasswordVaultItem] {
        switch scope {
        case .matched:
            let matched = matchedItemIDs
            return snapshot.items.filter { matched.contains($0.id) }
        case .favorites:
            return snapshot.items.filter(\.isFavorite)
        case .recent:
            return snapshot.items.filter { $0.lastUsedAt != nil }
        case .all:
            return snapshot.items
        case let .tag(tag):
            return snapshot.items.filter { $0.tags.contains(tag) }
        }
    }

    /// Matched first, then the first non-empty convenience scope, so the picker
    /// always opens on something useful instead of a blank list.
    func defaultScope() -> PasswordVaultPickerScope {
        if hasArchiveContext, count(for: .matched) > 0 { return .matched }
        if count(for: .favorites) > 0 { return .favorites }
        if count(for: .recent) > 0 { return .recent }
        return .all
    }

    // MARK: - Rail metadata

    func title(for scope: PasswordVaultPickerScope) -> String {
        switch scope {
        case .matched: SZL10n.string("password.vault.picker.scope.matched")
        case .favorites: SZL10n.string("password.vault.sidebar.favorites")
        case .recent: SZL10n.string("password.vault.sidebar.recent")
        case .all: SZL10n.string("password.vault.sidebar.all")
        case let .tag(tag): "#\(tag)"
        }
    }

    func systemImage(for scope: PasswordVaultPickerScope) -> String {
        switch scope {
        case .matched: "sparkles"
        case .favorites: "star.fill"
        case .recent: "clock.arrow.circlepath"
        case .all: "key.fill"
        case .tag: "tag.fill"
        }
    }

    var visibleTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in snapshot.items {
            for tag in item.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.localizedStandardCompare(rhs.0) == .orderedAscending
            }
            .prefix(Self.maxVisibleTags)
            .map { ($0.0, $0.1) }
    }

    var searchPlaceholder: String {
        switch scope {
        case .matched:
            return SZL10n.string("password.vault.picker.searchMatched")
        case .favorites:
            return SZL10n.string("password.vault.picker.searchFavorites")
        case .recent:
            return SZL10n.string("password.vault.picker.searchRecent")
        case .all:
            return SZL10n.string("password.vault.searchPlaceholder")
        case .tag:
            return String(format: SZL10n.string("password.vault.picker.searchIn"), "#\(scopeTag)")
        }
    }

    private var scopeTag: String {
        guard case let .tag(tag) = scope else { return "" }
        return tag
    }

    // MARK: - List content

    var visibleItems: [PasswordVaultItem] {
        PasswordVaultSorting.sorted(items(for: scope).filter { item in
            PasswordVaultSearch.matches(searchText,
                                        item: item,
                                        archiveNames: archiveNames(for: item.id))
        }, by: sortOrder)
    }

    var selectedItem: PasswordVaultItem? {
        guard let selectedItemID else { return nil }
        return snapshot.items.first { $0.id == selectedItemID }
    }

    func pruneSelection() {
        let visibleIDs = Set(visibleItems.map(\.id))
        if let selectedItemID, !visibleIDs.contains(selectedItemID) {
            self.selectedItemID = nil
        }
    }

    func scopeChanged() {
        selectedItemID = nil
    }

    // MARK: - Helpers

    private func archiveNames(for itemID: UUID) -> [String] {
        var seen: Set<String> = []
        return snapshot.usage
            .filter { $0.itemID == itemID }
            .sorted { $0.date > $1.date }
            .compactMap { record in
                guard seen.insert(record.archiveName).inserted else { return nil }
                return record.archiveName
            }
    }
}
