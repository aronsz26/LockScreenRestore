// iOS 15's Dynamic wallpapers (bokeh) for both SpringBoard and Settings.
//
// iOS 16 still ships them: their colors live in the system's Bokeh wallpaper collection
// (/Library/Wallpaper/Collections/Bokeh.wallpaperCollection/Wallpapers/<id>.<Name>.wallpaper/
// Wallpaper.plist, a light "default" and a "dark" set each), and WallpaperKit's WKBokehView
// draws them, animated and with its own parallax. A Dynamic design is stored as the absolute
// path of its .wallpaper folder instead of a name in our wallpapers folder.

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>

static NSString *const kLSRBokehWallpapersDir = @"/Library/Wallpaper/Collections/Bokeh.wallpaperCollection/Wallpapers";

static inline BOOL LSRIsBokehDesign(NSString *design) {
    return [design isKindOfClass:[NSString class]] && [design hasPrefix:kLSRBokehWallpapersDir]
        && [[NSFileManager defaultManager] fileExistsAtPath:[design stringByAppendingPathComponent:@"Wallpaper.plist"]];
}

static inline void LSRLoadWallpaperKit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dlopen("/System/Library/PrivateFrameworks/WallpaperKit.framework/WallpaperKit", RTLD_NOW); });
}

// The Dynamic designs in Apple's order (the id before the name).
static inline NSArray<NSString *> *LSRBokehDesigns(void) {
    NSMutableArray *designs = [NSMutableArray new];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kLSRBokehWallpapersDir error:nil]) {
        NSString *dir = [kLSRBokehWallpapersDir stringByAppendingPathComponent:name];
        if (LSRIsBokehDesign(dir)) [designs addObject:dir];
    }
    return [designs sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

static inline NSDictionary *LSRBokehAsset(NSString *dir, BOOL dark) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"Wallpaper.plist"]];
    NSDictionary *assets = plist[@"assets"][@"lockAndHome"];
    if (![assets isKindOfClass:[NSDictionary class]]) return nil;
    return (dark ? assets[@"dark"] : nil) ?: assets[@"default"];
}

// "Multicolored", "Warm Silver", ...
static inline NSString *LSRBokehName(NSString *dir) {
    NSString *name = LSRBokehAsset(dir, NO)[@"name"];
    if (name.length) return [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    NSString *folder = dir.lastPathComponent.stringByDeletingPathExtension;
    NSRange dot = [folder rangeOfString:@"."];
    return [(dot.location == NSNotFound ? folder : [folder substringFromIndex:NSMaxRange(dot)])
        stringByReplacingOccurrencesOfString:@"_" withString:@" "];
}

static inline NSArray<UIColor *> *LSRBokehColors(NSArray *hexes) {
    NSMutableArray *colors = [NSMutableArray new];
    for (NSString *hex in hexes) {
        if (![hex isKindOfClass:[NSString class]]) continue;
        unsigned int rgb = 0;
        [[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&rgb];
        [colors addObject:[UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0
                                           blue:(rgb & 0xFF) / 255.0 alpha:1.0]];
    }
    return colors;
}

static inline id LSRBokehInput(NSString *dir, BOOL dark) {
    LSRLoadWallpaperKit();
    NSDictionary *asset = LSRBokehAsset(dir, dark);
    Class inputClass = NSClassFromString(@"WKBokehWallpaperInput");
    SEL init = NSSelectorFromString(@"initWithBackgroundColors:bubbleColors:bubbleCount:bubbleScale:parallaxMultiplier:thumbnailSeed:");
    if (!asset || ![inputClass instancesRespondToSelector:init]) return nil;
    return ((id (*)(id, SEL, id, id, unsigned long long, double, double, unsigned long long))objc_msgSend)(
        [inputClass alloc], init, LSRBokehColors(asset[@"backgroundColors"]), LSRBokehColors(asset[@"bubbleColors"]),
        [asset[@"bubbleCount"] unsignedLongLongValue] ?: 40, [asset[@"bubbleScale"] doubleValue] ?: 1.0,
        [asset[@"parallaxMultiplier"] doubleValue], [asset[@"thumbnailSeed"] unsignedLongLongValue]);
}

// Apple's animated bokeh view; nil when this iOS doesn't have it.
static inline UIView *LSRBokehView(NSString *dir, BOOL dark, CGRect frame) {
    id input = LSRBokehInput(dir, dark);
    Class viewClass = NSClassFromString(@"WKBokehView");
    if (!input || ![viewClass instancesRespondToSelector:@selector(initWithBokehWallpaperInput:)]) return nil;
    UIView *view = ((id (*)(id, SEL, id))objc_msgSend)([viewClass alloc], @selector(initWithBokehWallpaperInput:), input);
    view.frame = frame;
    // The bubbles are laid out for the bounds the input arrives with: hand it over again now
    // that the view has its size.
    if ([view respondsToSelector:@selector(setBokehWallpaperInput:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(view, @selector(setBokehWallpaperInput:), input);
    }
    return view;
}

static inline void LSRSetBokehAnimating(UIView *view, BOOL animating) {
    if ([view respondsToSelector:@selector(setAnimationEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view, @selector(setAnimationEnabled:), animating);
    }
}

// A still frame, for thumbnails and for the lock screen's copies while it slides away.
static inline UIImage *LSRBokehImage(NSString *dir, BOOL dark, CGSize size) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    NSString *key = [NSString stringWithFormat:@"%@|%d|%.0fx%.0f", dir, dark, size.width, size.height];
    UIImage *image = [cache objectForKey:key];
    if (image) return image;
    // Apple's own thumbnail renderer draws the bubbles too (a plain snapshot of the view only
    // has the gradient: the bubbles appear once it's on screen). Scaled to the size asked for.
    id input = LSRBokehInput(dir, dark);
    Class viewClass = NSClassFromString(@"WKBokehView");
    UIImage *thumbnail = input && [viewClass respondsToSelector:@selector(thumbnailImageWithBokehInput:)]
        ? ((id (*)(id, SEL, id))objc_msgSend)(viewClass, @selector(thumbnailImageWithBokehInput:), input) : nil;
    if ([thumbnail isKindOfClass:[UIImage class]] && thumbnail.size.width > 0) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGFloat scale = MAX(size.width / thumbnail.size.width, size.height / thumbnail.size.height);
            CGSize drawn = CGSizeMake(thumbnail.size.width * scale, thumbnail.size.height * scale);
            [thumbnail drawInRect:CGRectMake((size.width - drawn.width) / 2, (size.height - drawn.height) / 2, drawn.width, drawn.height)];
        }];
        [cache setObject:image forKey:key];
        return image;
    }
    UIView *view = LSRBokehView(dir, dark, CGRectMake(0, 0, size.width, size.height));
    if (!view) return nil;
    LSRSetBokehAnimating(view, NO);
    [view setNeedsLayout];
    [view layoutIfNeeded];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [view.layer renderInContext:context.CGContext];
    }];
    if (image) [cache setObject:image forKey:key];
    return image;
}
