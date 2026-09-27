// Development-only helpers, compiled out of release builds (make package FINALPACKAGE=1).
//
// Over SSH, while the lock screen is visible:
//   touch /var/mobile/Documents/lsr-dump-request
//     -> LockScreenRestoreViews-now.log: every view in every window (class, frame in window
//        coordinates, hidden/alpha/transform, label text/font/color)
//   printf "Focus\nCSFocus\n" > /var/mobile/Documents/lsr-recon-request
//     -> LockScreenRestoreRecon-now.log: methods/ivars/properties of matching classes
//   printf "CSCombinedListViewController topContentInset\n" > /var/mobile/Documents/lsr-call-request
//     -> LockScreenRestoreCalls-now.log: result of a zero-argument getter on the live instance
//        ("Class +selector" calls a class method; "Class a.b.c" follows a getter chain)

#ifdef DEBUG

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface UIWindow (LSRPrivate)
+ (NSArray *)allWindowsIncludingInternalWindows:(BOOL)includeInternal onlyVisibleWindows:(BOOL)onlyVisible;
@end

static void LSRDumpClass(Class cls, NSMutableString *out) {
    [out appendFormat:@"\n=== %@ (superclass: %@) ===\n", NSStringFromClass(cls), NSStringFromClass(class_getSuperclass(cls))];

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    [out appendFormat:@"-- instance methods (%u) --\n", count];
    for (unsigned int i = 0; i < count; i++) {
        [out appendFormat:@"  - %@ %s\n", NSStringFromSelector(method_getName(methods[i])),
            method_getTypeEncoding(methods[i]) ?: ""];
    }
    free(methods);

    methods = class_copyMethodList(object_getClass(cls), &count);
    [out appendFormat:@"-- class methods (%u) --\n", count];
    for (unsigned int i = 0; i < count; i++) {
        [out appendFormat:@"  + %@ %s\n", NSStringFromSelector(method_getName(methods[i])),
            method_getTypeEncoding(methods[i]) ?: ""];
    }
    free(methods);

    Ivar *ivars = class_copyIvarList(cls, &count);
    [out appendFormat:@"-- ivars (%u) --\n", count];
    for (unsigned int i = 0; i < count; i++) {
        [out appendFormat:@"  %s (%s)\n", ivar_getName(ivars[i]) ?: "?", ivar_getTypeEncoding(ivars[i]) ?: "?"];
    }
    free(ivars);

    objc_property_t *props = class_copyPropertyList(cls, &count);
    [out appendFormat:@"-- properties (%u) --\n", count];
    for (unsigned int i = 0; i < count; i++) {
        [out appendFormat:@"  @property %s (%s)\n", property_getName(props[i]), property_getAttributes(props[i]) ?: ""];
    }
    free(props);
}

static void LSRRunRecon(NSArray<NSString *> *fragments) {
    NSMutableString *out = [NSMutableString new];
    [out appendFormat:@"LockScreenRestore recon %@ — %@\n", fragments, [NSDate date]];
    int numClasses = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * (unsigned long)numClasses);
    numClasses = objc_getClassList(classes, numClasses);
    for (int i = 0; i < numClasses; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        for (NSString *fragment in fragments) {
            if ([name rangeOfString:fragment options:NSCaseInsensitiveSearch].location != NSNotFound) {
                LSRDumpClass(classes[i], out);
                break;
            }
        }
    }
    free(classes);
    [out writeToFile:@"/var/mobile/Documents/LockScreenRestoreRecon-now.log" atomically:YES
            encoding:NSUTF8StringEncoding error:nil];
}

static void LSRDumpView(UIView *view, NSUInteger depth, NSMutableString *out) {
    NSString *extra = @"";
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        extra = [NSString stringWithFormat:@" text=\"%@\" font=%@ %.1f color=%@", label.text,
            label.font.fontName, label.font.pointSize, label.textColor];
    } else if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        extra = [NSString stringWithFormat:@" image=%@ tint=%@", imageView.image, imageView.tintColor];
    }
    if (view.backgroundColor) extra = [extra stringByAppendingFormat:@" bg=%@", view.backgroundColor];
    if (view.layer.cornerRadius > 0) extra = [extra stringByAppendingFormat:@" radius=%.1f", view.layer.cornerRadius];
    NSString *transform = CGAffineTransformIsIdentity(view.transform) ? @""
        : [NSString stringWithFormat:@" transform=%@", NSStringFromCGAffineTransform(view.transform)];
    [out appendFormat:@"%@%@ %p frame=%@ hidden=%d alpha=%.2f%@%@\n",
        [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
        NSStringFromClass([view class]), view, NSStringFromCGRect([view convertRect:view.bounds toView:nil]),
        view.hidden, view.alpha, transform, extra];
    for (UIView *sub in view.subviews) LSRDumpView(sub, depth + 1, out);
}

static void LSRDumpAllWindows(void) {
    NSMutableString *out = [NSMutableString new];
    [out appendFormat:@"### view dump — %@\n", [NSDate date]];
    for (UIWindow *window in [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO]) {
        [out appendFormat:@"\n##### WINDOW %@ level=%.0f hidden=%d\n", NSStringFromClass([window class]),
            window.windowLevel, window.hidden];
        LSRDumpView(window, 0, out);
    }
    [out writeToFile:@"/var/mobile/Documents/LockScreenRestoreViews-now.log" atomically:YES
            encoding:NSUTF8StringEncoding error:nil];
}

// Live object lookup: first view of the class in any window, else first view controller of
// the class reachable from the windows' root view controllers.
static id LSRFindViewOfClass(UIView *root, Class cls) {
    if ([root isKindOfClass:cls]) return root;
    for (UIView *sub in root.subviews) {
        id found = LSRFindViewOfClass(sub, cls);
        if (found) return found;
    }
    return nil;
}

static id LSRFindViewControllerOfClass(UIViewController *vc, Class cls) {
    if (!vc) return nil;
    if ([vc isKindOfClass:cls]) return vc;
    for (UIViewController *child in vc.childViewControllers) {
        id found = LSRFindViewControllerOfClass(child, cls);
        if (found) return found;
    }
    return LSRFindViewControllerOfClass(vc.presentedViewController, cls);
}

static id LSRFindLiveObject(Class cls) {
    NSArray *windows = [UIWindow allWindowsIncludingInternalWindows:YES onlyVisibleWindows:NO];
    for (UIWindow *window in windows) {
        id found = LSRFindViewOfClass(window, cls);
        if (found) return found;
    }
    for (UIWindow *window in windows) {
        id found = LSRFindViewControllerOfClass(window.rootViewController, cls);
        if (found) return found;
    }
    return nil;
}

// Calls a zero-argument getter and formats the common return types.
static NSString *LSRCallGetter(id target, SEL sel) {
    if (![target respondsToSelector:sel]) return @"<does not respond>";
    NSMethodSignature *sig = [target methodSignatureForSelector:sel];
    if (sig.numberOfArguments != 2) return @"<not a zero-argument getter>";
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = target;
    inv.selector = sel;
    [inv invoke];
    const char *type = sig.methodReturnType;
    if (type[0] == '@') {
        __unsafe_unretained id value = nil;
        [inv getReturnValue:&value];
        return [NSString stringWithFormat:@"%@", value];
    }
    if (type[0] == 'B' || type[0] == 'c') { BOOL v; [inv getReturnValue:&v]; return v ? @"YES" : @"NO"; }
    if (type[0] == 'd') { double v; [inv getReturnValue:&v]; return [NSString stringWithFormat:@"%.2f", v]; }
    if (type[0] == 'q' || type[0] == 'Q' || type[0] == 'i' || type[0] == 'I' || type[0] == 'l' || type[0] == 'L') {
        long long v = 0; [inv getReturnValue:&v]; return [NSString stringWithFormat:@"%lld", v];
    }
    if (strncmp(type, "{CGRect", 7) == 0) { CGRect v; [inv getReturnValue:&v]; return NSStringFromCGRect(v); }
    if (strncmp(type, "{CGPoint", 8) == 0) { CGPoint v; [inv getReturnValue:&v]; return NSStringFromCGPoint(v); }
    if (strncmp(type, "{CGSize", 7) == 0) { CGSize v; [inv getReturnValue:&v]; return NSStringFromCGSize(v); }
    if (strncmp(type, "{UIEdgeInsets", 13) == 0) { UIEdgeInsets v; [inv getReturnValue:&v]; return NSStringFromUIEdgeInsets(v); }
    return [NSString stringWithFormat:@"<unsupported return type %s>", type];
}

// Request lines: "ClassName selector" -> LockScreenRestoreCalls-now.log
static void LSRRunCalls(NSString *body) {
    NSMutableString *out = [NSMutableString new];
    for (NSString *line in [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSArray *parts = [[line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
            componentsSeparatedByString:@" "];
        if (parts.count != 2) continue;
        Class cls = NSClassFromString(parts[0]);
        // "+selector" calls a class method instead of looking for a live instance.
        BOOL classCall = [parts[1] hasPrefix:@"+"];
        if (classCall) parts = @[parts[0], [parts[1] substringFromIndex:1]];
        id target = cls ? (classCall ? (id)cls : LSRFindLiveObject(cls)) : nil;
        NSString *result = @"<no live instance>";
        if (target) {
            @try {
                // "a.b.c": every step but the last must return an object.
                NSArray *path = [parts[1] componentsSeparatedByString:@"."];
                for (NSUInteger i = 0; i + 1 < path.count && target; i++) {
                    target = [target valueForKey:path[i]];
                }
                result = target ? LSRCallGetter(target, NSSelectorFromString(path.lastObject)) : @"<nil in path>";
            } @catch (NSException *e) {
                result = [NSString stringWithFormat:@"<exception %@>", e.reason];
            }
        }
        [out appendFormat:@"%@ %@ = %@\n", parts[0], parts[1], result];
    }
    [out writeToFile:@"/var/mobile/Documents/LockScreenRestoreCalls-now.log" atomically:YES
            encoding:NSUTF8StringEncoding error:nil];
}

__attribute__((constructor)) static void LSRInstallDebugTools(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *dumpRequest = @"/var/mobile/Documents/lsr-dump-request";
            if ([fm fileExistsAtPath:dumpRequest]) {
                [fm removeItemAtPath:dumpRequest error:nil];
                LSRDumpAllWindows();
            }
            NSString *reconRequest = @"/var/mobile/Documents/lsr-recon-request";
            if ([fm fileExistsAtPath:reconRequest]) {
                NSString *body = [NSString stringWithContentsOfFile:reconRequest encoding:NSUTF8StringEncoding error:nil];
                [fm removeItemAtPath:reconRequest error:nil];
                NSMutableArray *fragments = [NSMutableArray new];
                for (NSString *line in [body componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
                    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (trimmed.length) [fragments addObject:trimmed];
                }
                if (fragments.count) LSRRunRecon(fragments);
            }
            NSString *callRequest = @"/var/mobile/Documents/lsr-call-request";
            if ([fm fileExistsAtPath:callRequest]) {
                NSString *body = [NSString stringWithContentsOfFile:callRequest encoding:NSUTF8StringEncoding error:nil];
                [fm removeItemAtPath:callRequest error:nil];
                LSRRunCalls(body);
            }
        }];
    });
}

#endif
