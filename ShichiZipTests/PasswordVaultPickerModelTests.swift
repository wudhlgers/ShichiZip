import Foundation
#if SHICHIZIP_ZS_VARIANT
    @testable import ShichiZip_ZS
#else
    @testable import ShichiZip
#endif
import XCTest

@MainActor
final class PasswordVaultPickerModelTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: InMemoryPasswordVaultStore!
    private var notificationCenter: NotificationCenter!
    private var repository: PasswordVaultRepository!

    override func setUp() {
        super.setUp()
        suiteName = "PasswordVaultPickerModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = InMemoryPasswordVaultStore()
        notificationCenter = NotificationCenter()
        repository = PasswordVaultRepository(
            store: store,
            defaults: defaults,
            notificationCenter: notificationCenter,
        )
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

    // MARK: - Default scope

    func testDefaultScopeFallsBackToFavoritesThenAll() throws {
        let other = try repository.addItem(PasswordVaultItemDraft(title: "Other", password: "other"))

        var model = makeModel(archivePath: "/x/movie.rar")
        XCTAssertEqual(model.defaultScope(), .all)

        try repository.setFavorite(true, for: other.id)
        model = makeModel(archivePath: "/x/movie.rar")
        XCTAssertEqual(model.defaultScope(), .favorites)

        try repository.recordPassword("movie-pw", forFile: "/x/movie.rar")
        model = makeModel(archivePath: "/x/movie.rar")
        XCTAssertEqual(model.defaultScope(), .matched)
        XCTAssertEqual(model.count(for: .matched), 1)
        XCTAssertEqual(model.items(for: .matched).first?.password, "movie-pw")
    }

    func testMatchedScopeUsesUniqueTitleFallback() throws {
        _ = try repository.addItem(PasswordVaultItemDraft(title: "series-backup", password: "manual"))

        let model = makeModel(archivePath: "/x/series-backup.zip")
        XCTAssertEqual(model.count(for: .matched), 1)
        XCTAssertEqual(model.items(for: .matched).first?.password, "manual")

        let ambiguous = makeModel(archivePath: "/x/other.rar")
        XCTAssertEqual(ambiguous.count(for: .matched), 0)
    }

    // MARK: - Search

    func testSearchCoversNoteTagsAndArchiveNamesWithinScope() throws {
        let noted = try repository.addItem(PasswordVaultItemDraft(title: "A", password: "a", note: "needle-note"))
        _ = try repository.addItem(PasswordVaultItemDraft(title: "B", password: "b", tags: ["needle-tag"]))
        _ = try repository.addItem(PasswordVaultItemDraft(title: "C", password: "c"))
        try repository.recordPassword("c", forFile: "needle.zip")

        let model = makeModel()
        model.scope = .all
        model.searchText = "needle"
        XCTAssertEqual(Set(model.visibleItems.map(\.title)), ["A", "B", "C"])

        model.searchText = "zzz"
        XCTAssertTrue(model.visibleItems.isEmpty)
        model.selectedItemID = noted.id
        model.pruneSelection()
        XCTAssertNil(model.selectedItem, "Selection must not survive a filter that hides the row")
    }

    // MARK: - Tags and sorting

    func testVisibleTagsAreSortedByCountThenName() throws {
        _ = try repository.addItem(PasswordVaultItemDraft(title: "One", password: "1", tags: ["dup", "single"]))
        _ = try repository.addItem(PasswordVaultItemDraft(title: "Two", password: "2", tags: ["dup"]))

        let model = makeModel()
        XCTAssertEqual(model.visibleTags.map(\.tag), ["dup", "single"])
        XCTAssertEqual(model.count(for: .tag("dup")), 2)

        model.scope = .tag("dup")
        XCTAssertEqual(Set(model.visibleItems.map(\.title)), ["One", "Two"])
    }

    func testSortOrderPersistsAcrossModels() {
        let model = makeModel()
        model.sortOrder = .title

        let reloaded = makeModel()
        XCTAssertEqual(reloaded.sortOrder, .title)
    }

    // MARK: - Helpers

    private func makeModel(archivePath: String? = nil) -> PasswordVaultPickerModel {
        PasswordVaultPickerModel(
            repository: repository,
            defaults: defaults,
            archivePath: archivePath,
        )
    }
}
