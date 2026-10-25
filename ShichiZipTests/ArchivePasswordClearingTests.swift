import Foundation
#if SHICHIZIP_ZS_VARIANT
    @testable import ShichiZip_ZS
#else
    @testable import ShichiZip
#endif
import XCTest

final class ArchivePasswordClearingTests: XCTestCase {
    private static let password = "clear-me-password"

    // MARK: - perform

    func testPerformReplacesEncryptedZipInPlaceWithoutPassword() throws {
        let payloads = ["root.txt": "root payload",
                        "nested/inner.txt": "inner payload"]
        let archiveURL = try makeEncryptedArchive(named: "clear-zip-in-place",
                                                  format: .formatZip,
                                                  payloads: payloads)

        try perform(archiveURL: archiveURL, destinationURL: archiveURL, targetFormat: .formatZip)

        XCTAssertEqual(try readContents(archiveURL, password: nil), payloads)
        try assertNoEntryEncrypted(archiveURL)
    }

    func testPerformWritesDecryptedZipToNewDestinationAndKeepsOriginal() throws {
        let payloads = ["root.txt": "root payload"]
        let archiveURL = try makeEncryptedArchive(named: "clear-zip-save-as",
                                                  format: .formatZip,
                                                  payloads: payloads)
        let destinationURL = archiveURL.deletingLastPathComponent()
            .appendingPathComponent("cleared-copy.zip")

        try perform(archiveURL: archiveURL, destinationURL: destinationURL, targetFormat: .formatZip)

        XCTAssertEqual(try readContents(archiveURL, password: Self.password), payloads,
                       "The save-as operation must not modify the original archive")
        try assertEncrypted(archiveURL)
        XCTAssertEqual(try readContents(destinationURL, password: nil), payloads)
        try assertNoEntryEncrypted(destinationURL)
    }

    func testPerformClearsEncrypted7zWithEncryptedFileNames() throws {
        let payloads = ["root.txt": "root payload",
                        "nested/inner.txt": "inner payload"]
        let archiveURL = try makeEncryptedArchive(named: "clear-7z-encrypted-names",
                                                  format: .format7z,
                                                  payloads: payloads,
                                                  encryptFileNames: true)

        try perform(archiveURL: archiveURL, destinationURL: archiveURL, targetFormat: .format7z)

        XCTAssertEqual(try readContents(archiveURL, password: nil), payloads)
        try assertNoEntryEncrypted(archiveURL)
    }

    /// A reused password (as cached from an open archive) must open the
    /// archive without any prompt.
    func testPerformWithCachedPasswordSkipsThePrompt() throws {
        let payloads = ["root.txt": "root payload"]
        let archiveURL = try makeEncryptedArchive(named: "clear-zip-cached-pw",
                                                  format: .formatZip,
                                                  payloads: payloads)

        let session = SZOperationSession()
        session.passwordRequestHandler = { _, _, _, _ in false }
        try ArchivePasswordClearing.perform(archiveURL: archiveURL,
                                            destinationURL: archiveURL,
                                            outputSettings: ArchivePasswordClearing.makePlainOutputSettings(format: .formatZip),
                                            sourcePassword: Self.password,
                                            session: session)

        XCTAssertEqual(try readContents(archiveURL, password: nil), payloads)
    }

    /// A stale reused password falls back to the session's prompt instead of
    /// failing the whole operation.
    func testPerformWithStalePasswordFallsBackToPrompt() throws {
        let payloads = ["root.txt": "root payload"]
        let archiveURL = try makeEncryptedArchive(named: "clear-zip-stale-pw",
                                                  format: .formatZip,
                                                  payloads: payloads)

        let session = makeNoPromptSession(password: Self.password)
        try ArchivePasswordClearing.perform(archiveURL: archiveURL,
                                            destinationURL: archiveURL,
                                            outputSettings: ArchivePasswordClearing.makePlainOutputSettings(format: .formatZip),
                                            sourcePassword: "stale-wrong-password",
                                            session: session)

        XCTAssertEqual(try readContents(archiveURL, password: nil), payloads)
    }

    // MARK: - analyze

    func testAnalysisReportsPlainArchiveAsKnownUnencrypted() throws {
        let archiveURL = try makeEncryptedArchive(named: "clear-analysis-plain",
                                                  format: .formatZip,
                                                  payloads: ["root.txt": "root payload"],
                                                  password: nil)

        let analysis = ArchivePasswordClearing.analyze(archiveURL: archiveURL)

        XCTAssertTrue(analysis.isKnownUnencrypted)
        XCTAssertEqual(analysis.compressionFormat, .formatZip)
    }

    func testAnalysisReportsEncryptedEntriesAndFormat() throws {
        let archiveURL = try makeEncryptedArchive(named: "clear-analysis-encrypted",
                                                  format: .formatZip,
                                                  payloads: ["root.txt": "root payload"])

        let analysis = ArchivePasswordClearing.analyze(archiveURL: archiveURL)

        XCTAssertFalse(analysis.isKnownUnencrypted)
        XCTAssertEqual(analysis.compressionFormat, .formatZip)
    }

    func testAnalysisStaysUnknownWhenArchiveHeadersAreEncrypted() throws {
        let archiveURL = try makeEncryptedArchive(named: "clear-analysis-headers",
                                                  format: .format7z,
                                                  payloads: ["root.txt": "root payload"],
                                                  encryptFileNames: true)

        let analysis = ArchivePasswordClearing.analyze(archiveURL: archiveURL)

        XCTAssertFalse(analysis.isKnownUnencrypted)
        XCTAssertNil(analysis.compressionFormat)
    }

    // MARK: - Naming and format mapping

    func testCompressionFormatMapping() {
        XCTAssertEqual(ArchivePasswordClearing.compressionFormat(for: "zip"), .formatZip)
        XCTAssertEqual(ArchivePasswordClearing.compressionFormat(for: "7z"), .format7z)
        XCTAssertEqual(ArchivePasswordClearing.compressionFormat(for: "ZIP"), .formatZip)
        XCTAssertNil(ArchivePasswordClearing.compressionFormat(for: "rar"))
        XCTAssertNil(ArchivePasswordClearing.compressionFormat(for: nil))
    }

    func testSuggestedSaveAsFileName() {
        XCTAssertEqual(ArchivePasswordClearing.suggestedSaveAsFileName(
            for: URL(fileURLWithPath: "/tmp/backup.zip"), suffix: "no password"),
            "backup (no password).zip")
        XCTAssertEqual(ArchivePasswordClearing.suggestedSaveAsFileName(
            for: URL(fileURLWithPath: "/tmp/backup.7z"), suffix: "无密码"),
            "backup (无密码).7z")
        XCTAssertEqual(ArchivePasswordClearing.suggestedSaveAsFileName(
            for: URL(fileURLWithPath: "/tmp/backup"), suffix: "no password"),
            "backup (no password)")
    }

    // MARK: - Helpers

    /// Supplies the archive password without any UI, mirroring the default
    /// session's prompt the app relies on during the real operation.
    private func perform(archiveURL: URL, destinationURL: URL, targetFormat: SZArchiveFormat) throws {
        let session = SZOperationSession()
        session.passwordRequestHandler = { _, _, _, password in
            password?.pointee = Self.password as NSString
            return true
        }
        try ArchivePasswordClearing.perform(archiveURL: archiveURL,
                                            destinationURL: destinationURL,
                                            outputSettings: ArchivePasswordClearing.makePlainOutputSettings(format: targetFormat),
                                            sourcePassword: nil,
                                            session: session)
    }

    private func makeEncryptedArchive(named name: String,
                                      format: SZArchiveFormat,
                                      payloads: [String: String],
                                      encryptFileNames: Bool = false,
                                      password: String? = ArchivePasswordClearingTests.password) throws -> URL {
        let tempRoot = try makeTemporaryDirectory(named: name)
        var sourceURLs: [URL] = []
        for (relativePath, contents) in payloads.sorted(by: { $0.key < $1.key }) {
            let fileURL = tempRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            sourceURLs.append(fileURL)
        }

        let ext = format == .formatZip ? "zip" : "7z"
        let archiveURL = tempRoot.appendingPathComponent("\(name).\(ext)")

        let settings = SZCompressionSettings()
        settings.format = format
        settings.pathMode = .relativePaths
        settings.password = password
        if format == .format7z {
            settings.encryptFileNames = encryptFileNames
        } else {
            settings.encryption = password == nil ? .none : .AES256
            settings.method = .deflate
            settings.methodName = "Deflate"
        }
        try SZArchive.create(atPath: archiveURL.path,
                             fromPaths: sourceURLs.map(\.path),
                             settings: settings,
                             session: nil)
        return archiveURL
    }

    private func makeNoPromptSession(password: String?) -> SZOperationSession {
        let session = SZOperationSession()
        session.passwordRequestHandler = { _, _, _, suppliedPassword in
            if let password {
                suppliedPassword?.pointee = password as NSString
                return true
            }
            return false
        }
        return session
    }

    /// Reads every file entry's contents. Passing a nil password fails the
    /// open or extraction for any archive that is still protected, so the
    /// assertions prove both decryption and content preservation.
    private func readContents(_ archiveURL: URL, password: String?) throws -> [String: String] {
        let archive = SZArchive()
        try archive.open(atPath: archiveURL.path, session: makeNoPromptSession(password: password))
        defer { archive.close() }

        let entries = try archive.entries(with: makeNoPromptSession(password: password))
            .filter { !$0.isDirectory }
        guard !entries.isEmpty else { return [:] }

        var contents: [String: String] = [:]
        let settings = SZExtractionSettings()
        settings.pathMode = .noPaths
        settings.overwriteMode = .rename
        for entry in entries {
            let destination = try makeTemporaryDirectory(named: "clear-read-\(UUID().uuidString.prefix(8))")
            let outputs = try archive.extractEntriesWithOutputURLs([NSNumber(value: entry.index)],
                                                                   toPath: destination.path,
                                                                   settings: settings,
                                                                   session: makeNoPromptSession(password: password))
            contents[entry.path] = try String(contentsOf: try XCTUnwrap(outputs.first), encoding: .utf8)
        }
        return contents
    }

    private func assertNoEntryEncrypted(_ archiveURL: URL) throws {
        let archive = SZArchive()
        try archive.open(atPath: archiveURL.path, session: makeNoPromptSession(password: nil))
        defer { archive.close() }
        XCTAssertFalse(archive.entries().contains { $0.isEncrypted },
                       "\(archiveURL.lastPathComponent) must have no encrypted entries")
    }

    private func assertEncrypted(_ archiveURL: URL) throws {
        let archive = SZArchive()
        try archive.open(atPath: archiveURL.path, session: makeNoPromptSession(password: Self.password))
        defer { archive.close() }
        XCTAssertTrue(archive.entries().contains { $0.isEncrypted },
                      "\(archiveURL.lastPathComponent) must keep its encrypted entries")
    }
}
