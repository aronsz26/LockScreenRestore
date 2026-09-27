// LockScreenRestore — iOS 15 "Settings > Wallpaper" page on iOS 16.
//
// Settings: iOS 16's page (a SwiftUI poster carousel started by WSWallpaperSettingsCoordinator)
// is replaced by the iOS 15 one: "Choose a New Wallpaper", a lock screen and a home screen
// preview side by side, and "Dark Appearance Dims Wallpaper". Choose opens iOS's own legacy
// album list (still shipped for iPadOS).
//
// SpringBoard: the home screen wallpaper is a poster rendered out of process, so there's no
// image of it to read. Instead SpringBoard saves a small screenshot of the home screen each
// time you unlock to it; the preview shows that (iOS 15's preview showed wallpaper + icons too).

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>

static NSString *const kLSRPaneDomain = @"com.aronsz26.lockscreenrestore";
static NSString *const kLSRPaneWallpapersDir = @"/var/mobile/Library/LockScreenRestore/Wallpapers";
static NSString *const kLSRHomePreviewPath = @"/var/mobile/Library/LockScreenRestore/HomePreview.jpg";

static NSString *LSRPanePrefsPath(void) {
    NSString *name = [kLSRPaneDomain stringByAppendingPathExtension:@"plist"];
    BOOL isDir = NO;
    NSString *rootless = @"/var/jb/var/mobile/Library/Preferences";
    if ([[NSFileManager defaultManager] fileExistsAtPath:rootless isDirectory:&isDir] && isDir) {
        return [rootless stringByAppendingPathComponent:name];
    }
    return [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:name];
}

static NSDictionary *LSRPanePrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:LSRPanePrefsPath()] ?: @{};
}

static BOOL LSRPanePrefEnabled(NSDictionary *prefs, NSString *key, BOOL fallback) {
    id value = prefs[key];
    return value ? [value boolValue] : fallback;
}

// Same as the settings bundle: through cfprefsd, and straight to the file SpringBoard reads.
static void LSRPaneSetPref(NSString *key, id value) {
    CFStringRef domain = (__bridge CFStringRef)kLSRPaneDomain;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, domain);
    CFPreferencesAppSynchronize(domain);
    NSMutableDictionary *prefs = [LSRPanePrefs() mutableCopy];
    if (value) prefs[key] = value;
    else [prefs removeObjectForKey:key];
    [prefs writeToFile:LSRPanePrefsPath() atomically:YES];
}

// Tells SpringBoard to reload the lock screen wallpaper (design or dimming changed).
static void LSRPaneNotifySpringBoard(void) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.aronsz26.lockscreenrestore/wallpaper"), NULL, NULL, true);
}

// The chosen design's folder, or the first one available (same rule as the lock screen).
static NSString *LSRPaneDesignDir(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *chosen = LSRPanePrefs()[@"wallpaperDesign"];
    if ([chosen isKindOfClass:[NSString class]] && chosen.length) {
        NSString *dir = [kLSRPaneWallpapersDir stringByAppendingPathComponent:chosen];
        if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"Light.heic"]]) return dir;
    }
    for (NSString *design in [[fm contentsOfDirectoryAtPath:kLSRPaneWallpapersDir error:nil]
                                 sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        NSString *dir = [kLSRPaneWallpapersDir stringByAppendingPathComponent:design];
        if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"Light.heic"]]) return dir;
    }
    return nil;
}

#pragma mark - Settings: previews

// A miniature lock screen: wallpaper, padlock, time, date, flashlight/camera and home bar,
// all sized relative to the preview so it reads like a scaled-down screen.
@interface LSRLockPreviewView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *padlock;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UIView *flashlight;
@property (nonatomic, strong) UIView *camera;
@property (nonatomic, strong) UIView *homeBar;
@end

@implementation LSRLockPreviewView

- (UIView *)_quickActionWithSymbol:(NSString *)symbol {
    UIView *circle = [UIView new];
    circle.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.tintColor = [UIColor whiteColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tag = 1;
    [circle addSubview:icon];
    return circle;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.backgroundColor = [UIColor blackColor];
        _imageView = [UIImageView new];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        [self addSubview:_imageView];
        _padlock = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
        _padlock.tintColor = [UIColor whiteColor];
        _padlock.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_padlock];
        _timeLabel = [UILabel new];
        _timeLabel.textColor = [UIColor whiteColor];
        _timeLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_timeLabel];
        _dateLabel = [UILabel new];
        _dateLabel.textColor = [UIColor whiteColor];
        _dateLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_dateLabel];
        _flashlight = [self _quickActionWithSymbol:@"flashlight.off.fill"];
        _camera = [self _quickActionWithSymbol:@"camera.fill"];
        [self addSubview:_flashlight];
        [self addSubview:_camera];
        _homeBar = [UIView new];
        _homeBar.backgroundColor = [UIColor whiteColor];
        [self addSubview:_homeBar];
    }
    return self;
}

- (void)refresh {
    NSDate *now = [NSDate date];
    NSDateFormatter *time = [NSDateFormatter new];
    time.locale = [NSLocale autoupdatingCurrentLocale];
    time.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:time.locale];
    // iOS 15's lock screen clock drops the AM/PM marker.
    NSString *timeText = [[[time stringFromDate:now] stringByReplacingOccurrencesOfString:time.AMSymbol withString:@""]
        stringByReplacingOccurrencesOfString:time.PMSymbol withString:@""];
    self.timeLabel.text = [timeText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSDateFormatter *date = [NSDateFormatter new];
    date.locale = [NSLocale autoupdatingCurrentLocale];
    date.dateFormat = @"EEEE, MMMM d";
    self.dateLabel.text = [date stringFromDate:now];

    NSString *dir = LSRPaneDesignDir();
    BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    NSString *path = [dir stringByAppendingPathComponent:dark ? @"Dark.heic" : @"Light.heic"];
    self.imageView.image = dir ? [UIImage imageWithContentsOfFile:path] : nil;
    [self setNeedsLayout];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (previous.userInterfaceStyle != self.traitCollection.userInterfaceStyle) [self refresh];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    // Proportions of the real 390 x 844 lock screen.
    CGFloat s = w / 390.0;
    self.layer.cornerRadius = 40.0 * s + 4.0;
    self.imageView.frame = self.bounds;
    self.padlock.frame = CGRectMake((w - 20 * s) / 2, 62 * s, 20 * s, 26 * s);
    self.timeLabel.font = [UIFont systemFontOfSize:80 * s weight:UIFontWeightThin];
    self.timeLabel.frame = CGRectMake(0, 100 * s, w, 90 * s);
    self.dateLabel.font = [UIFont systemFontOfSize:20 * s weight:UIFontWeightRegular];
    self.dateLabel.frame = CGRectMake(0, 190 * s, w, 26 * s);
    CGFloat button = 50 * s;
    self.flashlight.frame = CGRectMake(46 * s, h - 100 * s, button, button);
    self.camera.frame = CGRectMake(w - 46 * s - button, h - 100 * s, button, button);
    for (UIView *circle in @[self.flashlight, self.camera]) {
        circle.layer.cornerRadius = button / 2;
        [circle viewWithTag:1].frame = CGRectInset(circle.bounds, button * 0.25, button * 0.25);
    }
    self.homeBar.frame = CGRectMake((w - 139 * s) / 2, h - 13 * s, 139 * s, MAX(5 * s, 1.5));
    self.homeBar.layer.cornerRadius = self.homeBar.frame.size.height / 2;
}

@end

// Both previews side by side, centered, at the screen's aspect ratio.
@interface LSRWallpaperPreviewCell : UITableViewCell
@property (nonatomic, strong) LSRLockPreviewView *lockPreview;
@property (nonatomic, strong) UIImageView *homePreview;
@end

@implementation LSRWallpaperPreviewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _lockPreview = [LSRLockPreviewView new];
        [self.contentView addSubview:_lockPreview];
        _homePreview = [UIImageView new];
        _homePreview.contentMode = UIViewContentModeScaleAspectFill;
        _homePreview.clipsToBounds = YES;
        _homePreview.backgroundColor = [UIColor blackColor];
        _homePreview.layer.cornerCurve = kCACornerCurveContinuous;
        [self.contentView addSubview:_homePreview];
    }
    return self;
}

+ (CGFloat)previewHeight {
    return 290.0;
}

- (void)refresh {
    [self.lockPreview refresh];
    UIImage *home = [UIImage imageWithContentsOfFile:kLSRHomePreviewPath];
    // No screenshot yet (or the wallpaper changed since): the home screen's wallpaper itself.
    if (!home) {
        NSString *design = LSRPanePrefs()[@"homeWallpaperDesign"];
        BOOL dark = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        if ([design isKindOfClass:[NSString class]] && design.length) {
            home = [UIImage imageWithContentsOfFile:[[kLSRPaneWallpapersDir stringByAppendingPathComponent:design]
                stringByAppendingPathComponent:dark ? @"Dark.heic" : @"Light.heic"]];
        }
    }
    self.homePreview.image = home ?: self.lockPreview.imageView.image;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat h = [LSRWallpaperPreviewCell previewHeight];
    CGFloat w = round(h * MIN(screen.width, screen.height) / MAX(screen.width, screen.height));
    CGFloat gap = 12.0;
    CGFloat x = round((self.contentView.bounds.size.width - 2 * w - gap) / 2);
    CGFloat y = round((self.contentView.bounds.size.height - h) / 2);
    self.lockPreview.frame = CGRectMake(x, y, w, h);
    self.homePreview.frame = CGRectMake(x + w + gap, y, w, h);
    self.homePreview.layer.cornerRadius = 40.0 * (w / 390.0) + 4.0;
}

@end

#pragma mark - Settings: the page

@interface LSRWallpaperSettingsController : UITableViewController
@end

@implementation LSRWallpaperSettingsController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Wallpaper";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"row"];
    [self.tableView registerClass:[LSRWallpaperPreviewCell class] forCellReuseIdentifier:@"preview"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"When Dark Appearance is on, iPhone will dim your wallpaper depending on your ambient light.";
    return @"Dynamic wallpaper and perspective zoom are disabled when Low Power Mode is on.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row == 1 ? [LSRWallpaperPreviewCell previewHeight] + 32.0 : UITableViewAutomaticDimension;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row == 1) {
        LSRWallpaperPreviewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"preview" forIndexPath:indexPath];
        [cell refresh];
        return cell;
    }
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    if (indexPath.row == 0) {
        content.text = @"Choose a New Wallpaper";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        content.text = @"Dark Appearance Dims Wallpaper";
        UISwitch *toggle = [UISwitch new];
        toggle.on = LSRPanePrefEnabled(LSRPanePrefs(), @"dimWallpaperInDark", NO);
        [toggle addTarget:self action:@selector(_dimToggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.contentConfiguration = content;
    return cell;
}

- (void)_dimToggled:(UISwitch *)toggle {
    LSRPaneSetPref(@"dimWallpaperInDark", @(toggle.on));
    LSRPaneNotifySpringBoard();
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 0) [self _chooseNewWallpaper];
}

// iOS's legacy album list (iPadOS still uses it).
- (void)_chooseNewWallpaper {
    Class listClass = NSClassFromString(@"WallpaperSettings.WallpaperAlbumListController")
        ?: NSClassFromString(@"WallpaperAlbumListTableViewController");
    Class specClass = NSClassFromString(@"WallpaperAlbumListTableViewControllerPhoneSpec");
    if (!listClass || !specClass) return;
    UIViewController *list = nil;
    @try {
        list = ((id (*)(id, SEL, id))objc_msgSend)([listClass alloc], @selector(initWithSpec:), [specClass new]);
    } @catch (NSException *e) {
        list = nil;
    }
    if (!list) return;
    list.title = @"Choose";
    [self.navigationController pushViewController:list animated:YES];
}

@end

#pragma mark - Settings: wallpaper library (Dynamic / Stills / Live)

typedef NS_ENUM(NSInteger, LSRWallpaperKind) {
    LSRWallpaperKindDynamic,
    LSRWallpaperKindStills,
    LSRWallpaperKindLive,
};

static NSString *LSRWallpaperKindTitle(LSRWallpaperKind kind) {
    switch (kind) {
        case LSRWallpaperKindDynamic: return @"Dynamic";
        case LSRWallpaperKindStills: return @"Stills";
        case LSRWallpaperKindLive: return @"Live";
    }
    return @"";
}

// Every design folder with a Light.heic, in Finder order.
static NSArray<NSString *> *LSRPaneDesigns(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *designs = [NSMutableArray new];
    for (NSString *name in [[fm contentsOfDirectoryAtPath:kLSRPaneWallpapersDir error:nil]
                               sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if ([name hasPrefix:@"."]) continue;  // .Photo: a photo set from the library
        NSString *dir = [kLSRPaneWallpapersDir stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"Light.heic"]]) [designs addObject:name];
    }
    return designs;
}

// Stills: every design. Live: the ones that come with a video. Dynamic (iOS 15's moving bokeh
// wallpapers) has nothing yet.
static NSArray<NSString *> *LSRPaneDesignsOfKind(LSRWallpaperKind kind) {
    if (kind == LSRWallpaperKindDynamic) return @[];
    NSArray *designs = LSRPaneDesigns();
    if (kind == LSRWallpaperKindStills) return designs;
    NSMutableArray *live = [NSMutableArray new];
    for (NSString *design in designs) {
        NSString *video = [[kLSRPaneWallpapersDir stringByAppendingPathComponent:design] stringByAppendingPathComponent:@"Light.mov"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:video]) [live addObject:design];
    }
    return live;
}

// Downscaled decode (the HEICs are full screen resolution), cached.
static UIImage *LSRPaneThumbnail(NSString *design, NSString *variant, CGFloat maxPixels) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    NSString *key = [NSString stringWithFormat:@"%@/%@/%.0f", design, variant, maxPixels];
    UIImage *image = [cache objectForKey:key];
    if (image) return image;
    NSString *path = [[kLSRPaneWallpapersDir stringByAppendingPathComponent:design]
        stringByAppendingPathComponent:[variant stringByAppendingPathExtension:@"heic"]];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return nil;
    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixels),
    };
    CGImageRef cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!cgImage) return nil;
    image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    [cache setObject:image forKey:key];
    return image;
}

// Left half Light, right half Dark — how iOS 15 showed wallpapers that follow the appearance.
@interface LSRSplitThumbnailView : UIView
@property (nonatomic, copy) NSString *design;
@property (nonatomic, strong) UIImageView *lightView;
@property (nonatomic, strong) UIImageView *darkView;
@property (nonatomic, strong) UIImageView *badge;
@end

@implementation LSRSplitThumbnailView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor secondarySystemBackgroundColor];
        _lightView = [UIImageView new];
        _darkView = [UIImageView new];
        for (UIImageView *half in @[_lightView, _darkView]) {
            half.contentMode = UIViewContentModeScaleAspectFill;
            half.clipsToBounds = YES;
            [self addSubview:half];
        }
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightSemibold];
        _badge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"circle.righthalf.filled" withConfiguration:config]];
        _badge.tintColor = [UIColor whiteColor];
        _badge.layer.shadowOpacity = 0.4;
        _badge.layer.shadowRadius = 2;
        _badge.layer.shadowOffset = CGSizeZero;
        [self addSubview:_badge];
    }
    return self;
}

- (void)setDesign:(NSString *)design {
    _design = [design copy];
    self.lightView.image = nil;
    self.darkView.image = nil;
    if (!design) return;
    CGFloat pixels = 520;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *light = LSRPaneThumbnail(design, @"Light", pixels);
        UIImage *dark = LSRPaneThumbnail(design, @"Dark", pixels);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.design isEqualToString:design]) return;
            self.lightView.image = light;
            self.darkView.image = dark ?: light;
        });
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    // Each half shows its own half of the image, so together they look like one wallpaper.
    self.lightView.frame = CGRectMake(0, 0, w, h);
    self.lightView.layer.mask = self.lightView.layer.mask ?: [CALayer layer];
    self.lightView.layer.mask.backgroundColor = [UIColor blackColor].CGColor;
    self.lightView.layer.mask.frame = CGRectMake(0, 0, round(w / 2), h);
    self.darkView.frame = CGRectMake(0, 0, w, h);
    self.darkView.layer.mask = self.darkView.layer.mask ?: [CALayer layer];
    self.darkView.layer.mask.backgroundColor = [UIColor blackColor].CGColor;
    self.darkView.layer.mask.frame = CGRectMake(round(w / 2), 0, w - round(w / 2), h);
    CGSize badge = self.badge.intrinsicContentSize;
    self.badge.frame = CGRectMake(round((w - badge.width) / 2), h - badge.height - 8, badge.width, badge.height);
}

@end

// iOS 15's Dynamic thumbnail: soft colored bubbles on black.
static UIImage *LSRDynamicPlaceholder(CGSize size) {
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor blackColor] setFill];
        UIRectFill(CGRectMake(0, 0, size.width, size.height));
        NSArray *colors = @[[UIColor systemGreenColor], [UIColor systemPinkColor], [UIColor systemYellowColor],
                            [UIColor systemOrangeColor], [UIColor systemPurpleColor], [UIColor systemBlueColor], [UIColor systemRedColor]];
        srand48(15);
        for (int i = 0; i < 26; i++) {
            UIColor *color = [colors[i % colors.count] colorWithAlphaComponent:0.35 + drand48() * 0.5];
            CGFloat r = size.width * (0.04 + drand48() * 0.14);
            CGPoint c = CGPointMake(drand48() * size.width, drand48() * size.height);
            [color setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - r, c.y - r, 2 * r, 2 * r)] fill];
        }
    }];
}

@class LSRWallpaperGridController;

// The row of three at the top of Choose, like iOS 15.
@interface LSRCollectionsCell : UITableViewCell
@property (nonatomic, weak) UINavigationController *navigation;
+ (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation LSRCollectionsCell {
    NSArray<UIButton *> *_tiles;
    NSArray<UILabel *> *_labels;
}

static const CGFloat kLSRCollectionsInset = 16.0;
static const CGFloat kLSRCollectionsGap = 11.0;

+ (CGSize)tileSizeForWidth:(CGFloat)width {
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGFloat w = floor((width - 2 * kLSRCollectionsInset - 2 * kLSRCollectionsGap) / 3);
    return CGSizeMake(w, round(w * MAX(screen.width, screen.height) / MIN(screen.width, screen.height)));
}

+ (CGFloat)heightForWidth:(CGFloat)width {
    return 16 + [self tileSizeForWidth:width].height + 12 + 24 + 16;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        NSMutableArray *tiles = [NSMutableArray new], *labels = [NSMutableArray new];
        for (NSInteger kind = LSRWallpaperKindDynamic; kind <= LSRWallpaperKindLive; kind++) {
            UIButton *tile = [UIButton buttonWithType:UIButtonTypeCustom];
            tile.tag = kind;
            tile.clipsToBounds = YES;
            tile.imageView.contentMode = UIViewContentModeScaleAspectFill;
            tile.contentHorizontalAlignment = UIControlContentHorizontalAlignmentFill;
            tile.contentVerticalAlignment = UIControlContentVerticalAlignmentFill;
            tile.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
            tile.layer.borderColor = [UIColor separatorColor].CGColor;
            [tile addTarget:self action:@selector(_tapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.contentView addSubview:tile];
            [tiles addObject:tile];
            UILabel *label = [UILabel new];
            label.text = LSRWallpaperKindTitle((LSRWallpaperKind)kind);
            label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
            label.textColor = [UIColor labelColor];
            [self.contentView addSubview:label];
            [labels addObject:label];
        }
        _tiles = tiles;
        _labels = labels;
        [self _loadImages];
    }
    return self;
}

- (void)_loadImages {
    NSArray *stills = LSRPaneDesignsOfKind(LSRWallpaperKindStills);
    NSArray *live = LSRPaneDesignsOfKind(LSRWallpaperKindLive);
    NSString *stillDesign = stills.count > 1 ? stills[stills.count / 2] : stills.firstObject;
    NSString *liveDesign = live.firstObject;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        UIImage *still = stillDesign ? LSRPaneThumbnail(stillDesign, @"Dark", 520) : nil;
        UIImage *livePicture = liveDesign ? LSRPaneThumbnail(liveDesign, @"Light", 520) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_tiles[LSRWallpaperKindDynamic] setImage:LSRDynamicPlaceholder(CGSizeMake(120, 260)) forState:UIControlStateNormal];
            [self->_tiles[LSRWallpaperKindStills] setImage:still forState:UIControlStateNormal];
            [self->_tiles[LSRWallpaperKindLive] setImage:livePicture forState:UIControlStateNormal];
        });
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize tile = [LSRCollectionsCell tileSizeForWidth:self.contentView.bounds.size.width];
    for (NSUInteger i = 0; i < _tiles.count; i++) {
        CGFloat x = kLSRCollectionsInset + i * (tile.width + kLSRCollectionsGap);
        _tiles[i].frame = CGRectMake(x, 16, tile.width, tile.height);
        _labels[i].frame = CGRectMake(x, 16 + tile.height + 10, tile.width, 26);
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    for (UIButton *tile in _tiles) tile.layer.borderColor = [UIColor separatorColor].CGColor;
}

- (void)_tapped:(UIButton *)tile {
    Class gridClass = NSClassFromString(@"LSRWallpaperGridController");
    UIViewController *grid = ((id (*)(id, SEL, NSInteger))objc_msgSend)([gridClass alloc], @selector(initWithKind:), tile.tag);
    [self.navigation pushViewController:grid animated:YES];
}

@end

#pragma mark - Settings: preview and set

@interface SBSUIWallpaperPreviewViewController : UIViewController
- (instancetype)initWithImage:(UIImage *)image;
- (void)setImageWallpaperForLocations:(NSInteger)locations completionHandler:(void (^)(void))completion;
@end

typedef NS_OPTIONS(NSInteger, LSRWallpaperLocations) {
    LSRWallpaperLocationLockScreen = 1,
    LSRWallpaperLocationHomeScreen = 2,
};

// Full screen, like iOS 15: the wallpaper with the lock screen clock over it, Cancel and Set at
// the bottom. Live designs play while pressed.
@interface LSRWallpaperPreviewController : UIViewController
- (instancetype)initWithDesign:(NSString *)design live:(BOOL)live;
- (instancetype)initWithPhoto:(UIImage *)photo video:(NSURL *)video;
@end

// A photo from the library becomes the ".Photo" design: same layout as the others, the photo
// as both variants (and its Live Photo video, if any).
static NSString *const kLSRPhotoDesign = @".Photo";
static NSString *const kLSRHomePhotoDesign = @".HomePhoto";

// Writes a photo (and its Live Photo video) as a hidden design; NO if it couldn't be saved.
static BOOL LSRSavePhotoDesign(UIImage *photo, NSURL *video, NSString *name) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [kLSRPaneWallpapersDir stringByAppendingPathComponent:name];
    [fm removeItemAtPath:dir error:nil];
    if (!photo || ![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]) return NO;
    NSData *data = UIImageJPEGRepresentation(photo, 0.92);
    for (NSString *variant in @[@"Light", @"Dark"]) {
        if (![data writeToFile:[dir stringByAppendingPathComponent:[variant stringByAppendingPathExtension:@"heic"]] atomically:YES]) return NO;
        if (video) [fm copyItemAtPath:video.path toPath:[dir stringByAppendingPathComponent:[variant stringByAppendingPathExtension:@"mov"]] error:nil];
    }
    return YES;
}

// Lock screen: "wallpaperDesign", home screen: "homeWallpaperDesign" — SpringBoard shows them
// in its wallpaper window. A photo is saved as its own hidden design per screen.
static void LSRApplyWallpaper(NSString *design, UIImage *photo, NSURL *video, LSRWallpaperLocations locations) {
    if (locations & LSRWallpaperLocationLockScreen) {
        NSString *name = design;
        if (photo) name = LSRSavePhotoDesign(photo, video, kLSRPhotoDesign) ? kLSRPhotoDesign : nil;
        if (name) LSRPaneSetPref(@"wallpaperDesign", name);
    }
    if (locations & LSRWallpaperLocationHomeScreen) {
        NSString *name = design;
        if (photo) name = LSRSavePhotoDesign(photo, video, kLSRHomePhotoDesign) ? kLSRHomePhotoDesign : nil;
        if (name) {
            LSRPaneSetPref(@"homeWallpaperDesign", name);
            // The home screen screenshot is outdated now; the preview falls back to the design.
            [[NSFileManager defaultManager] removeItemAtPath:kLSRHomePreviewPath error:nil];
        }
    }
    LSRPaneNotifySpringBoard();
}

@implementation LSRWallpaperPreviewController {
    NSString *_design;
    BOOL _live;
    UIImage *_photo;
    NSURL *_photoVideo;
    UIImageView *_imageView;
    AVPlayer *_player;
    AVPlayerLayer *_playerLayer;
    UILabel *_timeLabel;
    UILabel *_dateLabel;
    UIButton *_cancel;
    UIButton *_set;
    UILabel *_hint;
}

- (instancetype)initWithDesign:(NSString *)design live:(BOOL)live {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _design = [design copy];
        _live = live;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (instancetype)initWithPhoto:(UIImage *)photo video:(NSURL *)video {
    if ((self = [self initWithDesign:kLSRPhotoDesign live:video != nil])) {
        _photo = photo;
        _photoVideo = video;
    }
    return self;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (NSString *)_variant {
    return self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? @"Dark" : @"Light";
}

- (NSString *)_pathFor:(NSString *)extension {
    if (_photo) return [extension isEqualToString:@"mov"] ? _photoVideo.path : nil;
    return [[kLSRPaneWallpapersDir stringByAppendingPathComponent:_design]
        stringByAppendingPathComponent:[[self _variant] stringByAppendingPathExtension:extension]];
}

- (UIButton *)_barButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.45];
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.cornerRadius = 14;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    _imageView = [[UIImageView alloc] initWithFrame:self.view.bounds];
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_imageView];
    _player = [AVPlayer new];
    _player.muted = YES;
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    _playerLayer.opacity = 0;
    [self.view.layer addSublayer:_playerLayer];

    _timeLabel = [UILabel new];
    _timeLabel.textColor = [UIColor whiteColor];
    _timeLabel.textAlignment = NSTextAlignmentCenter;
    _timeLabel.font = [UIFont systemFontOfSize:80 weight:UIFontWeightThin];
    [self.view addSubview:_timeLabel];
    _dateLabel = [UILabel new];
    _dateLabel.textColor = [UIColor whiteColor];
    _dateLabel.textAlignment = NSTextAlignmentCenter;
    _dateLabel.font = [UIFont systemFontOfSize:20];
    [self.view addSubview:_dateLabel];

    _cancel = [self _barButton:@"Cancel" action:@selector(_cancelTapped)];
    _set = [self _barButton:@"Set" action:@selector(_setTapped)];
    if (_live) {
        _hint = [UILabel new];
        _hint.text = @"Touch and hold to play";
        _hint.textColor = [UIColor whiteColor];
        _hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _hint.textAlignment = NSTextAlignmentCenter;
        [self.view addSubview:_hint];
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_pressed:)];
        press.minimumPressDuration = 0.25;
        [self.view addGestureRecognizer:press];
    }
    [self _reloadContent];
}

- (void)_reloadContent {
    _imageView.image = _photo ?: [UIImage imageWithContentsOfFile:[self _pathFor:@"heic"]];
    NSDateFormatter *time = [NSDateFormatter new];
    time.locale = [NSLocale autoupdatingCurrentLocale];
    time.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:time.locale];
    NSString *timeText = [[[time stringFromDate:[NSDate date]] stringByReplacingOccurrencesOfString:time.AMSymbol withString:@""]
        stringByReplacingOccurrencesOfString:time.PMSymbol withString:@""];
    _timeLabel.text = [timeText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSDateFormatter *date = [NSDateFormatter new];
    date.locale = [NSLocale autoupdatingCurrentLocale];
    date.dateFormat = @"EEEE, MMMM d";
    _dateLabel.text = [date stringFromDate:[NSDate date]];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if (previous.userInterfaceStyle != self.traitCollection.userInterfaceStyle) [self _reloadContent];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    _playerLayer.frame = self.view.bounds;
    _timeLabel.frame = CGRectMake(0, 100, w, 96);
    _dateLabel.frame = CGRectMake(0, 190, w, 28);
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGFloat buttonW = 110, buttonH = 44, y = h - safe.bottom - buttonH - 20;
    _cancel.frame = CGRectMake(24, y, buttonW, buttonH);
    _set.frame = CGRectMake(w - 24 - buttonW, y, buttonW, buttonH);
    _hint.frame = CGRectMake(0, y - 34, w, 20);
}

- (void)_pressed:(UILongPressGestureRecognizer *)press {
    if (press.state == UIGestureRecognizerStateBegan) {
        [_player replaceCurrentItemWithPlayerItem:[AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:[self _pathFor:@"mov"]]]];
        _playerLayer.opacity = 1;
        [_player play];
    } else if (press.state == UIGestureRecognizerStateEnded || press.state == UIGestureRecognizerStateCancelled) {
        [_player pause];
        _playerLayer.opacity = 0;
    }
}

- (void)_cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)_setTapped {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Set Lock Screen" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self _applyToLocations:LSRWallpaperLocationLockScreen];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Set Home Screen" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self _applyToLocations:LSRWallpaperLocationHomeScreen];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Set Both" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self _applyToLocations:LSRWallpaperLocationLockScreen | LSRWallpaperLocationHomeScreen];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = _set;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)_applyToLocations:(LSRWallpaperLocations)locations {
    LSRApplyWallpaper(_photo ? nil : _design, _photo, _photoVideo, locations);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - Settings: grid

@interface LSRWallpaperGridCell : UICollectionViewCell
@property (nonatomic, strong) LSRSplitThumbnailView *thumbnail;
@end

@implementation LSRWallpaperGridCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _thumbnail = [[LSRSplitThumbnailView alloc] initWithFrame:self.contentView.bounds];
        _thumbnail.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.contentView addSubview:_thumbnail];
    }
    return self;
}
@end

@interface LSRWallpaperGridController : UICollectionViewController
- (instancetype)initWithKind:(LSRWallpaperKind)kind;
@end

@implementation LSRWallpaperGridController {
    LSRWallpaperKind _kind;
    NSArray<NSString *> *_designs;
    UILabel *_emptyLabel;
}

- (instancetype)initWithKind:(LSRWallpaperKind)kind {
    UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = UIEdgeInsetsMake(12, 16, 16, 16);
    if ((self = [super initWithCollectionViewLayout:layout])) {
        _kind = kind;
        _designs = LSRPaneDesignsOfKind(kind);
        self.title = LSRWallpaperKindTitle(kind);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.collectionView.backgroundColor = [UIColor systemBackgroundColor];
    [self.collectionView registerClass:[LSRWallpaperGridCell class] forCellWithReuseIdentifier:@"wallpaper"];
    if (!_designs.count) {
        _emptyLabel = [UILabel new];
        _emptyLabel.text = @"No Wallpapers";
        _emptyLabel.textColor = [UIColor secondaryLabelColor];
        _emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
        _emptyLabel.textAlignment = NSTextAlignmentCenter;
        self.collectionView.backgroundView = _emptyLabel;
    }
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.collectionViewLayout;
    CGFloat available = self.collectionView.bounds.size.width - layout.sectionInset.left - layout.sectionInset.right;
    CGFloat w = floor((available - 2 * layout.minimumInteritemSpacing) / 3);
    CGSize screen = [UIScreen mainScreen].bounds.size;
    CGSize item = CGSizeMake(w, round(w * MAX(screen.width, screen.height) / MIN(screen.width, screen.height)));
    if (!CGSizeEqualToSize(layout.itemSize, item)) layout.itemSize = item;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _designs.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    LSRWallpaperGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"wallpaper" forIndexPath:indexPath];
    cell.thumbnail.design = _designs[indexPath.item];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    LSRWallpaperPreviewController *preview = [[LSRWallpaperPreviewController alloc]
        initWithDesign:_designs[indexPath.item] live:_kind == LSRWallpaperKindLive];
    [self presentViewController:preview animated:YES completion:nil];
}

@end

#pragma mark - Settings: replace iOS 16's page

@interface WSWallpaperSettingsCoordinator : NSObject
@property (nonatomic, readonly) UINavigationController *navigationController;
@end

%group LSRSettingsPane

%hook WSWallpaperSettingsCoordinator
- (void)start {
    UINavigationController *nav = self.navigationController;
    if (![nav isKindOfClass:[UINavigationController class]]) {
        %orig;
        return;
    }
    // Settings hands us a fresh, empty navigation controller and shows it once we've filled it.
    [nav setViewControllers:@[[LSRWallpaperSettingsController new]] animated:NO];
}
%end

// Choose: iOS's own album list, with our Dynamic / Stills / Live row in the (on iPhone empty)
// wallpaper collections row at the top.
@interface WallpaperAlbumListController : UIViewController
@end

%hook WallpaperAlbumListController
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = %orig;
    if (![cell isKindOfClass:NSClassFromString(@"WallpaperSettings.WallpaperCollectionsCell")]) return cell;
    LSRCollectionsCell *ours = [tableView dequeueReusableCellWithIdentifier:@"LSRCollections"]
        ?: [[LSRCollectionsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LSRCollections"];
    ours.navigation = ((UIViewController *)self).navigationController;
    return ours;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return [LSRCollectionsCell heightForWidth:tableView.bounds.size.width];
    return %orig;
}
%end

// Photos from an album open in iOS's legacy preview (SBSUIWallpaperPreviewViewController, which
// already has iOS 15's Move & Scale). On iOS 16 it draws the iOS 16 clock (SBFLockScreenDateView)
// over a baked-in picture of an old one (_SBSUIOrientedImageView: "18:41, Tuesday, January 9").
// Hide both and show the iOS 15 clock; "Set" puts the framed photo on our lock screen.
@interface SBSUIWallpaperPreviewView : UIView
@end

static const NSInteger kLSRPreviewClockTag = 0x15C10C;

static UIView *LSRPaneFindSubview(UIView *root, Class cls) {
    if (!cls) return nil;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:cls]) return sub;
        UIView *found = LSRPaneFindSubview(sub, cls);
        if (found) return found;
    }
    return nil;
}

%hook SBSUIWallpaperPreviewView
- (void)layoutSubviews {
    %orig;
    UIView *dateView = LSRPaneFindSubview(self, NSClassFromString(@"SBFLockScreenDateView"));
    if (!dateView) return;  // home screen preview: leave it alone
    dateView.hidden = YES;
    UIView *oldChrome = LSRPaneFindSubview(self, NSClassFromString(@"_SBSUIOrientedImageView"));
    oldChrome.hidden = YES;

    UIView *clock = [self viewWithTag:kLSRPreviewClockTag];
    if (!clock) {
        clock = [UIView new];
        clock.tag = kLSRPreviewClockTag;
        clock.userInteractionEnabled = NO;
        UILabel *time = [UILabel new];
        time.tag = 1;
        time.textColor = [UIColor whiteColor];
        time.textAlignment = NSTextAlignmentCenter;
        time.font = [UIFont systemFontOfSize:80 weight:UIFontWeightThin];
        UILabel *date = [UILabel new];
        date.tag = 2;
        date.textColor = [UIColor whiteColor];
        date.textAlignment = NSTextAlignmentCenter;
        date.font = [UIFont systemFontOfSize:20];
        [clock addSubview:time];
        [clock addSubview:date];
        [self insertSubview:clock aboveSubview:dateView];
    }
    CGFloat w = self.bounds.size.width;
    clock.frame = self.bounds;
    UILabel *time = [clock viewWithTag:1], *date = [clock viewWithTag:2];
    time.frame = CGRectMake(0, 100, w, 96);
    date.frame = CGRectMake(0, 190, w, 28);
    NSDateFormatter *timeFormat = [NSDateFormatter new];
    timeFormat.locale = [NSLocale autoupdatingCurrentLocale];
    timeFormat.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"jmm" options:0 locale:timeFormat.locale];
    NSString *timeText = [[[timeFormat stringFromDate:[NSDate date]] stringByReplacingOccurrencesOfString:timeFormat.AMSymbol withString:@""]
        stringByReplacingOccurrencesOfString:timeFormat.PMSymbol withString:@""];
    time.text = [timeText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSDateFormatter *dateFormat = [NSDateFormatter new];
    dateFormat.locale = [NSLocale autoupdatingCurrentLocale];
    dateFormat.dateFormat = @"EEEE, MMMM d";
    date.text = [dateFormat stringFromDate:[NSDate date]];
}
%end

static NSURL *LSRPreviewVideoURL(UIViewController *legacy) {
    id video = nil;
    @try {
        video = [legacy valueForKey:@"_video"];
    } @catch (NSException *e) {
        video = nil;
    }
    if ([video isKindOfClass:[NSURL class]]) return video;
    if ([video isKindOfClass:[AVURLAsset class]]) return ((AVURLAsset *)video).URL;
    return nil;
}

@interface SBSUIWallpaperPreviewViewController (LSRSet)
- (UIView *)_previewView;
- (void)setWallpaperForLocations:(NSInteger)locations completionHandler:(void (^)(void))completion;
@end

// The photo as currently framed with Move & Scale, at screen size.
static UIImage *LSRFramedPreviewImage(SBSUIWallpaperPreviewViewController *controller) {
    UIView *preview = [controller respondsToSelector:@selector(_previewView)] ? [controller _previewView] : controller.view;
    UIView *wallpaper = LSRPaneFindSubview(preview, NSClassFromString(@"PBUIWallpaperView")) ?: preview;
    CGRect bounds = wallpaper.bounds;
    if (CGRectIsEmpty(bounds)) return nil;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    return [[[UIGraphicsImageRenderer alloc] initWithBounds:bounds format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [wallpaper drawViewHierarchyInRect:bounds afterScreenUpdates:NO];
    }];
}

%hook SBSUIWallpaperPreviewViewController
- (void)setWallpaperForLocations:(NSInteger)locations completionHandler:(void (^)(void))completion {
    // Both screens are ours now (iOS 16 ignores this path for the home screen anyway).
    LSRApplyWallpaper(nil, LSRFramedPreviewImage(self), LSRPreviewVideoURL(self), locations);
    if (completion) completion();
}
%end

// Settings saves where you are when it goes to the background, asking every controller on the
// stack for Settings-specific details ours don't have; don't let that take the app down.
%hook PSURLManager
- (id)urlForCurrentNavStack {
    @try {
        return %orig;
    } @catch (NSException *e) {
        return nil;
    }
}
%end

%end // LSRSettingsPane

#pragma mark - SpringBoard: home screen preview

@interface SpringBoard : UIApplication
- (id)_accessibilityFrontMostApplication;
@end

// Only when the plain home screen is showing: no app, no lock screen / Notification Center, no
// banner, Control Center or app switcher on top.
static BOOL LSRHomeScreenIsClear(void) {
    SpringBoard *app = (SpringBoard *)[UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(_accessibilityFrontMostApplication)] && [app _accessibilityFrontMostApplication]) return NO;
    id lockManager = [NSClassFromString(@"SBLockScreenManager") respondsToSelector:@selector(sharedInstance)]
        ? ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"SBLockScreenManager"), @selector(sharedInstance)) : nil;
    if ([lockManager respondsToSelector:@selector(isUILocked)] && ((BOOL (*)(id, SEL))objc_msgSend)(lockManager, @selector(isUILocked))) return NO;
    Class coverSheet = NSClassFromString(@"SBCoverSheetPresentationManager");
    id presentation = [coverSheet respondsToSelector:@selector(sharedInstance)] ? ((id (*)(id, SEL))objc_msgSend)(coverSheet, @selector(sharedInstance)) : nil;
    if ([presentation respondsToSelector:@selector(isVisible)] && ((BOOL (*)(id, SEL))objc_msgSend)(presentation, @selector(isVisible))) return NO;
    for (UIWindow *window in ((NSArray *(*)(id, SEL, BOOL, BOOL))objc_msgSend)([UIWindow class],
             NSSelectorFromString(@"allWindowsIncludingInternalWindows:onlyVisibleWindows:"), YES, NO)) {
        if (window.hidden || window.alpha < 0.01) continue;
        NSString *name = NSStringFromClass([window class]);
        for (NSString *blocker in @[@"SBBannerWindow", @"SBControlCenterWindow", @"SBMainSwitcherWindow", @"SBCoverSheetWindow", @"SBAlertItemWindow"]) {
            if ([name isEqualToString:blocker]) return NO;
        }
    }
    return YES;
}

static void LSRSaveHomePreview(void) {
    if (!LSRHomeScreenIsClear()) return;
    static UIImage *(*createScreenImage)(void);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ createScreenImage = (UIImage *(*)(void))dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage"); });
    if (!createScreenImage) return;
    UIImage *screen = createScreenImage();
    if (!screen) return;
    // One pixel per point (a third of the screen's pixels) is plenty for a ~135pt wide preview.
    CGSize size = screen.size;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1.0;
    UIImage *small = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [screen drawInRect:CGRectMake(0, 0, size.width, size.height)];
        }];
    [UIImageJPEGRepresentation(small, 0.8) writeToFile:kLSRHomePreviewPath atomically:YES];
}

%group LSRHomePreview

%hook CSCoverSheetViewController
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    // Once the unlock animation has settled on the home screen.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LSRSaveHomePreview();
    });
}
%end

%end // LSRHomePreview

%ctor {
    NSString *process = [NSProcessInfo processInfo].processName;
    NSDictionary *prefs = LSRPanePrefs();
    if (!LSRPanePrefEnabled(prefs, @"wallpaperPaneEnabled", YES)) return;
    if ([process isEqualToString:@"Preferences"]) {
        // Loaded on demand by Settings; load it now so the coordinator class exists to hook.
        dlopen("/System/Library/PrivateFrameworks/Settings/WallpaperSettings.framework/WallpaperSettings", RTLD_NOW);
        %init(LSRSettingsPane, WallpaperAlbumListController = NSClassFromString(@"WallpaperSettings.WallpaperAlbumListController"));
    } else if ([process isEqualToString:@"SpringBoard"]) {
        %init(LSRHomePreview);
    }
}
