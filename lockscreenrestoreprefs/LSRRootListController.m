#import <Preferences/PSListController.h>
#import <sys/sysctl.h>

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason options:(NSUInteger)options targetURL:(NSURL *)targetURL;
@end

// SBSRelaunchActionOptionsFadeToBlackTransition
static const NSUInteger kLSRRelaunchFadeToBlack = 1 << 2;

// The one device the layout has been checked on so far.
static NSString *const kLSRTestedModel = @"iPhone14,2";

static NSString *LSRModelIdentifier(void) {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *model = [NSString stringWithUTF8String:machine];
    free(machine);
    return model;
}

// Every iPhone that runs iOS 16.
static NSString *LSRDeviceName(NSString *model) {
    NSDictionary<NSString *, NSString *> *names = @{
        @"iPhone10,1": @"iPhone 8", @"iPhone10,4": @"iPhone 8",
        @"iPhone10,2": @"iPhone 8 Plus", @"iPhone10,5": @"iPhone 8 Plus",
        @"iPhone10,3": @"iPhone X", @"iPhone10,6": @"iPhone X",
        @"iPhone11,2": @"iPhone XS", @"iPhone11,4": @"iPhone XS Max", @"iPhone11,6": @"iPhone XS Max",
        @"iPhone11,8": @"iPhone XR",
        @"iPhone12,1": @"iPhone 11", @"iPhone12,3": @"iPhone 11 Pro", @"iPhone12,5": @"iPhone 11 Pro Max",
        @"iPhone12,8": @"iPhone SE (2nd generation)",
        @"iPhone13,1": @"iPhone 12 mini", @"iPhone13,2": @"iPhone 12",
        @"iPhone13,3": @"iPhone 12 Pro", @"iPhone13,4": @"iPhone 12 Pro Max",
        @"iPhone14,4": @"iPhone 13 mini", @"iPhone14,5": @"iPhone 13",
        @"iPhone14,2": @"iPhone 13 Pro", @"iPhone14,3": @"iPhone 13 Pro Max",
        @"iPhone14,6": @"iPhone SE (3rd generation)",
        @"iPhone14,7": @"iPhone 14", @"iPhone14,8": @"iPhone 14 Plus",
        @"iPhone15,2": @"iPhone 14 Pro", @"iPhone15,3": @"iPhone 14 Pro Max",
    };
    return names[model] ?: model;
}

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

// The tweak derives every size and position from the screen and SpringBoard's per-device
// lock screen metrics when SpringBoard starts. This shows what it will detect and recalculates.
- (void)fixPositions {
    UIScreen *screen = [UIScreen mainScreen];
    CGSize size = screen.bounds.size;
    NSString *model = LSRModelIdentifier();

    NSMutableString *message = [NSMutableString stringWithFormat:@"%@\n%.0f × %.0f pt @%.0fx\n\n",
        LSRDeviceName(model), MIN(size.width, size.height), MAX(size.width, size.height), screen.scale];
    [message appendString:@"Padlock, clock, date and Focus pill will be recalculated for this screen after a respring."];
    if (![model isEqualToString:kLSRTestedModel]) {
        [message appendString:@"\n\nThis iPhone hasn't been tested yet. If something looks off, please open an issue on GitHub with a screenshot."];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Fix Positions"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self respring];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
