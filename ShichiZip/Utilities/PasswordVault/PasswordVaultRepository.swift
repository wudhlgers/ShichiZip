import Foundation

extension Notification.Name {
    static let passwordVaultDidChange = Notification.Name("PasswordVaultDidChange")
}

/// Thread-safe façade over the Keychain-backed snapshot. Archive operations
/// call the Objective-C facade from worker queues while the library window
/// reads and edits from the main actor, so every mutation takes the same lock.
final class PasswordVaultRepository: @unchecked Sendable {
    #if DEBUG
        /// Backing suite for the in-memory vault that deterministic UI tests
        /// request with `SHICHIZIP_UI_TEST_IN_MEMORY_PASSWORD_VAULT`. The same
        /// suite doubles as the tests' scratch defaults domain and is reset on
        /// every launch.
        private static let uiTestSuiteName = "ee.dawn.ShichiZip.UITests.PasswordVault"
    #endif

    static let shared: PasswordVaultRepository = {
        #if DEBUG
            if ProcessInfo.processInfo.environment["SHICHIZIP_UI_TEST_IN_MEMORY_PASSWORD_VAULT"] == "1",
               let uiTestDefaults = UserDefaults(suiteName: PasswordVaultRepository.uiTestSuiteName)
            {
                uiTestDefaults.removePersistentDomain(forName: PasswordVaultRepository.uiTestSuiteName)
                return PasswordVaultRepository(
                    store: InMemoryPasswordVaultStore(),
                    defaults: uiTestDefaults,
                )
            }
        #endif
        return PasswordVaultRepository(
            store: KeychainPasswordVaultStore(),
            defaults: SZSharedUserDefaults.defaults,
        )
    }()

    static let usageLimit = 500

    private let lock = NSLock()
    private let store: PasswordVaultStoring
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let now: @Sendable () -> Date
    private var cachedSnapshot: PasswordVaultSnapshot?

    init(store: PasswordVaultStoring,
         defaults: UserDefaults,
         notificationCenter: NotificationCenter = .default,
         now: @escaping @Sendable () -> Date = Date.init)
    {
        self.store = store
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.now = now
    }

    // MARK: - Reads

    func snapshot() throws -> PasswordVaultSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return try loadSnapshotLocked()
    }

    func items() throws -> [PasswordVaultItem] {
        try snapshot().items
    }

    func usage() throws -> [PasswordVaultUsage] {
        try snapshot().usage
    }

    func usage(for itemID: UUID) throws -> [PasswordVaultUsage] {
        try snapshot().usage
            .filter { $0.itemID == itemID }
            .sorted { $0.date > $1.date }
    }

    func archiveNames(for itemID: UUID) throws -> [String] {
        var seen: Set<String> = []
        return try usage(for: itemID).compactMap { record in
            guard seen.insert(record.archiveName).inserted else { return nil }
            return record.archiveName
        }
    }

    /// Returns the most recently used password for an archive file name.
    /// Only the last path component is stored, so a moved archive still
    /// matches its usage history.
    func password(matchingArchivePath path: String) throws -> String? {
        let snapshot = try snapshot()
        let matchedIDs = PasswordVaultMatching.matchedItemIDs(archivePath: path, snapshot: snapshot)
        guard !matchedIDs.isEmpty else { return nil }

        let archiveName = (path as NSString).lastPathComponent
        let matchingUsage = snapshot.usage
            .filter { matchedIDs.contains($0.itemID) }
            .filter { PasswordVaultMatching.archiveName($0.archiveName, matches: archiveName) }
            .sorted { $0.date > $1.date }
        for record in matchingUsage {
            if let item = snapshot.items.first(where: { $0.id == record.itemID }) {
                return item.password
            }
        }
        return snapshot.items.first { matchedIDs.contains($0.id) }?.password
    }

    func item(withID id: UUID) throws -> PasswordVaultItem? {
        try snapshot().items.first { $0.id == id }
    }

    // MARK: - Editing

    @discardableResult
    func addItem(_ draft: PasswordVaultItemDraft) throws -> PasswordVaultItem {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = try loadSnapshotLocked()
        let password = draft.password
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { throw PasswordVaultError.emptyPassword }
        guard !title.isEmpty else { throw PasswordVaultError.emptyTitle }
        if let existing = snapshot.items.first(where: { $0.password == password }) {
            throw PasswordVaultError.duplicatePassword(existingTitle: existing.title)
        }

        let date = now()
        let item = PasswordVaultItem(
            title: title,
            password: password,
            category: draft.category,
            iconName: draft.iconName,
            note: draft.note,
            tags: Self.normalizedTags(draft.tags),
            isFavorite: draft.isFavorite,
            createdAt: date,
            updatedAt: date,
        )
        snapshot.items.insert(item, at: 0)
        try saveSnapshotLocked(snapshot)
        return item
    }

    @discardableResult
    func updateItem(id: UUID, with draft: PasswordVaultItemDraft) throws -> PasswordVaultItem {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = try loadSnapshotLocked()
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else {
            throw PasswordVaultError.itemNotFound
        }
        let password = draft.password
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else { throw PasswordVaultError.emptyPassword }
        guard !title.isEmpty else { throw PasswordVaultError.emptyTitle }
        if let existing = snapshot.items.first(where: { $0.id != id && $0.password == password }) {
            throw PasswordVaultError.duplicatePassword(existingTitle: existing.title)
        }

        var item = snapshot.items[index]
        item.title = title
        item.password = password
        item.category = draft.category
        item.iconName = draft.iconName
        item.note = draft.note
        item.tags = Self.normalizedTags(draft.tags)
        item.isFavorite = draft.isFavorite
        item.updatedAt = now()
        snapshot.items[index] = item
        try saveSnapshotLocked(snapshot)
        return item
    }

    func setFavorite(_ isFavorite: Bool, for id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = try loadSnapshotLocked()
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else {
            throw PasswordVaultError.itemNotFound
        }
        snapshot.items[index].isFavorite = isFavorite
        snapshot.items[index].updatedAt = now()
        try saveSnapshotLocked(snapshot)
    }

    func deleteItems(withIDs ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var snapshot = try loadSnapshotLocked()
        snapshot.items.removeAll { ids.contains($0.id) }
        snapshot.usage.removeAll { ids.contains($0.itemID) }
        try saveSnapshotLocked(snapshot)
    }

    func clearHistory() throws {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = try loadSnapshotLocked()
        guard !snapshot.usage.isEmpty else { return }
        snapshot.usage.removeAll()
        try saveSnapshotLocked(snapshot)
    }

    // MARK: - Automatic capture

    func rememberPassword(_ password: String) throws {
        guard !password.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var snapshot = try loadSnapshotLocked()
        guard !snapshot.items.contains(where: { $0.password == password }) else { return }
        let date = now()
        snapshot.items.insert(PasswordVaultItem(
            title: SZL10n.string("password.vault.untitled"),
            password: password,
            category: .general,
            createdAt: date,
            updatedAt: date,
        ), at: 0)
        try saveSnapshotLocked(snapshot)
    }

    func recordPassword(_ password: String, forFile file: String?) throws {
        guard !password.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var snapshot = try loadSnapshotLocked()
        let date = now()
        let archiveName = file.map { ($0 as NSString).lastPathComponent } ?? ""

        let itemID: UUID
        if let index = snapshot.items.firstIndex(where: { $0.password == password }) {
            itemID = snapshot.items[index].id
            snapshot.items[index].lastUsedAt = date
            snapshot.items[index].useCount += 1
            if !archiveName.isEmpty,
               snapshot.items[index].title == SZL10n.string("password.vault.untitled")
            {
                snapshot.items[index].title = Self.title(for: archiveName)
            }
        } else {
            itemID = UUID()
            snapshot.items.insert(PasswordVaultItem(
                id: itemID,
                title: Self.title(for: archiveName),
                password: password,
                createdAt: date,
                updatedAt: date,
                lastUsedAt: date,
                useCount: 1,
            ), at: 0)
        }

        if !archiveName.isEmpty {
            snapshot.usage.insert(PasswordVaultUsage(
                itemID: itemID,
                archiveName: archiveName,
                date: date,
            ), at: 0)
            if snapshot.usage.count > Self.usageLimit {
                snapshot.usage.removeLast(snapshot.usage.count - Self.usageLimit)
            }
        }

        try saveSnapshotLocked(snapshot)
    }

    func forgetPassword(_ password: String) throws {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = try loadSnapshotLocked()
        let ids = Set(snapshot.items.filter { $0.password == password }.map(\.id))
        guard !ids.isEmpty else { return }
        snapshot.items.removeAll { ids.contains($0.id) }
        snapshot.usage.removeAll { ids.contains($0.itemID) }
        try saveSnapshotLocked(snapshot)
    }

    func removeAllPasswords() throws {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = try loadSnapshotLocked()
        guard !snapshot.items.isEmpty else { return }
        snapshot.items.removeAll()
        snapshot.usage.removeAll()
        try saveSnapshotLocked(snapshot)
    }

    // MARK: - Persistence

    private func loadSnapshotLocked() throws -> PasswordVaultSnapshot {
        if let cachedSnapshot {
            return cachedSnapshot
        }

        if let data = try store.load() {
            do {
                let decoded = try Self.decoder().decode(PasswordVaultSnapshot.self, from: data)
                let normalized = Self.normalized(decoded)
                cachedSnapshot = normalized
                return normalized
            } catch {
                SZLog.error("PasswordVault", "Stored vault data could not be decoded")
                throw PasswordVaultError.corruptData
            }
        }

        let migration = PasswordVaultMigration(defaults: defaults, now: now())
        guard migration.hasLegacyData else {
            let empty = PasswordVaultSnapshot()
            cachedSnapshot = empty
            return empty
        }

        let migrated = Self.normalized(migration.snapshot())
        let data = try Self.encoder().encode(migrated)
        try store.save(data)
        PasswordVaultMigration.removeLegacyData(from: defaults)
        cachedSnapshot = migrated
        SZLog.info("PasswordVault",
                   "Migrated legacy vault to Keychain: \(migrated.items.count) items, \(migrated.usage.count) usage records")
        return migrated
    }

    private func saveSnapshotLocked(_ snapshot: PasswordVaultSnapshot) throws {
        let data = try Self.encoder().encode(snapshot)
        try store.save(data)
        cachedSnapshot = snapshot
        notifyDidChange()
    }

    private func notifyDidChange() {
        // Mutations hold `lock` while saving. Observers reload the vault, which
        // takes the same lock, so the notification must run after the mutation
        // unwinds — never synchronously on the calling (often main) thread.
        DispatchQueue.main.async { [notificationCenter] in
            notificationCenter.post(name: .passwordVaultDidChange, object: nil)
        }
    }

    private static func normalized(_ snapshot: PasswordVaultSnapshot) -> PasswordVaultSnapshot {
        var seenPasswords: Set<String> = []
        var seenIDs: Set<UUID> = []
        var items: [PasswordVaultItem] = []

        for var item in snapshot.items {
            guard !item.password.isEmpty else { continue }
            guard seenPasswords.insert(item.password).inserted else { continue }
            if !seenIDs.insert(item.id).inserted {
                item.id = UUID()
                seenIDs.insert(item.id)
            }
            item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if item.title.isEmpty {
                item.title = SZL10n.string("password.vault.untitled")
            }
            item.tags = normalizedTags(item.tags)
            item.useCount = max(0, item.useCount)
            items.append(item)
        }

        let validIDs = Set(items.map(\.id))
        var usage = snapshot.usage.filter { validIDs.contains($0.itemID) }
        usage.sort { $0.date > $1.date }
        if usage.count > usageLimit {
            usage.removeLast(usage.count - usageLimit)
        }

        return PasswordVaultSnapshot(
            schemaVersion: PasswordVaultSnapshot.currentSchemaVersion,
            items: items,
            usage: usage,
        )
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func title(for archiveName: String) -> String {
        guard !archiveName.isEmpty else {
            return SZL10n.string("password.vault.untitled")
        }
        let fileName = (archiveName as NSString).lastPathComponent
        let base = (fileName as NSString).deletingPathExtension
        return base.isEmpty ? fileName : base
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
