#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C compatibility facade over the Keychain-backed Swift
/// password vault. Archive operations and password prompts call these methods;
/// the library UI uses `PasswordVaultRepository` directly.
@interface SZPasswordVault : NSObject

+ (NSArray<NSString*>*)passwords;

+ (void)rememberPassword:(NSString*)password;

/// Remembers `password` and records a usage entry for `file` (only the last
/// path component is stored).
+ (void)recordPassword:(NSString*)password forFile:(nullable NSString*)file;

/// Returns the most recently used password for an archive file name, or nil.
+ (nullable NSString*)passwordForFile:(nullable NSString*)file;

+ (void)forgetPassword:(NSString*)password;

+ (void)removeAllPasswords;

+ (void)clearHistory;

@end

NS_ASSUME_NONNULL_END
