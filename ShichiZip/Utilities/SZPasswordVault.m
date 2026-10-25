#import "SZPasswordVault.h"

#if SHICHIZIP_ZS_VARIANT
#import "ShichiZip_ZS-Swift.h"
#else
#import "ShichiZip-Swift.h"
#endif

@implementation SZPasswordVault

+ (NSArray<NSString*>*)passwords {
    return [PasswordVaultCore passwords];
}

+ (void)rememberPassword:(NSString*)password {
    [PasswordVaultCore rememberPassword:password];
}

+ (void)recordPassword:(NSString*)password forFile:(NSString*)file {
    [PasswordVaultCore recordPassword:password forFile:file];
}

+ (NSString*)passwordForFile:(NSString*)file {
    return [PasswordVaultCore passwordForFile:file];
}

+ (void)forgetPassword:(NSString*)password {
    [PasswordVaultCore forgetPassword:password];
}

+ (void)removeAllPasswords {
    [PasswordVaultCore removeAllPasswords];
}

+ (void)clearHistory {
    [PasswordVaultCore clearHistory];
}

@end
