import AppKit
import Foundation
#if SHICHIZIP_ZS_VARIANT
    @testable import ShichiZip_ZS
#else
    @testable import ShichiZip
#endif
import XCTest

final class PasswordVaultTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: InMemoryPasswordVaultStore!
    private var notificationCenter: NotificationCenter!
    private var repository: PasswordVaultRepository!

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "PasswordVaultTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = InMemoryPasswordVaultStore()
        notificationCenter = NotificationCenter()
        repository = makeRepository()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        repository = nil
        notificationCenter = nil
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Editing

    func testAddUpdateFavoriteAndDelete() throws {
        let added = try repository.addItem(PasswordVaultItemDraft(
            title: "Home backup",
            password: "secret",
            category: .backup,
            note: "Weekly",
            tags: ["home", " home ", ""],
        ))
        XCTAssertEqual(added.title, "Home backup")
        XCTAssertEqual(added.tags, ["home"])
        XCTAssertEqual(try repository.items().count, 1)

        let updated = try repository.updateItem(id: added.id, with: PasswordVaultItemDraft(
            title: "Home backup 2",
            password: "secret-2",
            category: .work,
            iconName: "briefcase.fill",
        ))
        XCTAssertEqual(updated.title, "Home backup 2")
        XCTAssertEqual(updated.category, .work)
        XCTAssertEqual(updated.iconName, "briefcase.fill")
        XCTAssertEqual(updated.createdAt, added.createdAt)

        try repository.setFavorite(true, for: added.id)
        XCTAssertTrue(try XCTUnwrap(repository.item(withID: added.id)).isFavorite)

        try repository.deleteItems(withIDs: [added.id])
        XCTAssertTrue(try repository.items().isEmpty)
    }

    func testValidationAndDuplicatePassword() throws {
        XCTAssertThrowsError(try repository.addItem(PasswordVaultItemDraft(title: "", password: "x"))) {
            XCTAssertEqual($0 as? PasswordVaultError, .emptyTitle)
        }
        XCTAssertThrowsError(try repository.addItem(PasswordVaultItemDraft(title: "x", password: ""))) {
            XCTAssertEqual($0 as? PasswordVaultError, .emptyPassword)
        }

        _ = try repository.addItem(PasswordVaultItemDraft(title: "First", password: "same"))
        XCTAssertThrowsError(try repository.addItem(PasswordVaultItemDraft(title: "Second", password: "same"))) {
            XCTAssertEqual($0 as? PasswordVaultError, .duplicatePassword(existingTitle: "First"))
        }
    }

    @MainActor
    func testLibraryModelAddItemReturnsWithoutDeadlocking() throws {
        let repo = makeRepository(notificationCenter: .default)
        let model = PasswordVaultLibraryModel(repository: repo, defaults: defaults)
        try model.addItem(PasswordVaultItemDraft(title: "Deadlock check", password: "deadlock-check"))
        XCTAssertEqual(model.allItems.count, 1)
    }

    // MARK: - Clipboard

    @MainActor
    func testClipboardClearsOwnedPasswordAfterDelay() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasswordVaultTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let clipboard = PasswordVaultClipboard(pasteboard: pasteboard, clearDelay: 0.05)

        clipboard.copy("owned-password")
        XCTAssertEqual(pasteboard.string(forType: .string), "owned-password")

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    @MainActor
    func testClipboardDoesNotClearNewerContent() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PasswordVaultTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let clipboard = PasswordVaultClipboard(pasteboard: pasteboard, clearDelay: 0.05)

        clipboard.copy("owned-password")
        pasteboard.clearContents()
        pasteboard.setString("newer-content", forType: .string)

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(pasteboard.string(forType: .string), "newer-content")
    }

    // MARK: - Automatic capture

    func testRecordPasswordCreatesItemAndUsage() throws {
        try repository.rememberPassword("archive-password")
        let remembered = try XCTUnwrap(repository.items().first)
        XCTAssertEqual(remembered.useCount, 0)

        try repository.recordPassword("archive-password", forFile: "/downloads/movie.rar")
        let item = try XCTUnwrap(repository.items().first)
        XCTAssertEqual(item.id, remembered.id)
        XCTAssertEqual(item.title, "movie")
        XCTAssertEqual(item.useCount, 1)
        XCTAssertEqual(item.lastUsedAt, fixedDate)
        XCTAssertEqual(try repository.usage(for: item.id).map(\.archiveName), ["movie.rar"])

        try repository.recordPassword("archive-password", forFile: "/downloads/second.7z")
        let updated = try XCTUnwrap(repository.items().first)
        XCTAssertEqual(updated.useCount, 2)
        XCTAssertEqual(try repository.archiveNames(for: item.id), ["second.7z", "movie.rar"])
    }

    func testUsageIsCappedButItemsAreNot() throws {
        for index in 0 ..< 505 {
            try repository.recordPassword("one-password", forFile: "archive-\(index).zip")
        }
        let usage = try repository.usage()
        XCTAssertEqual(usage.count, PasswordVaultRepository.usageLimit)
        XCTAssertEqual(usage.first?.archiveName, "archive-504.zip")
        XCTAssertEqual(usage.last?.archiveName, "archive-5.zip")
        XCTAssertEqual(try repository.items().count, 1)
    }

    func testFindsMostRecentlyUsedPasswordByArchiveFileName() throws {
        try repository.recordPassword("old-password", forFile: "/downloads/movie.rar")
        try repository.recordPassword("new-password", forFile: "/backups/movie.rar")

        XCTAssertEqual(
            try repository.password(matchingArchivePath: "/elsewhere/movie.rar"),
            "new-password",
        )
        XCTAssertNil(try repository.password(matchingArchivePath: "/elsewhere/other.rar"))
    }

    func testFallsBackToUnambiguousManualTitleMatch() throws {
        _ = try repository.addItem(PasswordVaultItemDraft(title: "family-backup", password: "manual-password"))
        XCTAssertEqual(
            try repository.password(matchingArchivePath: "/elsewhere/family-backup.zip"),
            "manual-password",
        )

        _ = try repository.addItem(PasswordVaultItemDraft(title: "family-backup", password: "second-password"))
        XCTAssertNil(try repository.password(matchingArchivePath: "/elsewhere/family-backup.zip"),
                     "Ambiguous title matches must not pick a password")
    }

    func testForgetAndClearHistory() throws {
        try repository.recordPassword("a", forFile: "a.zip")
        try repository.recordPassword("b", forFile: "b.zip")
        try repository.clearHistory()
        XCTAssertTrue(try repository.usage().isEmpty)
        XCTAssertEqual(try repository.items().count, 2)

        try repository.forgetPassword("a")
        XCTAssertEqual(try repository.items().map(\.password), ["b"])

        try repository.removeAllPasswords()
        XCTAssertTrue(try repository.items().isEmpty)
        XCTAssertTrue(try repository.usage().isEmpty)
    }

    // MARK: - Migration

    func testMigratesLegacyEntriesAndHistory() throws {
        let addedA = fixedDate.addingTimeInterval(-100)
        let addedB = fixedDate.addingTimeInterval(-50)
        defaults.set([
            ["password": "old-a", "addedAt": addedA],
            ["password": "old-b", "addedAt": addedB],
        ], forKey: PasswordVaultLegacyKeys.entries)
        defaults.set(["old-b"], forKey: PasswordVaultLegacyKeys.passwords)
        defaults.set([
            ["file": "/downloads/movie.rar", "password": "old-a", "date": addedB],
            ["file": "/downloads/movie.rar", "password": "old-a", "date": fixedDate],
            ["file": "/downloads/ghost.zip", "password": "ghost", "date": fixedDate],
        ], forKey: PasswordVaultLegacyKeys.history)

        let snapshot = try repository.snapshot()
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.usage.count, 2)

        let itemA = try XCTUnwrap(snapshot.items.first { $0.password == "old-a" })
        XCTAssertEqual(itemA.title, "movie")
        XCTAssertEqual(itemA.createdAt, addedA)
        XCTAssertEqual(itemA.lastUsedAt, fixedDate)
        XCTAssertEqual(itemA.useCount, 2)

        let itemB = try XCTUnwrap(snapshot.items.first { $0.password == "old-b" })
        XCTAssertEqual(itemB.category, .general)
        XCTAssertEqual(itemB.useCount, 0)
        XCTAssertEqual(itemB.createdAt, addedB)

        XCTAssertNil(defaults.object(forKey: PasswordVaultLegacyKeys.entries))
        XCTAssertNil(defaults.object(forKey: PasswordVaultLegacyKeys.passwords))
        XCTAssertNil(defaults.object(forKey: PasswordVaultLegacyKeys.history))

        let ids = snapshot.items.map(\.id)
        let reloaded = try makeRepository().snapshot()
        XCTAssertEqual(reloaded.items.map(\.id), ids, "Migration must be idempotent")
    }

    func testMigrationReadsLegacyPasswordsEvenWhenCurrentEntryArrayIsEmpty() throws {
        defaults.set([], forKey: PasswordVaultLegacyKeys.entries)
        defaults.set(["legacy-password"], forKey: PasswordVaultLegacyKeys.passwords)

        let snapshot = try repository.snapshot()
        XCTAssertEqual(snapshot.items.map(\.password), ["legacy-password"])
    }

    func testCorruptKeychainDataLeavesLegacyDataUntouched() throws {
        defaults.set([["password": "old", "addedAt": fixedDate]], forKey: PasswordVaultLegacyKeys.entries)
        store = InMemoryPasswordVaultStore(data: Data("not-json".utf8))
        repository = makeRepository()

        XCTAssertThrowsError(try repository.snapshot()) {
            XCTAssertEqual($0 as? PasswordVaultError, .corruptData)
        }
        XCTAssertNotNil(defaults.object(forKey: PasswordVaultLegacyKeys.entries))
    }

    func testSaveFailureLeavesLegacyDataUntouched() throws {
        defaults.set([["password": "old", "addedAt": fixedDate]], forKey: PasswordVaultLegacyKeys.entries)
        store.saveError = PasswordVaultError.keychain(-1)

        XCTAssertThrowsError(try repository.snapshot())
        XCTAssertNotNil(defaults.object(forKey: PasswordVaultLegacyKeys.entries))
    }

    func testNormalizesDuplicatePasswordsIDsAndOrphanUsage() throws {
        let sharedID = UUID()
        let orphanID = UUID()
        let snapshot = PasswordVaultSnapshot(
            items: [
                PasswordVaultItem(id: sharedID, title: "A", password: "a"),
                PasswordVaultItem(id: sharedID, title: "B", password: "b"),
                PasswordVaultItem(id: UUID(), title: "A duplicate", password: "a"),
            ],
            usage: [
                PasswordVaultUsage(itemID: sharedID, archiveName: "a.zip", date: fixedDate),
                PasswordVaultUsage(itemID: orphanID, archiveName: "orphan.zip", date: fixedDate),
            ],
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        store = InMemoryPasswordVaultStore(data: try encoder.encode(snapshot))
        repository = makeRepository()

        let normalized = try repository.snapshot()
        XCTAssertEqual(normalized.items.count, 2)
        XCTAssertEqual(Set(normalized.items.map(\.password)), ["a", "b"])
        XCTAssertEqual(Set(normalized.items.map(\.id)).count, 2)
        XCTAssertEqual(normalized.usage.count, 1)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeRepository(notificationCenter: NotificationCenter? = nil) -> PasswordVaultRepository {
        PasswordVaultRepository(
            store: store,
            defaults: defaults,
            notificationCenter: notificationCenter ?? self.notificationCenter,
            now: { [fixedDate] in fixedDate },
        )
    }
}
