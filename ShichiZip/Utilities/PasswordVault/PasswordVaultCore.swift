import Foundation

/// Objective-C visible facade used by the archive bridge and password prompts.
/// All real work lives in `PasswordVaultRepository`.
@objcMembers
final class PasswordVaultCore: NSObject {
    private static var repository: PasswordVaultRepository {
        .shared
    }

    @objc class func passwords() -> [String] {
        do {
            return try repository.items().map(\.password)
        } catch {
            log(error)
            return []
        }
    }

    @objc class func rememberPassword(_ password: String) {
        do {
            try repository.rememberPassword(password)
        } catch {
            log(error)
        }
    }

    @objc class func recordPassword(_ password: String, forFile file: String?) {
        do {
            try repository.recordPassword(password, forFile: file)
        } catch {
            log(error)
        }
    }

    @objc class func password(forFile file: String?) -> String? {
        guard let file, !file.isEmpty else { return nil }
        do {
            return try repository.password(matchingArchivePath: file)
        } catch {
            log(error)
            return nil
        }
    }

    @objc class func forgetPassword(_ password: String) {
        do {
            try repository.forgetPassword(password)
        } catch {
            log(error)
        }
    }

    @objc class func removeAllPasswords() {
        do {
            try repository.removeAllPasswords()
        } catch {
            log(error)
        }
    }

    @objc class func clearHistory() {
        do {
            try repository.clearHistory()
        } catch {
            log(error)
        }
    }

    private class func log(_ error: Error) {
        let message = (error as? PasswordVaultError)?.message ?? error.localizedDescription
        SZLog.error("PasswordVault", "Vault operation failed: \(message)")
    }
}
