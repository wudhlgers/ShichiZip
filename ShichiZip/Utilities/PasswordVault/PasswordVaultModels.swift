import Foundation

/// Legacy organization field. The UI no longer exposes categories — tags,
/// favorites, recency, and archive-name matching cover retrieval — but the
/// field stays so existing Keychain snapshots decode without migration.
enum PasswordVaultCategory: String, Codable, Sendable {
    case general
    case archive
    case document
    case media
    case backup
    case work
    case personal
    case other
}

/// Icon every entry shows until the user picks an override in the editor.
enum PasswordVaultIcon {
    static let `default` = "key.fill"
}

enum PasswordVaultSortOrder: String, CaseIterable, Identifiable, Sendable {
    case lastUsed
    case dateAdded
    case title
    case mostUsed

    var id: String { rawValue }

    var title: String {
        SZL10n.string("password.vault.sort.\(rawValue)")
    }
}

struct PasswordVaultItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var password: String
    var category: PasswordVaultCategory
    var iconName: String?
    var note: String
    var tags: [String]
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int

    init(id: UUID = UUID(),
         title: String,
         password: String,
         category: PasswordVaultCategory = .general,
         iconName: String? = nil,
         note: String = "",
         tags: [String] = [],
         isFavorite: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         lastUsedAt: Date? = nil,
         useCount: Int = 0)
    {
        self.id = id
        self.title = title
        self.password = password
        self.category = category
        self.iconName = iconName
        self.note = note
        self.tags = tags
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    var resolvedIconName: String {
        iconName ?? PasswordVaultIcon.default
    }

    var maskedPassword: String {
        String(repeating: "•", count: 8)
    }
}

struct PasswordVaultItemDraft: Sendable {
    var title: String
    var password: String
    var category: PasswordVaultCategory
    var iconName: String?
    var note: String
    var tags: [String]
    var isFavorite: Bool

    init(title: String = "",
         password: String = "",
         category: PasswordVaultCategory = .general,
         iconName: String? = nil,
         note: String = "",
         tags: [String] = [],
         isFavorite: Bool = false)
    {
        self.title = title
        self.password = password
        self.category = category
        self.iconName = iconName
        self.note = note
        self.tags = tags
        self.isFavorite = isFavorite
    }

    init(item: PasswordVaultItem) {
        title = item.title
        password = item.password
        category = item.category
        iconName = item.iconName
        note = item.note
        tags = item.tags
        isFavorite = item.isFavorite
    }
}

struct PasswordVaultUsage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var itemID: UUID
    var archiveName: String
    var date: Date

    init(id: UUID = UUID(), itemID: UUID, archiveName: String, date: Date = Date()) {
        self.id = id
        self.itemID = itemID
        self.archiveName = archiveName
        self.date = date
    }
}

struct PasswordVaultSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 3

    var schemaVersion: Int
    var items: [PasswordVaultItem]
    var usage: [PasswordVaultUsage]

    init(schemaVersion: Int = PasswordVaultSnapshot.currentSchemaVersion,
         items: [PasswordVaultItem] = [],
         usage: [PasswordVaultUsage] = [])
    {
        self.schemaVersion = schemaVersion
        self.items = items
        self.usage = usage
    }
}

enum PasswordVaultError: Error, Equatable {
    case keychain(OSStatus)
    case corruptData
    case duplicatePassword(existingTitle: String)
    case emptyTitle
    case emptyPassword
    case itemNotFound

    var message: String {
        switch self {
        case .keychain:
            SZL10n.string("password.vault.error.keychain")
        case .corruptData:
            SZL10n.string("password.vault.error.corruptData")
        case let .duplicatePassword(existingTitle):
            SZL10n.string("password.vault.error.duplicatePassword", existingTitle)
        case .emptyTitle:
            SZL10n.string("password.vault.error.emptyTitle")
        case .emptyPassword:
            SZL10n.string("password.vault.error.emptyPassword")
        case .itemNotFound:
            SZL10n.string("password.vault.error.itemNotFound")
        }
    }
}
