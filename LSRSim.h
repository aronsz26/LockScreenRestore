// Simulator builds: there is no /var/mobile, a simulated device keeps its files in its own data
// folder on the Mac (the home directory of its SpringBoard). On a real device paths stay as is.

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

static inline NSString *LSRDevicePath(NSString *path) {
#if TARGET_OS_SIMULATOR
    NSString *const mobile = @"/var/mobile/";
    if ([path hasPrefix:mobile]) {
        return [NSHomeDirectory() stringByAppendingPathComponent:[path substringFromIndex:mobile.length]];
    }
#endif
    return path;
}
