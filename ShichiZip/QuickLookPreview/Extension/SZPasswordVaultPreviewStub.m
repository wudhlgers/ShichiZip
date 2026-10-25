#import "../../Utilities/SZPasswordVault.h"

/// The Quick Look extension links the archive bridge, which notifies the
/// password vault after a successful password check. The extension must not
/// read or write the user's Keychain-backed library, so it uses this no-op
/// implementation. The main app compiles the real Swift-backed facade.
@implementation SZPasswordVault

+ (NSArray<NSString*>*)passwords {
    return @[];
}

+ (void)rememberPassword:(NSString*)password {}

+ (void)recordPassword:(NSString*)password forFile:(NSString*)file {}

+ (NSString*)passwordForFile:(NSString*)file {
    return nil;
}

+ (void)forgetPassword:(NSString*)password {}

+ (void)removeAllPasswords {}

+ (void)clearHistory {}

@end
