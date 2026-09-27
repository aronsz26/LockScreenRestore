#import <Preferences/PSListController.h>

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason options:(NSUInteger)options targetURL:(NSURL *)targetURL;
@end

// SBSRelaunchActionOptionsFadeToBlackTransition
static const NSUInteger kLSRRelaunchFadeToBlack = 1 << 2;

@interface LSRRootListController : PSListController
@end

@implementation LSRRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// The tweak picks its hook groups at SpringBoard launch (reading the plist from disk), so flush
// the switches to disk first, then respring.
- (void)respring {
    CFPreferencesAppSynchronize(CFSTR("com.aronsz26.lockscreenrestore"));
    SBSRelaunchAction *action = [SBSRelaunchAction actionWithReason:@"RestartRenderServer"
                                                            options:kLSRRelaunchFadeToBlack
                                                          targetURL:nil];
    [[FBSSystemService sharedService] sendActions:[NSSet setWithObject:action] withResult:nil];
}

@end
