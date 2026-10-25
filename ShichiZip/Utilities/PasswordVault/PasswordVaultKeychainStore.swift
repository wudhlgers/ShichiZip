import Foundation
import Security

protocol PasswordVaultStoring: AnyObject {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

/// Stores the whole vault as one generic-password item. The data-protection
/// keychain is preferred; ad-hoc or unsigned development builds fall back to
/// the legacy login keychain so the library remains usable.
final class KeychainPasswordVaultStore: PasswordVaultStoring {
    private enum Style {
        case dataProtection
        case legacy
    }

    private let service: String
    private let account: String
    private var activeStyle: Style?

    init(service: String = "\(Bundle.main.bundleIdentifier ?? "ee.dawn.ShichiZip").passwordVault",
         account: String = "v3")
    {
        self.service = service
        self.account = account
    }

    func load() throws -> Data? {
        if let data = try load(style: .dataProtection) {
            activeStyle = .dataProtection
            return data
        }
        if let data = try load(style: .legacy) {
            activeStyle = .legacy
            return data
        }
        return nil
    }

    func save(_ data: Data) throws {
        if let activeStyle {
            try save(data, style: activeStyle)
            return
        }

        do {
            try save(data, style: .dataProtection)
            activeStyle = .dataProtection
        } catch let error as PasswordVaultError {
            guard Self.isUnsupportedStyleError(error) else { throw error }
            try save(data, style: .legacy)
            activeStyle = .legacy
        }
    }

    func delete() throws {
        var firstError: OSStatus?
        for style in [Style.dataProtection, .legacy] {
            let status = SecItemDelete(query(style: style) as CFDictionary)
            if status != errSecSuccess,
               status != errSecItemNotFound,
               !Self.isUnsupportedStyleError(.keychain(status)),
               firstError == nil
            {
                firstError = status
            }
        }
        if let firstError {
            throw PasswordVaultError.keychain(firstError)
        }
        activeStyle = nil
    }

    private func load(style: Style) throws -> Data? {
        var query = query(style: style)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw PasswordVaultError.corruptData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            if Self.isUnsupportedStyleError(.keychain(status)) {
                return nil
            }
            throw PasswordVaultError.keychain(status)
        }
    }

    private func save(_ data: Data, style: Style) throws {
        let baseQuery = query(style: style)
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PasswordVaultError.keychain(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        if style == .dataProtection {
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PasswordVaultError.keychain(addStatus)
        }
    }

    private func query(style: Style) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if style == .dataProtection {
            query[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
        }
        return query
    }

    private static func isUnsupportedStyleError(_ error: PasswordVaultError) -> Bool {
        guard case let .keychain(status) = error else { return false }
        return status == errSecParam
            || status == errSecNotAvailable
            || status == errSecMissingEntitlement
            || status == errSecUnimplemented
    }
}

/// Test double. Production code always uses `KeychainPasswordVaultStore`.
final class InMemoryPasswordVaultStore: PasswordVaultStoring {
    private let lock = NSLock()
    private var data: Data?
    var loadError: Error?
    var saveError: Error?
    var deleteError: Error?

    init(data: Data? = nil) {
        self.data = data
    }

    func load() throws -> Data? {
        if let loadError { throw loadError }
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func save(_ data: Data) throws {
        if let saveError { throw saveError }
        lock.lock()
        defer { lock.unlock() }
        self.data = data
    }

    func delete() throws {
        if let deleteError { throw deleteError }
        lock.lock()
        defer { lock.unlock() }
        data = nil
    }

    var storedData: Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
