import Foundation

/// Shared vault search rules. The library window and the picker must agree on
/// which fields a query covers; the picker's no-results copy already promises
/// name, tags, notes, and archive names.
enum PasswordVaultSearch {
    static func matches(_ query: String,
                        item: PasswordVaultItem,
                        archiveNames: [String]) -> Bool
    {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if item.title.localizedCaseInsensitiveContains(query) { return true }
        if item.note.localizedCaseInsensitiveContains(query) { return true }
        if item.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
        return archiveNames.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

/// Shared ordering so the library window and the picker present rows the same
/// way for a given sort choice.
enum PasswordVaultSorting {
    static func sorted(_ items: [PasswordVaultItem],
                       by order: PasswordVaultSortOrder) -> [PasswordVaultItem]
    {
        items.sorted { lhs, rhs in
            switch order {
            case .lastUsed:
                let left = lhs.lastUsedAt ?? lhs.createdAt
                let right = rhs.lastUsedAt ?? rhs.createdAt
                if left != right { return left > right }
                return lhs.createdAt > rhs.createdAt
            case .dateAdded:
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.createdAt > rhs.createdAt
            case .mostUsed:
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                return (lhs.lastUsedAt ?? lhs.createdAt) > (rhs.lastUsedAt ?? rhs.createdAt)
            }
        }
    }
}
