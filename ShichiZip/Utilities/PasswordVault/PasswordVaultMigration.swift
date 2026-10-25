import Foundation

enum PasswordVaultLegacyKeys {
    static let entries = "SZSavedPasswordEntries"
    static let passwords = "SZSavedPasswords"
    static let history = "SZPasswordHistory"
}

/// Converts the pre-Keychain `UserDefaults` representation into the v3
/// snapshot. Only passwords that are still present in the saved-entry list
/// become items: history entries for forgotten or evicted passwords must not
/// resurrect them.
struct PasswordVaultMigration {
    let defaults: UserDefaults
    let now: Date

    init(defaults: UserDefaults, now: Date = Date()) {
        self.defaults = defaults
        self.now = now
    }

    var hasLegacyData: Bool {
        defaults.object(forKey: PasswordVaultLegacyKeys.entries) != nil
            || defaults.object(forKey: PasswordVaultLegacyKeys.passwords) != nil
            || defaults.object(forKey: PasswordVaultLegacyKeys.history) != nil
    }

    func snapshot() -> PasswordVaultSnapshot {
        let candidates = legacyEntries()
        let history = legacyHistory()

        var items: [PasswordVaultItem] = []
        var usages: [PasswordVaultUsage] = []
        var seenPasswords: Set<String> = []

        for candidate in candidates where !candidate.password.isEmpty {
            guard seenPasswords.insert(candidate.password).inserted else { continue }

            let matchingHistory = history.filter { $0.password == candidate.password }
            let latestHistory = matchingHistory.max { $0.date < $1.date }
            let archiveName = latestHistory?.archiveName
            let title = Self.title(for: archiveName) ?? SZL10n.string("password.vault.untitled")
            let itemID = UUID()

            items.append(PasswordVaultItem(
                id: itemID,
                title: title,
                password: candidate.password,
                iconName: nil,
                note: "",
                tags: [],
                isFavorite: false,
                createdAt: candidate.addedAt,
                updatedAt: candidate.addedAt,
                lastUsedAt: latestHistory?.date,
                useCount: matchingHistory.count,
            ))

            for record in matchingHistory {
                usages.append(PasswordVaultUsage(
                    itemID: itemID,
                    archiveName: record.archiveName,
                    date: record.date,
                ))
            }
        }

        let knownPasswords = Set(candidates.map(\.password))
        let droppedHistoryCount = history.filter { !knownPasswords.contains($0.password) }.count
        if droppedHistoryCount > 0 {
            SZLog.info("PasswordVault",
                       "Dropping \(droppedHistoryCount) legacy history records whose passwords are no longer saved")
        }

        usages.sort { $0.date > $1.date }
        return PasswordVaultSnapshot(items: items, usage: usages)
    }

    static func removeLegacyData(from defaults: UserDefaults) {
        defaults.removeObject(forKey: PasswordVaultLegacyKeys.entries)
        defaults.removeObject(forKey: PasswordVaultLegacyKeys.passwords)
        defaults.removeObject(forKey: PasswordVaultLegacyKeys.history)
    }

    private struct Candidate {
        let password: String
        let addedAt: Date
    }

    private struct HistoryRecord {
        let password: String
        let archiveName: String
        let date: Date
    }

    private func legacyEntries() -> [Candidate] {
        var candidates: [Candidate] = []
        var seen: Set<String> = []

        if let stored = defaults.array(forKey: PasswordVaultLegacyKeys.entries) {
            for value in stored {
                if let dictionary = value as? [String: Any],
                   let password = dictionary["password"] as? String,
                   !password.isEmpty,
                   seen.insert(password).inserted
                {
                    candidates.append(Candidate(
                        password: password,
                        addedAt: dictionary["addedAt"] as? Date ?? now,
                    ))
                } else if let password = value as? String,
                          !password.isEmpty,
                          seen.insert(password).inserted
                {
                    candidates.append(Candidate(password: password, addedAt: now))
                }
            }
        }

        if let legacyPasswords = defaults.stringArray(forKey: PasswordVaultLegacyKeys.passwords) {
            for password in legacyPasswords where !password.isEmpty && seen.insert(password).inserted {
                candidates.append(Candidate(password: password, addedAt: now))
            }
        }

        return candidates
    }

    private func legacyHistory() -> [HistoryRecord] {
        guard let stored = defaults.array(forKey: PasswordVaultLegacyKeys.history) else {
            return []
        }

        var records: [HistoryRecord] = []
        for value in stored {
            guard let dictionary = value as? [String: Any],
                  let password = dictionary["password"] as? String,
                  !password.isEmpty
            else {
                continue
            }
            let archiveName = (dictionary["file"] as? String) ?? ""
            guard !archiveName.isEmpty else { continue }
            records.append(HistoryRecord(
                password: password,
                archiveName: archiveName,
                date: dictionary["date"] as? Date ?? now,
            ))
        }
        return records
    }

    private static func title(for archiveName: String?) -> String? {
        guard let archiveName, !archiveName.isEmpty else { return nil }
        let fileName = (archiveName as NSString).lastPathComponent
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? fileName : base
    }
}
