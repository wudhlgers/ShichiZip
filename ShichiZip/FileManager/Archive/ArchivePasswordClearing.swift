import Foundation

/// Clears password protection from an archive the user can already open with
/// its password: every entry is extracted with the known password, repacked
/// into a writable format without encryption, and written to the destination.
/// Metadata that survives neither extraction nor repacking (for example
/// archive comments) is not preserved.
enum ArchivePasswordClearing {
    /// Precheck result shown before asking the user to confirm the operation.
    struct Analysis {
        let archiveURL: URL
        /// Whether listing the archive proved it carries no encryption at all.
        /// False also covers archives the precheck could not open silently,
        /// such as archives with encrypted headers; the real operation will
        /// prompt for their password.
        let isKnownUnencrypted: Bool
        /// Non-nil when the archive's format can be re-created without a
        /// password, enabling in-place clearing. Read-only formats such as RAR
        /// fall back to repacking into a chosen writable format.
        let compressionFormat: SZArchiveFormat?
    }

    static func analyze(archiveURL: URL) -> Analysis {
        let archive = SZArchive()
        let session = SZOperationSession()
        // The precheck must never prompt for a password: a failed open keeps
        // the analysis unknown, and the real operation asks for the password.
        session.passwordRequestHandler = { _, _, _, _ in false }
        do {
            try archive.open(atPath: archiveURL.path, session: session)
        } catch {
            return Analysis(archiveURL: archiveURL, isKnownUnencrypted: false, compressionFormat: nil)
        }
        defer { archive.close() }

        let format = compressionFormat(for: archive.formatName)
        guard let entries = try? archive.entries(with: session) else {
            return Analysis(archiveURL: archiveURL, isKnownUnencrypted: false, compressionFormat: format)
        }
        return Analysis(archiveURL: archiveURL,
                        isKnownUnencrypted: !entries.contains { $0.isEncrypted },
                        compressionFormat: format)
    }

    /// The formats that both carry entry encryption and can be created fresh.
    /// Other writable formats either cannot be encrypted (tar, gzip) so
    /// clearing them is moot, or cannot be written at all (rar).
    static func compressionFormat(for formatName: String?) -> SZArchiveFormat? {
        switch formatName?.lowercased() {
        case "zip":
            .formatZip
        case "7z":
            .format7z
        default:
            nil
        }
    }

    /// Suggested file name for the save-as destination, keeping the archive's
    /// own extension.
    static func suggestedSaveAsFileName(for archiveURL: URL, suffix: String) -> String {
        suggestedFileName(for: archiveURL,
                          pathExtension: archiveURL.pathExtension,
                          suffix: suffix)
    }

    /// Compression settings for the clear-password flows: the same format,
    /// rebuilt without any encryption.
    static func makePlainOutputSettings(format: SZArchiveFormat) -> SZCompressionSettings {
        let settings = SZCompressionSettings()
        settings.format = format
        settings.pathMode = .relativePaths
        settings.encryption = .none
        settings.password = nil
        if format == .formatZip {
            settings.method = .deflate
            settings.methodName = "Deflate"
            settings.solidMode = false
        }
        return settings
    }

    /// Runs inside `ArchiveOperationRunner` on a background queue. With a
    /// non-nil `sourcePassword` the archive opens without prompting; otherwise
    /// the session asks for the password (and offers the password library).
    /// `outputSettings` drives the rebuilt archive; the repack always stores
    /// the extracted items under their own names regardless of the dialog's
    /// path mode, and original-file deletion stays the caller's decision.
    static func perform(archiveURL: URL,
                        destinationURL: URL,
                        outputSettings: SZCompressionSettings,
                        sourcePassword: String?,
                        session: SZOperationSession) throws
    {
        let archive = SZArchive()
        var openedWithoutPrompt = false
        if let sourcePassword {
            do {
                try archive.open(atPath: archiveURL.path, password: sourcePassword, session: session)
                openedWithoutPrompt = true
            } catch {
                // A stale reused password must not wedge the operation: fall
                // back to a prompted open before failing.
            }
        }
        if !openedWithoutPrompt {
            try archive.open(atPath: archiveURL.path, session: session)
        }
        defer { archive.close() }

        let workDirectory = try FileManagerTemporaryDirectorySupport
            .makeTemporaryDirectory(prefix: FileManagerTemporaryDirectorySupport.stagingPrefix)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        let extractionSettings = SZExtractionSettings()
        extractionSettings.overwriteMode = .rename
        try FileManagerArchiveExtraction.performFullArchiveExtraction(archive,
                                                                      to: workDirectory,
                                                                      settings: extractionSettings,
                                                                      session: session)

        let extractedItems = try FileManager.default.contentsOfDirectory(at: workDirectory,
                                                                         includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !extractedItems.isEmpty else {
            throw Self.makeError(SZL10n.string("app.archive.error.extractionFailed"))
        }

        outputSettings.pathMode = .relativePaths
        outputSettings.updateMode = .add
        outputSettings.deleteAfterCompression = false

        let outputURL = destinationURL.standardizedFileURL
        let stagingURL = try makeStagingURL(for: outputURL)
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        try SZArchive.create(atPath: stagingURL.path,
                             fromPaths: extractedItems.map(\.path),
                             settings: outputSettings,
                             session: session)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: stagingURL)
        } else {
            try FileManager.default.moveItem(at: stagingURL, to: outputURL)
        }
    }

    private static func suggestedFileName(for archiveURL: URL,
                                          pathExtension: String,
                                          suffix: String) -> String
    {
        let baseName = archiveURL.deletingPathExtension().lastPathComponent
        let newName = "\(baseName) (\(suffix))"
        return pathExtension.isEmpty ? newName : "\(newName).\(pathExtension)"
    }

    /// A hidden sibling of the destination on the same volume, so the final
    /// swap is a fast rename and interrupted runs never leave a half-written
    /// archive under the destination name.
    private static func makeStagingURL(for destinationURL: URL) throws -> URL {
        let directory = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = destinationURL.deletingPathExtension().lastPathComponent
        let pathExtension = destinationURL.pathExtension
        for _ in 0 ..< 16 {
            let suffix = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
            let name = pathExtension.isEmpty
                ? ".\(baseName).clear-\(suffix)"
                : ".\(baseName).clear-\(suffix).\(pathExtension)"
            let candidate = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw Self.makeError(SZL10n.string("app.archive.clearPassword.stagingFailed"))
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(domain: SZArchiveErrorDomain,
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
