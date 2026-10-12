// iOS 15's Dynamic wallpapers (bokeh) for both SpringBoard and Settings.
//
// iOS 16 still ships iOS 15's own bokeh view, renamed (SBFBokehWallpaperView ->
// PBUIBokehWallpaperView, the way iPadOS 16 draws Dynamic wallpapers), and its presets:
// +[Bokeh presetWallpaperOptions] in ProceduralWallpapers.bundle lists the same 14 on 15.8 and
// 16.1, seven on black ("newblue", ...) and seven light ones ("Blue_v01", "BokehGradient", ...),
// each with Apple's thumbnail. That view draws them, animated and with its own parallax.
//
// A Dynamic design is stored as the absolute path of its folder in iOS 16's Bokeh collection
// (/Library/Wallpaper/Collections/Bokeh.wallpaperCollection/Wallpapers/<id>.<Name>.wallpaper),
// which pairs the same designs as a light "default" and a "dark" set. WallpaperKit's WKBokehView
// (iOS 16's own renderer for that collection) is only the fallback.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
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
        // "#RRGGBB" or "#RRGGBBAA".
        NSString *digits = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
        unsigned int value = 0;
        [[NSScanner scannerWithString:digits] scanHexInt:&value];
        CGFloat alpha = 1.0;
        if (digits.length > 6) {
            alpha = (value & 0xFF) / 255.0;
            value >>= 8;
        }
        [colors addObject:[UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0
                                           blue:(value & 0xFF) / 255.0 alpha:alpha]];
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

// WallpaperKit's animated bokeh view; nil when this iOS doesn't have it.
static inline UIView *LSRCollectionBokehView(NSString *dir, BOOL dark, CGRect frame) {
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

// The preset iOS 15 had for a design of the collection, per appearance. Orange and Purple only
// exist on black and the two silvers only light: those look the same in both appearances.
static inline NSString *LSRLegacyBokehVariant(NSString *dir, BOOL dark) {
    static NSDictionary<NSString *, NSArray<NSString *> *> *variants;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        variants = @{ @"Multicolored": @[@"BokehGradient", @"newmixedcolors"], @"Green": @[@"Green_v01", @"newgreen"],
                      @"Yellow": @[@"Yellow_v03", @"newyellow"], @"Orange": @[@"neworange", @"neworange"],
                      @"Red": @[@"Red_v01", @"newred"], @"Purple": @[@"newpurple", @"newpurple"],
                      @"Blue": @[@"Blue_v01", @"newblue"], @"Warm_Silver": @[@"Silver_v01", @"Silver_v01"],
                      @"Cool_Silver": @[@"BokehGradientSilver", @"BokehGradientSilver"] };
    });
    NSString *folder = dir.lastPathComponent.stringByDeletingPathExtension;
    NSRange dot = [folder rangeOfString:@"."];
    return variants[dot.location == NSNotFound ? folder : [folder substringFromIndex:NSMaxRange(dot)]][dark ? 1 : 0];
}

static inline NSBundle *LSRProceduralWallpapersBundle(void) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/PaperBoardUI.framework/PaperBoardUI", RTLD_NOW);
        bundle = [NSBundle bundleWithPath:@"/System/Library/ProceduralWallpaper/ProceduralWallpapers.bundle"];
        [bundle load];
    });
    return bundle;
}

// The view showing a design right now (the wallpaper window's): its snapshot has the bubbles
// where they are on screen.
static __weak UIView *sLSRLiveBokehView = nil;
static const void *const kLSRBokehVariantKey = &kLSRBokehVariantKey;

static inline UIView *LSRLegacyBokehView(NSString *dir, BOOL dark, CGRect frame) {
    NSString *variant = LSRLegacyBokehVariant(dir, dark);
    if (!variant || !LSRProceduralWallpapersBundle()) return nil;
    Class configurationClass = NSClassFromString(@"PBUIWallpaperConfiguration");
    Class viewClass = NSClassFromString(@"PBUIBokehWallpaperView");
    SEL configurationInit = NSSelectorFromString(@"initWithVariant:type:");
    SEL viewInit = NSSelectorFromString(@"initWithFrame:configuration:variant:cacheGroup:delegate:options:");
    if (![configurationClass instancesRespondToSelector:configurationInit] || ![viewClass instancesRespondToSelector:viewInit]) return nil;
    // Variant 0 is the lock screen, wallpaper type 2 a procedural ("magic") wallpaper.
    id configuration = ((id (*)(id, SEL, long long, long long))objc_msgSend)([configurationClass alloc], configurationInit, 0, 2);
    ((void (*)(id, SEL, id))objc_msgSend)(configuration, NSSelectorFromString(@"setProceduralWallpaperInfo:"), @{
        @"kSBUIMagicWallpaperIdentifierKey": @"Bokeh",
        @"kSBUIMagicWallpaperPresetOptionsKey": @{ @"bokehVariant": variant },
    });
    UIView *view = ((id (*)(id, SEL, CGRect, id, long long, id, id, unsigned long long))objc_msgSend)(
        [viewClass alloc], viewInit, frame, configuration, 0, @"LockScreenRestore", nil, 0);
    objc_setAssociatedObject(view, kLSRBokehVariantKey, variant, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return view;
}

// Apple's thumbnail of a preset (NewBokeh-Dark-Blue_thumb, ...).
static inline UIImage *LSRLegacyBokehThumbnail(NSString *variant) {
    Class bokeh = [LSRProceduralWallpapersBundle() classNamed:@"Bokeh"];
    if (!variant || ![bokeh respondsToSelector:@selector(presetWallpaperOptions)]) return nil;
    NSArray *presets = ((id (*)(id, SEL))objc_msgSend)(bokeh, @selector(presetWallpaperOptions));
    for (NSDictionary *preset in presets) {
        if (![preset isKindOfClass:[NSDictionary class]] || ![preset[@"bokehVariant"] isEqual:variant]) continue;
        NSString *name = preset[@"thumbnailImageName"] ?: preset[@"kSBUIMagicWallpaperThumbnailNameKey"];
        return name ? [UIImage imageNamed:name inBundle:LSRProceduralWallpapersBundle() compatibleWithTraitCollection:nil] : nil;
    }
    return nil;
}

// Apple's animated bokeh view for a design: iOS 15's, else WallpaperKit's.
static inline UIView *LSRBokehView(NSString *dir, BOOL dark, CGRect frame) {
    UIView *view = LSRLegacyBokehView(dir, dark, frame) ?: LSRCollectionBokehView(dir, dark, frame);
    sLSRLiveBokehView = view;
    return view;
}

static inline void LSRSetBokehAnimating(UIView *view, BOOL animating) {
    if ([view respondsToSelector:@selector(setAnimationEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view, @selector(setAnimationEnabled:), animating);
    } else if ([view respondsToSelector:@selector(setWallpaperAnimationEnabled:)]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(view, @selector(setWallpaperAnimationEnabled:), animating);
    }
}

// A still frame, for thumbnails and for the lock screen's copies while it slides away.
static inline UIImage *LSRBokehImage(NSString *dir, BOOL dark, CGSize size) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    NSString *key = [NSString stringWithFormat:@"%@|%d|%.0fx%.0f", dir, dark, size.width, size.height];
    // The bubbles as they are on screen, when a view shows this design (never cached).
    NSString *variant = LSRLegacyBokehVariant(dir, dark);
    UIView *live = sLSRLiveBokehView;
    if (variant && live.window && [objc_getAssociatedObject(live, kLSRBokehVariantKey) isEqual:variant]
        && [live respondsToSelector:@selector(snapshotImage)]) {
        UIImage *snapshot = ((id (*)(id, SEL))objc_msgSend)(live, @selector(snapshotImage));
        if ([snapshot isKindOfClass:[UIImage class]] && snapshot.size.width > 0) return snapshot;
    }
    UIImage *image = [cache objectForKey:key];
    if (image) return image;
    // Apple's thumbnail of the preset, scaled to the size asked for.
    UIImage *presetThumbnail = LSRLegacyBokehThumbnail(variant);
    if (presetThumbnail.size.width > 0) {
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
        image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGFloat scale = MAX(size.width / presetThumbnail.size.width, size.height / presetThumbnail.size.height);
            CGSize drawn = CGSizeMake(presetThumbnail.size.width * scale, presetThumbnail.size.height * scale);
            [presetThumbnail drawInRect:CGRectMake((size.width - drawn.width) / 2, (size.height - drawn.height) / 2, drawn.width, drawn.height)];
        }];
        [cache setObject:image forKey:key];
        return image;
    }
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
    UIView *view = LSRCollectionBokehView(dir, dark, CGRectMake(0, 0, size.width, size.height));
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
