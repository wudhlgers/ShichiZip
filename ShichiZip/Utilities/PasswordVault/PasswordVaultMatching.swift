import Foundation

/// Shared archive↔password matching. Auto-apply, the picker's "This Archive"
/// scope, and the repository lookup must agree on what "belongs to this
/// archive" means.
enum PasswordVaultMatching {
    /// Case-insensitive archive-name equality; macOS file systems are
    /// case-preserving, so usage history written as `Movie.rar` should still
    /// match `movie.rar`.
    static func archiveName(_ lhs: String, matches rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    /// A manually titled entry may use the full file name or the basename.
    static func titleMatchesArchive(_ title: String, archiveName: String) -> Bool {
        let baseName = (archiveName as NSString).deletingPathExtension
        return title.caseInsensitiveCompare(archiveName) == .orderedSame
            || title.caseInsensitiveCompare(baseName) == .orderedSame
    }

    /// Item IDs belonging to an archive path: usage-linked items win; without
    /// usage history, a single unambiguous title match is accepted so a manually
    /// named entry still surfaces while ambiguous titles never leak a password.
    static func matchedItemIDs(archivePath: String,
                               snapshot: PasswordVaultSnapshot) -> Set<UUID>
    {
        let archiveName = (archivePath as NSString).lastPathComponent
        guard !archiveName.isEmpty else { return [] }

        let usageMatches = snapshot.items.filter { item in
            snapshot.usage.contains { record in
                record.itemID == item.id && Self.archiveName(record.archiveName, matches: archiveName)
            }
        }
        if !usageMatches.isEmpty {
            return Set(usageMatches.map(\.id))
        }

        let titleMatches = snapshot.items.filter { Self.titleMatchesArchive($0.title, archiveName: archiveName) }
        return titleMatches.count == 1 ? Set(titleMatches.map(\.id)) : []
    }
}
