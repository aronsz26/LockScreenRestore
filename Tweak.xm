// LockScreenRestore — iOS 15 lock screen look on iOS 16 (rootless):
// thin white clock, date below it as "Sunday, September 27", focus pill under the date, big
// padlock that stays open after Face ID, notifications listed top-down under the clock, no
// vibrancy tint, no depth effect, no widgets, iOS 15 music player, live wallpapers.
//
// Sizes and positions adapt to the device: they come from the per-device values SpringBoard
// still carries from iOS 15 (SBFLockScreenMetrics) plus ratios measured against Apple's iOS 15
// lock screen, and are converted with the real font metrics at runtime.
//
// Independently switchable groups (Settings > LockScreenRestore, all on by default), applied at
// SpringBoard launch — the settings page has a respring button. The music player part runs in
// MediaRemoteUI, which restarts with SpringBoard.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreText/CoreText.h>
#import <AVFoundation/AVFoundation.h>
#import "LSRBokeh.h"

// Read straight from disk: NSUserDefaults in SpringBoard's constructor didn't see the values
// (cfprefsd). The settings page flushes to disk before its respring. Rootless jailbreaks
// (Dopamine) redirect tweak preferences under /var/jb, so look there first.
static NSString *const kLSRPrefsPaths[] = {
    @"/var/jb/var/mobile/Library/Preferences/com.aronsz26.lockscreenrestore.plist",
    @"/var/mobile/Library/Preferences/com.aronsz26.lockscreenrestore.plist",
};
static BOOL sLSRClockEnabled = YES;

// Debug builds log to LockScreenRestoreDebug.log.
#ifdef DEBUG
static void LSRDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void LSRDebugLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [NSString stringWithFormat:@"%.2f %@\n", CACurrentMediaTime(), [[NSString alloc] initWithFormat:format arguments:args]];
    va_end(args);
    // MediaRemoteUI is sandboxed: its log goes to its own tmp folder.
    BOOL springBoard = [[NSProcessInfo processInfo].processName isEqualToString:@"SpringBoard"];
    NSString *path = [springBoard ? @"/var/mobile/Documents" : NSTemporaryDirectory()
        stringByAppendingPathComponent:@"LockScreenRestoreDebug.log"];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}
#else
#define LSRDebugLog(...) do {} while (0)
#endif

@interface SBFLockScreenDateView : UIView
+ (UIFont *)timeFont;
- (void)setCustomTimeFont:(UIFont *)font;
- (UIFont *)customTimeFont;
@end

@interface BSUIVibrancyEffectView : UIView
@property (nonatomic) BOOL isEnabled;
@end

@interface CSProminentTextElementView : UIView
@property (nonatomic, strong) NSDate *date;
@property (readonly, nonatomic) UILabel *textLabel;
@end

@interface CSProminentTimeView : CSProminentTextElementView
@end

@interface CSProminentSubtitleDateView : CSProminentTextElementView
@end

@interface CSProminentDisplayView : UIView
@property (readonly, nonatomic) BSUIVibrancyEffectView *vibrancyEffectView;
@property (nonatomic, strong) CSProminentTimeView *timeView;
@property (nonatomic, strong) CSProminentTextElementView *transientSubtitleView;
@property (nonatomic, strong) CSProminentTextElementView *customSubtitleView;
@end

@interface _UIAnimatingLabel : UILabel
@end

@interface SBUIProudLockIconView : UIView
@end

@interface PBUIPosterFloatingLayerReplica : UIView
@end

#pragma mark - Per-device layout

// Ratios measured on Apple's iOS 15 lock screen (both reference renders agree):
// - the iOS 15 clock is 0.8x the size of iOS 16's clock font on the same device (80 vs 100pt)
// - time baseline sits 0.441 x clock size above the date baseline (0.615 x digit height)
// - SF digits are 0.717em tall
// - the padlock's center sits 0.531 x clock size above the top of the digits
// - the date's descenders reach 0.21em below its baseline; content under the date (the Focus
//   pill, whose item has 10pt of built-in top padding) starts right there
static const CGFloat kIOS15ClockScale = 0.8;
// Settings > Clock Size (1 = iOS 15's size), for anyone who wants it bigger or smaller.
static CGFloat sLSRClockSizeFactor = 1.0;
// Weights on the system font's weight axis (Thin 111, Light 274, Regular 400, Medium 510).
// Clock: Thin looked slightly too thin, 220 and 250 too thick, 170 matched. Date: Regular (170
// looked too thin, Medium too heavy). UIFontWeight values between the named weights get
// rounded to the nearest one, so the axis is set directly.
static const CGFloat kIOS15ClockWeightAxis = 170.0;
static const CGFloat kIOS15DateWeightAxis = 400.0;
static const uint32_t kFontAxisWeight = 'wght';
static const CGFloat kIOS15TimeBaselineAboveDate = 0.441;
static const CGFloat kSFDigitHeight = 0.717;
static const CGFloat kIOS15PadlockCenterAboveDigits = 0.531;
static const CGFloat kSFDescender = 0.21;
// iOS 15's clock on iPhones (SpringBoardFoundation 15.6.1: SBFLockScreenDateView timeFont,
// SBFDashBoardViewMetrics timeLabelBaselineY/searchClippingLineMaxY; checked against an
// iPhone 13 Pro and XR): a fixed size per screen, the time baseline at the status area plus the
// clock size but not above a minimum, and the date 36pt below the time.
static const CGFloat kIOS15FaceIDTimeBaselineMin = 175.0;
static const CGFloat kIOS15PlusTimeBaselineMin = 154.0;
static const CGFloat kIOS15HomeButtonTimeBaselineMin = 140.0;
static const CGFloat kIOS15FaceIDStatusArea = 92.0;
static const CGFloat kIOS15HomeButtonStatusArea = 68.0;
static const CGFloat kIOS15TimeToDate = 36.0;
static const CGFloat kIOS15FaceIDPadlockCenter = 76.0;
static const CGFloat kIOS15DateBaselineToList = 29.0;

// 0 = a screen iOS 15 didn't have (Dynamic Island): then 0.8x iOS 16's size.
static CGFloat LSRIOS15ClockSize(CGFloat screenHeight) {
    if (screenHeight == 568.0 || screenHeight == 667.0) return 70.0;  // SE, 8
    if (screenHeight == 736.0) return 86.0;                           // 8 Plus (measured on iOS 15: 62pt digits)
    if (screenHeight == 812.0 || screenHeight == 844.0) return 80.0;  // X, XS, 11 Pro, 12/13 (mini, Pro)
    if (screenHeight == 896.0 || screenHeight == 926.0) return 90.0;  // XR, XS Max, 11, Pro Max, 14 Plus
    return 0;
}

typedef struct {
    CGFloat clockFontSize;
    CGFloat dateFontSize;
    CGFloat timeBaselineY;   // screen coordinates, lock screen at rest
    CGFloat dateBaselineY;
    CGFloat padlockScale;
    CGFloat padlockDrop;     // from iOS 16's padlock position to the iOS 15 one
} LSRLayout;

static CGFloat LSRClassMetric(NSString *className, NSString *selectorName, CGFloat fallback) {
    Class cls = NSClassFromString(className);
    SEL sel = NSSelectorFromString(selectorName);
    if (!cls || ![cls respondsToSelector:sel]) return fallback;
    CGFloat value = ((CGFloat (*)(id, SEL))objc_msgSend)(cls, sel);
    return value > 0 ? value : fallback;
}

// Fallbacks are the values an iPhone 13 Pro reports.
static LSRLayout LSRCurrentLayout(void) {
    static LSRLayout layout;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class dateViewClass = NSClassFromString(@"SBFLockScreenDateView");
        UIFont *iOS16TimeFont = [dateViewClass respondsToSelector:@selector(timeFont)] ? [dateViewClass timeFont] : nil;
        CGFloat iOS16TimeSize = iOS16TimeFont.pointSize > 0 ? iOS16TimeFont.pointSize : 100.0;

        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGFloat screenHeight = MAX(screen.width, screen.height);
        BOOL phone = [UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPhone;
        BOOL faceID = phone && screenHeight >= 812.0;
        CGFloat iOS15Size = phone ? LSRIOS15ClockSize(screenHeight) : 0;
        layout.clockFontSize = round((iOS15Size > 0 ? iOS15Size : iOS16TimeSize * kIOS15ClockScale) * sLSRClockSizeFactor);
        layout.dateFontSize = LSRClassMetric(@"SBFLockScreenMetrics", @"dateLabelFontSize", 20.0);
        layout.padlockScale = 1.0 / LSRClassMetric(@"SBFLockScreenMetrics", @"proudLockScaleFactor", 0.5);

        CGFloat digitsTop, padlockCenter;
        if (phone) {
            // iOS 15's own placement (SBFDashBoardViewMetrics timeLabelBaselineY): below the
            // status area by the clock's size, but never above a per-device minimum. The metric
            // used on iPads below is off on some iPhones (iPhone X with 16.7) and missing on iOS 17.
            CGFloat minimum = faceID ? kIOS15FaceIDTimeBaselineMin
                : (screenHeight >= 736.0 ? kIOS15PlusTimeBaselineMin : kIOS15HomeButtonTimeBaselineMin);
            CGFloat statusArea = faceID ? kIOS15FaceIDStatusArea : kIOS15HomeButtonStatusArea;
            layout.timeBaselineY = MAX(minimum, statusArea + layout.clockFontSize);
            layout.dateBaselineY = layout.timeBaselineY + kIOS15TimeToDate * sLSRClockSizeFactor;
            digitsTop = layout.timeBaselineY - kSFDigitHeight * layout.clockFontSize;
            // Face ID iPhones: the padlock sits at the same height on all of them.
            padlockCenter = faceID ? kIOS15FaceIDPadlockCenter
                : digitsTop - kIOS15PadlockCenterAboveDigits * layout.clockFontSize;
        } else {
            layout.dateBaselineY = LSRClassMetric(@"SBFLockScreenMetrics", @"subtitleBaselineOffsetFromTopOfScreen", 211.0);
            layout.timeBaselineY = layout.dateBaselineY - kIOS15TimeBaselineAboveDate * layout.clockFontSize;
            digitsTop = layout.timeBaselineY - kSFDigitHeight * layout.clockFontSize;
            padlockCenter = digitsTop - kIOS15PadlockCenterAboveDigits * layout.clockFontSize;
        }
        CGFloat iOS16PadlockCenter = LSRClassMetric(@"SBFLockScreenMetrics", @"proudLockCenterFromTopOfScreen", 64.5);
        layout.padlockDrop = padlockCenter - iOS16PadlockCenter;
    });
    return layout;
}

static UIFont *LSRSystemFont(CGFloat size, CGFloat weightAxis) {
    UIFont *base = [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
    UIFontDescriptor *descriptor = [base.fontDescriptor fontDescriptorByAddingAttributes:@{
        (__bridge NSString *)kCTFontVariationAttribute: @{ @(kFontAxisWeight): @(weightAxis) },
    }];
    return [UIFont fontWithDescriptor:descriptor size:size];
}

// Cached: compared with isEqual: on every layout pass, and building them isn't free.
static UIFont *LSRClockFont(void) {
    static UIFont *font;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ font = LSRSystemFont(LSRCurrentLayout().clockFontSize, kIOS15ClockWeightAxis); });
    return font;
}

static UIFont *LSRDateFont(void) {
    static UIFont *font;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ font = LSRSystemFont(LSRCurrentLayout().dateFontSize, kIOS15DateWeightAxis); });
    return font;
}

static UIView *LSRFindSubview(UIView *root, Class cls) {
    if (!cls) return nil;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:cls]) return sub;
        UIView *found = LSRFindSubview(sub, cls);
        if (found) return found;
    }
    return nil;
}

#pragma mark - Group: iOS 15 clock (padlock, time, date, colors, no depth effect)

%group LSRClock

%hook SBFLockScreenDateView
- (void)layoutSubviews {
    // Only set when it differs: setting it schedules another layout pass, and doing it
    // unconditionally froze SpringBoard in an endless layout loop.
    if (fabs(self.customTimeFont.pointSize - LSRCurrentLayout().clockFontSize) > 0.5) {
        [self setCustomTimeFont:LSRClockFont()];
    }
    %orig;
}
%end

#pragma mark - Time and date positions
//
// iOS positions CSProminentTimeView / CSProminentSubtitleDateView via setFrame:/setCenter:.
// Transforms on top of that get mis-compensated by UIKit, so we substitute the position
// instead. Targets are baselines in screen coordinates; the full-screen CSProminentDisplayView
// is the reference, so the math also holds while the lock screen is being swiped away. Each
// label is vertically centered in its view, and its baseline sits one ascender below its top.

// Set while we assign positions ourselves, so nested setFrame:/setCenter: calls pass through.
static BOOL sLSRApplying = NO;

// The full-screen view holding time and date; the focus pill measures itself against it.
static __weak UIView *sLSRDisplayView = nil;

// Top for a view whose centered label (in `font`) should have its baseline at `baselineY`.
static BOOL LSRTargetTopForBaseline(UIView *view, CGFloat baselineY, UIFont *font, CGFloat height, CGFloat *outTop) {
    UIView *container = view.superview;
    UIView *display = container;
    Class displayClass = NSClassFromString(@"CSProminentDisplayView");
    while (display && ![display isKindOfClass:displayClass]) display = display.superview;
    if (!container || !display || !font) return NO;

    CGFloat containerY = [container convertPoint:CGPointZero toView:display].y;
    *outTop = baselineY - containerY - ((height - font.lineHeight) / 2.0 + font.ascender);
    return YES;
}

static BOOL LSRTargetTop(UIView *view, BOOL isTime, CGFloat height, CGFloat *outTop) {
    LSRLayout layout = LSRCurrentLayout();
    return LSRTargetTopForBaseline(view, isTime ? layout.timeBaselineY : layout.dateBaselineY,
                                   isTime ? LSRClockFont() : LSRDateFont(), height, outTop);
}

static void LSRMoveTop(UIView *view, CGFloat top) {
    CGFloat currentTop = view.center.y - view.bounds.size.height / 2.0;
    if (fabs(currentTop - top) < 0.25) return;
    CGPoint center = view.center;
    center.y = top + view.bounds.size.height / 2.0;
    sLSRApplying = YES;
    view.center = center;
    sLSRApplying = NO;
}

static void LSRPlaceView(UIView *view, BOOL isTime) {
    CGFloat top;
    if (view && LSRTargetTop(view, isTime, view.bounds.size.height, &top)) LSRMoveTop(view, top);
}

static CGRect LSRAdjustedFrame(UIView *view, BOOL isTime, CGRect frame) {
    CGFloat top;
    if (LSRTargetTop(view, isTime, frame.size.height, &top)) frame.origin.y = top;
    return frame;
}

static CGPoint LSRAdjustedCenter(UIView *view, BOOL isTime, CGPoint center) {
    CGFloat height = view.bounds.size.height;
    CGFloat top;
    if (LSRTargetTop(view, isTime, height, &top)) center.y = top + height / 2.0;
    return center;
}

%hook CSProminentTimeView
// Covers a label that already had its font before being added here (the setFont: hook below
// only applies once the label is inside this view). Only assign when different.
- (void)layoutSubviews {
    %orig;
    UILabel *label = self.textLabel;
    UIFont *font = LSRClockFont();
    if (label && ![label.font isEqual:font]) label.font = font;
}

- (void)setFrame:(CGRect)frame {
    if (sLSRApplying) {
        %orig;
        return;
    }
    sLSRApplying = YES;
    %orig(LSRAdjustedFrame(self, YES, frame));
    sLSRApplying = NO;
}

- (void)setCenter:(CGPoint)center {
    if (sLSRApplying) {
        %orig;
        return;
    }
    sLSRApplying = YES;
    %orig(LSRAdjustedCenter(self, YES, center));
    sLSRApplying = NO;
}
%end

#pragma mark - Date text: "Sunday, September 27", regular weight

static NSDateFormatter *LSRLongDateFormatter(void) {
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Fixed pattern rather than a localized template: English language + German region
        // would otherwise give "Sunday, 27. September".
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale autoupdatingCurrentLocale];
        formatter.dateFormat = @"EEEE, MMMM d";
    });
    return formatter;
}

// The view formats via its own _formatter ivar and writes the label directly, so we correct
// the label itself. Only assign when different, so the resulting relayout finds nothing to do.
static void LSRApplyIOS15Date(CSProminentSubtitleDateView *view) {
    UILabel *label = view.textLabel;
    if (!label) return;
    NSString *wanted = [LSRLongDateFormatter() stringFromDate:view.date ?: [NSDate date]];
    if (![label.text isEqualToString:wanted]) label.text = wanted;
    UIFont *font = LSRDateFont();
    if (![label.font isEqual:font]) label.font = font;
}

// Something re-assigns the short "Sun Sep 27" text bypassing the view's own methods, so the
// label's setters are the one reliable choke point — scoped to the label inside the date view.
static NSString *LSRIOS15DateTextForLabel(UILabel *label, NSString *incoming) {
    Class dateViewClass = NSClassFromString(@"CSProminentSubtitleDateView");
    if (!incoming.length || ![label.superview isKindOfClass:dateViewClass]) return incoming;
    CSProminentSubtitleDateView *dateView = (CSProminentSubtitleDateView *)label.superview;
    return [LSRLongDateFormatter() stringFromDate:dateView.date ?: [NSDate date]];
}

%hook _UIAnimatingLabel
- (void)setText:(NSString *)text {
    %orig(LSRIOS15DateTextForLabel(self, text));
}

// The time and date labels get iOS 16's fonts assigned directly (customTimeFont doesn't reach them).
- (void)setFont:(UIFont *)font {
    if ([self.superview isKindOfClass:NSClassFromString(@"CSProminentTimeView")]) font = LSRClockFont();
    else if ([self.superview isKindOfClass:NSClassFromString(@"CSProminentSubtitleDateView")]) font = LSRDateFont();
    %orig(font);
}

// The attributed text carries its own font, which wins over the label's: give the date iOS 15's.
- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (attributedText.length && [self.superview isKindOfClass:NSClassFromString(@"CSProminentSubtitleDateView")]) {
        NSMutableDictionary *attributes = [[attributedText attributesAtIndex:0 effectiveRange:NULL] mutableCopy];
        attributes[NSFontAttributeName] = LSRDateFont();
        attributedText = [[NSAttributedString alloc] initWithString:LSRIOS15DateTextForLabel(self, attributedText.string)
            attributes:attributes];
    }
    %orig(attributedText);
}
%end

%hook CSProminentSubtitleDateView
- (void)setFrame:(CGRect)frame {
    if (sLSRApplying) {
        %orig;
        return;
    }
    sLSRApplying = YES;
    %orig(LSRAdjustedFrame(self, NO, frame));
    sLSRApplying = NO;
}

- (void)setCenter:(CGPoint)center {
    if (sLSRApplying) {
        %orig;
        return;
    }
    sLSRApplying = YES;
    %orig(LSRAdjustedCenter(self, NO, center));
    sLSRApplying = NO;
}

- (void)setDate:(NSDate *)date {
    %orig;
    LSRApplyIOS15Date(self);
}

- (void)_updateLabel {
    %orig;
    LSRApplyIOS15Date(self);
}

- (void)layoutSubviews {
    %orig;
    LSRApplyIOS15Date(self);
}

- (void)didMoveToWindow {
    %orig;
    LSRApplyIOS15Date(self);
}
%end

#pragma mark - Solid white time/date (no vibrancy tint)
//
// iOS 16 draws the time/date through a BSUIVibrancyEffectView (the labels themselves sit at
// alpha 0 behind a vibrancy portal), which makes them tinted and slightly see-through.

%hook CSProminentDisplayView
- (void)layoutSubviews {
    %orig;
    sLSRDisplayView = self;
    BSUIVibrancyEffectView *vibrancy = self.vibrancyEffectView;
    if (vibrancy.isEnabled) vibrancy.isEnabled = NO;
    // Frames set before the views were fully in the hierarchy couldn't be converted; place
    // them again now that they are.
    LSRPlaceView(self.timeView, YES);
    LSRPlaceView(LSRFindSubview(self, NSClassFromString(@"CSProminentSubtitleDateView")), NO);

    // Temporary subtitles ("Swipe up to unlock", ...) cross-fade with the date in iOS 16; keep
    // them on the date's line instead of above the clock, where they'd hit the padlock.
    CGFloat dateBaselineY = LSRCurrentLayout().dateBaselineY;
    for (CSProminentTextElementView *subtitle in @[self.transientSubtitleView ?: [NSNull null],
                                                   self.customSubtitleView ?: [NSNull null]]) {
        if (![subtitle isKindOfClass:[UIView class]]) continue;
        CGFloat top;
        if (LSRTargetTopForBaseline(subtitle, dateBaselineY, subtitle.textLabel.font, subtitle.bounds.size.height, &top)) {
            LSRMoveTop(subtitle, top);
        }
    }
}
%end

%hook CSProminentDisplayViewController
- (void)setTextColor:(UIColor *)color {
    %orig([UIColor whiteColor]);
}

- (UIColor *)effectiveTextColor {
    return [UIColor whiteColor];
}
%end

// iOS 15 started the list (Focus pill, music player, notifications) 29pt below the date's
// baseline (SBFDashBoardViewMetrics listMinYForPage: = date baseline + dateBaselineToListY);
// iOS 16 starts it under its own, higher clock. The list view covers the whole screen, so its
// top inset is the start's height on screen.
%hook CSCombinedListViewController
- (UIEdgeInsets)_listViewDefaultContentInsets {
    UIEdgeInsets insets = %orig;
    if ([UIDevice currentDevice].userInterfaceIdiom != UIUserInterfaceIdiomPhone) return insets;
    CGFloat listTop = round(LSRCurrentLayout().dateBaselineY + kIOS15DateBaselineToList);
    if (insets.top < listTop) insets.top = listTop;
    return insets;
}
%end

#pragma mark - Big padlock that stays open after Face ID

%hook SBUIProudLockIconView
- (void)layoutSubviews {
    %orig;
    // The glyph is only centered by its parent, never re-framed, so a transform is safe.
    UIView *glyph = LSRFindSubview(self, NSClassFromString(@"BSUICAPackageView"));
    LSRLayout layout = LSRCurrentLayout();
    CGAffineTransform t = CGAffineTransformMake(layout.padlockScale, 0, 0, layout.padlockScale, 0, layout.padlockDrop);
    if (glyph && !CGAffineTransformEqualToTransform(glyph.transform, t)) glyph.transform = t;
}

// iOS 16 fades the padlock out and shrinks it (~0.7) after unlocking; iOS 15 kept it.
- (void)setAlpha:(CGFloat)alpha {
    %orig(1.0);
}

- (void)setTransform:(CGAffineTransform)transform {
    %orig(CGAffineTransformIdentity);
}
%end

%hook CSProudLockViewController
- (BOOL)_shouldApplyScaleAndBlurForAuthenticated {
    return NO;
}
%end

// No depth effect: the wallpaper's cut-out foreground layer is drawn above the clock; iOS 15
// had none.
%hook PBUIPosterFloatingLayerReplica
- (void)didMoveToWindow {
    %orig;
    self.hidden = YES;
}

- (void)setHidden:(BOOL)hidden {
    %orig(YES);
}
%end

#pragma mark - Charging battery in place of the clock
//
// On plug-in iOS fades out time and date and shows "60% Charged" over a big battery. iOS 16
// centers that on its own clock, which puts the text right under our bigger padlock; iOS 15
// showed it where the clock was. Shift it so it's centered on our time + date block. A
// translation on the charging view (full-screen, clear) moves label and battery together
// without fighting their Auto Layout; the getter/setter pair keeps it out of iOS's own
// transforms.

@interface CSBatteryChargingView : UIView
@end

@interface _CSSingleBatteryChargingView : CSBatteryChargingView
@end

@interface _CSDoubleBatteryChargingView : CSBatteryChargingView
@end

static const void *kLSRChargingShiftKey = &kLSRChargingShiftKey;

static CGFloat LSRChargingShift(UIView *view) {
    return [objc_getAssociatedObject(view, kLSRChargingShiftKey) doubleValue];
}

static void LSRUpdateChargingShift(UIView *view) {
    CGRect content = CGRectNull;
    for (UIView *sub in view.subviews) {
        if (sub.hidden || CGRectIsEmpty(sub.frame)) continue;
        content = CGRectUnion(content, sub.frame);
    }
    if (CGRectIsNull(content)) return;

    LSRLayout layout = LSRCurrentLayout();
    CGFloat clockTop = layout.timeBaselineY - kSFDigitHeight * layout.clockFontSize;
    CGFloat dateBottom = layout.dateBaselineY + kSFDescender * layout.dateFontSize;
    CGFloat shift = round((clockTop + dateBottom) / 2.0 - CGRectGetMidY(content));
    if (fabs(shift - LSRChargingShift(view)) < 0.5) return;

    CGAffineTransform own = view.transform;
    objc_setAssociatedObject(view, kLSRChargingShiftKey, @(shift), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.transform = own;
    LSRDebugLog(@"charging view %@ content %@ shift %.1f", NSStringFromClass([view class]),
        NSStringFromCGRect(content), shift);
}

%hook CSBatteryChargingView
- (void)didMoveToWindow {
    %orig;
    LSRUpdateChargingShift(self);
}

- (void)setTransform:(CGAffineTransform)transform {
    transform.ty += LSRChargingShift(self);
    %orig(transform);
}

- (CGAffineTransform)transform {
    CGAffineTransform t = %orig;
    t.ty -= LSRChargingShift(self);
    return t;
}
%end

%hook _CSSingleBatteryChargingView
- (void)layoutSubviews {
    %orig;
    LSRUpdateChargingShift(self);
}
%end

%hook _CSDoubleBatteryChargingView
- (void)layoutSubviews {
    %orig;
    LSRUpdateChargingShift(self);
}
%end

%end // LSRClock

#pragma mark - Group: iOS 15 focus pill
//
// iOS 16 still ships the iOS 15 focus pill (CSFocusActivityView/-Indicator, added as an item of
// the adjunct list under the clock); CSFocusActivityManager just decides to hide it. Re-enable
// it, move it below our date, and remove iOS 16's replacement: the focus name + symbol at the
// bottom of the notification list. The notification count in that bottom view is left alone.
//
// Where the pill lands depends on where iOS starts the adjunct list, which differs per device.
// So the pill measures its real distance to our date on every layout. Its item keeps iOS's
// height: growing it through preferredContentSize fed back into itself (iOS writes the value it
// reads back), so instead the item stops clipping. iOS leaves 26pt below each adjunct item, far
// more than the few points the pill sticks out.


@interface CSFocusActivityView : UIView
@end

%group LSRFocus

%hook CSFocusActivityManager
- (BOOL)_shouldHideFocusActivityIndicator {
    return NO;
}
%end

%hook NCNotificationListCountIndicatorView
- (void)setTitleString:(NSString *)titleString {
    %orig(nil);
}

- (void)setSymbolImageName:(NSString *)symbolImageName {
    %orig(nil);
}

// Without a focus symbol iOS falls back to a "circlebadge.fill" dot; iOS 15 had no symbol here.
- (void)layoutSubviews {
    %orig;
    Ivar ivar = class_getInstanceVariable(object_getClass(self), "_symbolImageView");
    UIView *symbolView = ivar ? object_getIvar(self, ivar) : nil;
    if (symbolView && !symbolView.hidden) symbolView.hidden = YES;
}
%end

%end // LSRFocus

#pragma mark - Group: iOS 15 notifications (listed from the top)
//
// iOS 16 lays the lock screen notification list out from the bottom up
// (NCNotificationListView.layoutFromBottom); iOS 15 listed them top-down under the date.

static const CGFloat kIOS15CardCornerRadius = 13.0;
static const CGFloat kIOS15CardInsetReduction = 4.0;

@interface NCNotificationShortLookView : UIView
- (CGFloat)_continuousCornerRadius;
- (void)_setContinuousCornerRadius:(CGFloat)radius;
@end

@interface NCNotificationSeamlessContentView : UIView
@end

static const CGFloat kIOS15ListInset = 8.0;
static const CGFloat kIOS16ListInset = 10.0;

@interface ACUISSizeDimensionRequest : NSObject
+ (instancetype)fixed:(CGFloat)value;
@property (readonly, nonatomic) CGFloat minimum;
@property (readonly, nonatomic) CGFloat maximum;
@end

@interface ACUISActivityItemMetricsRequest : NSObject <NSCopying>
@property (nonatomic, strong) ACUISSizeDimensionRequest *widthRequest;
@end

@interface ACUISActivityMetricsRequest : NSObject <NSCopying>
@property (nonatomic, copy) ACUISActivityItemMetricsRequest *lockScreenMetrics;
@end

@interface NCNotificationListSectionHeaderView : UIView
@property (nonatomic, weak) id delegate;
@end

@interface NCNotificationListView : UIScrollView
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic) CGFloat revealPercentage;
- (BOOL)isRevealed;
@end

// The history section ("Notification Centre" + X) fades its notifications with the reveal but
// leaves its header at full alpha: on iOS 16 that header waits below the screen's bottom edge
// until you swipe up. Listed from the top it sits right under the clock, so give the header
// the same reveal alpha as the notifications below it (iOS 15 only showed it after a swipe up).
static BOOL LSRIsHistoryHeader(UIView *header) {
    if (![header isKindOfClass:NSClassFromString(@"NCNotificationListSectionHeaderView")]) return NO;
    id section = ((NCNotificationListSectionHeaderView *)header).delegate;
    return [section respondsToSelector:@selector(isHistorySection)]
        && ((BOOL (*)(id, SEL))objc_msgSend)(section, @selector(isHistorySection));
}

// Highest alpha the history header may have right now: its list's reveal progress. Views
// outside a history list aren't limited.
static CGFloat LSRHistoryHeaderMaxAlpha(UIView *header) {
    NCNotificationListView *list = (NCNotificationListView *)header.superview;
    if (![list isKindOfClass:NSClassFromString(@"NCNotificationListView")] || list.headerView != header
        || !LSRIsHistoryHeader(header)) return 1.0;
    return list.isRevealed ? 1.0 : MIN(MAX(list.revealPercentage, 0.0), 1.0);
}

static void LSRApplyHistoryHeaderReveal(NCNotificationListView *list) {
    UIView *header = list.headerView;
    if (!LSRIsHistoryHeader(header)) return;
    CGFloat alpha = LSRHistoryHeaderMaxAlpha(header);
    if (fabs(header.alpha - alpha) > 0.001) header.alpha = alpha;
}

%group LSRNotifications

%hook NCNotificationListView
- (BOOL)layoutFromBottom {
    return NO;
}

- (void)setLayoutFromBottom:(BOOL)layoutFromBottom {
    %orig(NO);
}

- (void)layoutSubviews {
    %orig;
    LSRApplyHistoryHeaderReveal(self);
}

- (void)setRevealPercentage:(CGFloat)percentage {
    %orig;
    LSRApplyHistoryHeaderReveal(self);
}

- (void)setRevealed:(BOOL)revealed {
    %orig;
    LSRApplyHistoryHeaderReveal(self);
}
%end

// iOS also sets the header's alpha itself (e.g. fading it in while unlocking, with the history
// still closed); never let it rise above the reveal progress.
%hook NCNotificationListSectionHeaderView
- (void)setAlpha:(CGFloat)alpha {
    %orig(MIN(alpha, LSRHistoryHeaderMaxAlpha(self)));
}
%end


// iOS 15 cards had ~8pt side margins (measured 8.6pt incl. anti-aliasing); iOS 16 uses 10.
%hook CSCombinedListViewController
- (CGFloat)horizontalInsetMargin {
    return kIOS15ListInset;
}

%end

// Live Activities (like the music player) get a fixed width from the activity metrics, made
// for iOS 16's 10pt margins; widen them to fill the wider platter.
%hook ACUISActivityHostViewControllerFactory
+ (id)activityHostViewControllerWithDescriptor:(id)descriptor sceneType:(NSInteger)type metricsRequest:(ACUISActivityMetricsRequest *)request {
    ACUISActivityItemMetricsRequest *lockScreen = request.lockScreenMetrics;
    ACUISSizeDimensionRequest *width = lockScreen.widthRequest;
    LSRDebugLog(@"activity metrics request: width %.1f..%.1f", width.minimum, width.maximum);
    if (width && fabs(width.minimum - width.maximum) < 0.01) {
        CGFloat wider = width.maximum + 2.0 * (kIOS16ListInset - kIOS15ListInset);
        ACUISActivityMetricsRequest *adjusted = [request copy];
        ACUISActivityItemMetricsRequest *adjustedLockScreen = [lockScreen copy];
        adjustedLockScreen.widthRequest = [%c(ACUISSizeDimensionRequest) fixed:wider];
        adjusted.lockScreenMetrics = adjustedLockScreen;
        request = adjusted;
    }
    return %orig(descriptor, type, request);
}
%end

// Card shape, measured on Apple's iOS 15 lock screen: 13pt corners (iOS 16: 23.5), and every
// inner inset 4pt tighter — icon 10pt from the edges (iOS 16: 14), date 13pt from the right
// (17), one-line card 58pt tall (66). Instead of re-implementing iOS 16's layout, let it lay
// out (and measure) for a size 8pt larger than the real one, then view it through a bounds
// origin of (4,4) so everything shows 4pt up and left: every inset shrinks by exactly 4pt and
// the measured height follows. (iOS lays out from (0,0) and ignores the bounds' origin; moving
// the subviews themselves added up, since iOS doesn't re-place all of them every pass.)
%hook NCNotificationSeamlessContentView
- (void)_layoutSubviewInBounds:(CGRect)bounds measuringOnly:(CGSize *)measuredSize {
    CGFloat reduction = kIOS15CardInsetReduction;
    CGRect enlarged = bounds;
    enlarged.size.width += 2.0 * reduction;
    enlarged.size.height += 2.0 * reduction;
    %orig(enlarged, measuredSize);
    if (measuredSize) {
        measuredSize->width = MAX(0.0, measuredSize->width - 2.0 * reduction);
        measuredSize->height = MAX(0.0, measuredSize->height - 2.0 * reduction);
        return;
    }
    CGRect viewBounds = self.bounds;
    if (!CGPointEqualToPoint(viewBounds.origin, CGPointMake(reduction, reduction))) {
        viewBounds.origin = CGPointMake(reduction, reduction);
        self.bounds = viewBounds;
    }
    // iOS 16 top-aligns the icon with the title on taller cards; iOS 15 always centered it.
    CGFloat wantedCenterY = CGRectGetMidY(viewBounds);
    for (UIView *subview in self.subviews) {
        if (![NSStringFromClass([subview class]) containsString:@"BadgedIconView"]) continue;
        CGPoint center = subview.center;
        if (fabs(center.y - wantedCenterY) > 0.01) subview.center = CGPointMake(center.x, wantedCenterY);
    }
}
%end

%hook NCNotificationShortLookView
- (void)_setContinuousCornerRadius:(CGFloat)radius {
    %orig(kIOS15CardCornerRadius);
}

- (void)layoutSubviews {
    %orig;
    if (fabs(self._continuousCornerRadius - kIOS15CardCornerRadius) > 0.01) {
        [self _setContinuousCornerRadius:kIOS15CardCornerRadius];
    }
    // The dimming layer on cards stacked behind another one keeps its own radius.
    Ivar ivar = class_getInstanceVariable(object_getClass(self), "_stackDimmingOverlayView");
    UIView *dimming = ivar ? object_getIvar(self, ivar) : nil;
    if (dimming && fabs(dimming.layer.cornerRadius - kIOS15CardCornerRadius) > 0.01) {
        dimming.layer.cornerRadius = kIOS15CardCornerRadius;
        dimming.layer.cornerCurve = kCACornerCurveContinuous;
    }
}
%end

// iOS 15 only had the list. iOS 16's Settings > Notifications > Display As also offers Count
// and Stack (0 = List there): always use the list while this is on. The user's choice stays
// saved and applies again without the tweak.
%hook NCNotificationMasterList
- (void)setCurrentListDisplayStyleSetting:(NSUInteger)setting {
    %orig(0);
}

- (NSUInteger)currentListDisplayStyleSetting {
    return 0;
}
%end

%end // LSRNotifications

#pragma mark - Group: iOS 15 live wallpaper
//
// iOS 16 dropped live wallpapers. Apple's iOS 15 wallpapers come as a still plus a 3s video per
// appearance. We show them in our own view on top of iOS's wallpaper, inside the wallpaper
// window, switch between Light and Dark with the system appearance, and play the video while
// the lock screen is pressed (like iOS 15).
//
// The files aren't bundled (they're Apple's): <kLSRWallpapersDir>/<Design>/{Light,Dark}.{heic,mov}

static NSString *const kLSRWallpapersDir = @"/var/mobile/Library/LockScreenRestore/Wallpapers";
static NSString *sLSRWallpaperDesignDir = nil;
// Settings > Wallpaper "Set Home Screen"; nil = the home screen shows the lock screen's design.
static NSString *sLSRHomeDesignDir = nil;
// The wallpaper window serves both screens: the lock screen's design while the cover sheet is
// up, the home screen's once it goes away. (While it slides, the cover sheet carries its own
// copy of the lock screen wallpaper, see LSRCoverWithStill.)
static BOOL sLSRShowingLockScreen = YES;
// iOS 15's "Perspective Zoom": the wallpaper is drawn a bit larger and shifts as the iPhone
// tilts. Dynamic wallpapers move on their own and skip it.
static BOOL sLSRPerspectiveZoom = YES;
static const CGFloat kLSRPerspectiveMargin = 28.0;
// "Dark Appearance Dims Wallpaper" (Settings > Wallpaper).
static BOOL sLSRDimInDark = NO;
// Posted in SpringBoard after Settings picked another design or toggled dimming.
static NSString *const kLSRWallpaperReloadNotification = @"LSRWallpaperReload";
static NSMutableDictionary<NSString *, UIImage *> *sLSRStillCache;
// iOS 15 dimmed by roughly a quarter in the dark.
static const CGFloat kLSRDarkDimAlpha = 0.25;


static NSString *LSRWallpaperVariant(UITraitCollection *traits) {
    return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? @"Dark" : @"Light";
}

// Decoded once per variant: the same still is shown by several views (the wallpaper window and
// the copies iOS slides around during lock/unlock).
static UIImage *LSRWallpaperStillIn(NSString *dir, NSString *variant) {
    if (!dir) return nil;
    // Dynamic: a still of the bokeh (the lock screen's sliding copies can't animate).
    if (LSRIsBokehDesign(dir)) return LSRBokehImage(dir, [variant isEqualToString:@"Dark"], [UIScreen mainScreen].bounds.size);
    if (!sLSRStillCache) sLSRStillCache = [NSMutableDictionary new];
    NSString *path = [[dir stringByAppendingPathComponent:variant] stringByAppendingPathExtension:@"heic"];
    UIImage *image = sLSRStillCache[path];
    if (!image) {
        image = [UIImage imageWithContentsOfFile:path];
        if (image) sLSRStillCache[path] = image;
    }
    return image;
}

// The lock screen's still (what the cover sheet's own copies show).
static UIImage *LSRWallpaperStill(NSString *variant) {
    return LSRWallpaperStillIn(sLSRWallpaperDesignDir, variant);
}

// What the wallpaper window shows right now.
static NSString *LSRWindowDesignDir(void) {
    return !sLSRShowingLockScreen && sLSRHomeDesignDir ? sLSRHomeDesignDir : sLSRWallpaperDesignDir;
}

@interface LSRLiveWallpaperView : UIView
- (void)playVideo;
- (void)stopVideo;
@end

@implementation LSRLiveWallpaperView {
    UIView *_contentView;   // image, video and bokeh; moves with the device for Perspective Zoom
    UIImageView *_imageView;
    UIView *_bokehView;
    UIView *_dimView;
    AVPlayer *_player;
    AVPlayerLayer *_playerLayer;
    NSString *_loadedVariant;
    NSString *_loadedDir;
    NSURL *_videoURL;
    BOOL _wantsVideoVisible;
}

static void *kLSRReadyForDisplayContext = &kLSRReadyForDisplayContext;

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.clipsToBounds = YES;
        _contentView = [[UIView alloc] initWithFrame:self.bounds];
        [self addSubview:_contentView];
        _imageView = [[UIImageView alloc] initWithFrame:_contentView.bounds];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_contentView addSubview:_imageView];

        _player = [AVPlayer new];
        _player.muted = YES;
        _player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
        _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
        _playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        _playerLayer.opacity = 0.0;
        [_contentView.layer addSublayer:_playerLayer];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_videoDidEnd:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
        [_playerLayer addObserver:self forKeyPath:@"readyForDisplay" options:0 context:kLSRReadyForDisplayContext];
        _dimView = [[UIView alloc] initWithFrame:self.bounds];
        _dimView.backgroundColor = [UIColor blackColor];
        _dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_dimView];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_reload)
                                                     name:kLSRWallpaperReloadNotification object:nil];
        [self _loadCurrentVariant];
    }
    return self;
}

- (void)dealloc {
    [_playerLayer removeObserver:self forKeyPath:@"readyForDisplay" context:kLSRReadyForDisplayContext];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// Show the video layer only once it has a frame, so a fresh item never flashes black.
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kLSRReadyForDisplayContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_wantsVideoVisible || !self->_playerLayer.isReadyForDisplay) return;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self->_playerLayer.opacity = 1.0;
        [CATransaction commit];
    });
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BOOL perspective = sLSRPerspectiveZoom && !_bokehView;
    CGFloat margin = perspective ? kLSRPerspectiveMargin : 0.0;
    // Set center/bounds, not frame: the motion effects offset the center.
    _contentView.bounds = CGRectMake(0, 0, self.bounds.size.width + 2 * margin, self.bounds.size.height + 2 * margin);
    _contentView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _playerLayer.frame = _contentView.bounds;
    [CATransaction commit];
    _bokehView.frame = _contentView.bounds;
    [self _updatePerspective:perspective];
}

- (void)_updatePerspective:(BOOL)on {
    if (on == (_contentView.motionEffects.count > 0)) return;
    for (UIMotionEffect *effect in [_contentView.motionEffects copy]) [_contentView removeMotionEffect:effect];
    if (!on) return;
    UIInterpolatingMotionEffect *x = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x"
        type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    // Like iOS: the wallpaper moves against the tilt, so it seems to lie behind the screen.
    x.minimumRelativeValue = @(kLSRPerspectiveMargin);
    x.maximumRelativeValue = @(-kLSRPerspectiveMargin);
    UIInterpolatingMotionEffect *y = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y"
        type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    y.minimumRelativeValue = @(kLSRPerspectiveMargin);
    y.maximumRelativeValue = @(-kLSRPerspectiveMargin);
    UIMotionEffectGroup *group = [UIMotionEffectGroup new];
    group.motionEffects = @[x, y];
    [_contentView addMotionEffect:group];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self _loadCurrentVariant];
}

- (void)_reload {
    _loadedVariant = nil;
    _loadedDir = nil;
    [self _loadCurrentVariant];
}

- (void)_loadCurrentVariant {
    NSString *variant = LSRWallpaperVariant(self.traitCollection);
    // Above the video too, so a playing wallpaper stays dimmed.
    _dimView.alpha = sLSRDimInDark && [variant isEqualToString:@"Dark"] ? kLSRDarkDimAlpha : 0.0;
    [self bringSubviewToFront:_dimView];
    _dimView.layer.zPosition = 1;
    NSString *dir = LSRWindowDesignDir();
    if ([variant isEqualToString:_loadedVariant] && [dir isEqualToString:_loadedDir]) return;
    _loadedVariant = variant;
    _loadedDir = dir;
    [_bokehView removeFromSuperview];
    _bokehView = nil;
    if (LSRIsBokehDesign(dir)) {
        // Dynamic: Apple's animated bokeh, no video.
        _bokehView = LSRBokehView(dir, [variant isEqualToString:@"Dark"], _contentView.bounds);
        if (_bokehView) [_contentView insertSubview:_bokehView aboveSubview:_imageView];
        LSRSetBokehAnimating(_bokehView, YES);
        _imageView.image = _bokehView ? nil : LSRWallpaperStillIn(dir, variant);
        _videoURL = nil;
        [self setNeedsLayout];
        [self stopVideo];
        return;
    }
    [self setNeedsLayout];
    _imageView.image = LSRWallpaperStillIn(dir, variant);
    _videoURL = dir ? [NSURL fileURLWithPath:[[dir stringByAppendingPathComponent:variant] stringByAppendingPathExtension:@"mov"]] : nil;
    [self stopVideo];
}

// A fresh item every time: an item created before media services were reset (e.g. by a
// respring) stays "ready" but never plays (AVFoundationErrorDomain -11819).
- (void)playVideo {
    if (!_videoURL) return;
    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:_videoURL];
    [_player replaceCurrentItemWithPlayerItem:item];
    _wantsVideoVisible = YES;
    [_player play];
    LSRDebugLog(@"playVideo item=%@ status=%ld error=%@", item, (long)item.status, item.error);
}

- (void)stopVideo {
    _wantsVideoVisible = NO;
    [_player pause];
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.3];
    _playerLayer.opacity = 0.0;
    [CATransaction commit];
}

- (void)_videoDidEnd:(NSNotification *)notification {
    if (notification.object == _player.currentItem) [self stopVideo];
}
@end

static __weak LSRLiveWallpaperView *sLSRWallpaperView = nil;

@interface _SBWallpaperSecureWindow : UIWindow
@end

@interface CSCoverSheetViewController : UIViewController
@end

// While the lock screen slides away or back (unlock, lock, notification center, camera/today
// swipes), iOS draws a portal copy of its real wallpaper inside the lock screen window
// (SBWallpaperEffectView > PBUIWallpaperView > PBUIPortalReplicaEffectView). That's the old
// wallpaper flashing; cover those copies with our still too.
@interface LSRStillCoverView : UIImageView
@end

@implementation LSRStillCoverView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_reload)
                                                     name:kLSRWallpaperReloadNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_reload {
    self.image = LSRWallpaperStill(LSRWallpaperVariant(self.traitCollection));
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self _reload];
}
@end

static void LSRCoverWithStill(UIView *effectView) {
    // Only full-screen copies in the lock screen window: the same class also backs smaller
    // blurred surfaces elsewhere, which must keep their look.
    if (![effectView.window isKindOfClass:NSClassFromString(@"SBCoverSheetWindow")]) return;
    CGSize screen = [UIScreen mainScreen].bounds.size;
    if (fabs(effectView.bounds.size.width - screen.width) > 1 || fabs(effectView.bounds.size.height - screen.height) > 1) return;

    LSRStillCoverView *cover = nil;
    for (UIView *sub in effectView.subviews) {
        if ([sub isKindOfClass:[LSRStillCoverView class]]) cover = (LSRStillCoverView *)sub;
    }
    if (!cover) {
        cover = [[LSRStillCoverView alloc] initWithFrame:effectView.bounds];
        cover.contentMode = UIViewContentModeScaleAspectFill;
        cover.clipsToBounds = YES;
        cover.userInteractionEnabled = NO;
        cover.image = LSRWallpaperStill(LSRWallpaperVariant(effectView.traitCollection));
    }
    if (effectView.subviews.lastObject != cover) [effectView addSubview:cover];
    if (!CGRectEqualToRect(cover.frame, effectView.bounds)) cover.frame = effectView.bounds;
}

@interface SBWallpaperEffectView : UIView
@end

@interface SBDashBoardWallpaperEffectView : UIView
@end

@interface LSRWallpaperPressHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handlePress:(UILongPressGestureRecognizer *)recognizer;
@end

@implementation LSRWallpaperPressHandler
+ (instancetype)shared {
    static LSRWallpaperPressHandler *handler;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ handler = [LSRWallpaperPressHandler new]; });
    return handler;
}

- (void)handlePress:(UILongPressGestureRecognizer *)recognizer {
    LSRDebugLog(@"press state %ld, wallpaper view %@", (long)recognizer.state, sLSRWallpaperView);
    switch (recognizer.state) {
        case UIGestureRecognizerStateBegan:
            [sLSRWallpaperView playVideo];
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            [sLSRWallpaperView stopVideo];
            break;
        default:
            break;
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

// Only presses on the wallpaper itself, not on something that has its own press behaviour.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view; view = view.superview) {
        NSString *name = NSStringFromClass([view class]);
        BOOL blocked = [view isKindOfClass:[UIControl class]];
        for (NSString *fragment in @[@"ShortLook", @"LongLook", @"ListCell", @"PlatterView", @"AdjunctItem", @"QuickActions"]) {
            if ([name containsString:fragment]) blocked = YES;
        }
        if (blocked) {
            LSRDebugLog(@"touch on %@ ignored (inside %@)", NSStringFromClass([touch.view class]), name);
            return NO;
        }
    }
    LSRDebugLog(@"touch on %@ accepted", NSStringFromClass([touch.view class]));
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    LSRDebugLog(@"press should begin");
    return YES;
}
@end

%group LSRWallpaper

%hook _SBWallpaperSecureWindow
- (void)layoutSubviews {
    %orig;
    // Directly above iOS's wallpaper content (the window's first subview), below anything iOS
    // layers on top of it.
    LSRLiveWallpaperView *view = sLSRWallpaperView;
    if (!view || view.superview != self) {
        view = [[LSRLiveWallpaperView alloc] initWithFrame:self.bounds];
        sLSRWallpaperView = view;
    }
    UIView *wallpaperContent = self.subviews.firstObject;
    NSUInteger wantedIndex = wallpaperContent == view ? 0 : 1;
    if (view.superview != self || [self.subviews indexOfObject:view] != wantedIndex) {
        [self insertSubview:view aboveSubview:wallpaperContent];
    }
    if (!CGRectEqualToRect(view.frame, self.bounds)) view.frame = self.bounds;
}
%end

// iOS 16's lock screen long press opens the poster (lock screen) editor; on iOS 15 it played the
// live wallpaper. Replace it with our own press recognizer: play while held, back to the still
// on release. Presses on notifications and controls (flashlight, camera, ...) are left alone.
%hook CSCoverSheetViewController
- (void)viewDidLoad {
    %orig;
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc]
        initWithTarget:[LSRWallpaperPressHandler shared] action:@selector(handlePress:)];
    press.minimumPressDuration = 0.35;
    press.cancelsTouchesInView = NO;
    press.delegate = [LSRWallpaperPressHandler shared];
    [self.view addGestureRecognizer:press];
}

// Lock screen fully up: its design. Starting to go away: the home screen's design underneath.
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (sLSRShowingLockScreen) return;
    sLSRShowingLockScreen = YES;
    if (sLSRHomeDesignDir) [[NSNotificationCenter defaultCenter] postNotificationName:kLSRWallpaperReloadNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    if (!sLSRShowingLockScreen) return;
    sLSRShowingLockScreen = NO;
    if (sLSRHomeDesignDir) [[NSNotificationCenter defaultCenter] postNotificationName:kLSRWallpaperReloadNotification object:nil];
}

- (void)_setupPosterSwitcherGestureRecognizer {
}

- (void)_handlePosterSwitcherActivation:(id)sender {
}
%end

%hook SBWallpaperEffectView
- (void)layoutSubviews {
    %orig;
    LSRCoverWithStill(self);
}

- (void)didMoveToWindow {
    %orig;
    LSRCoverWithStill(self);
}
%end

%hook SBDashBoardWallpaperEffectView
- (void)layoutSubviews {
    %orig;
    LSRCoverWithStill(self);
}

- (void)didMoveToWindow {
    %orig;
    LSRCoverWithStill(self);
}
%end

%end // LSRWallpaper

// The home screen's design folder, nil when none was picked (then it shows the lock screen's).
static NSString *LSRResolveHomeDesignDir(NSDictionary *prefs) {
    NSString *chosen = prefs[@"homeWallpaperDesign"];
    if (LSRIsBokehDesign(chosen)) return chosen;
    if (![chosen isKindOfClass:[NSString class]] || !chosen.length) return nil;
    NSString *dir = [kLSRWallpapersDir stringByAppendingPathComponent:chosen];
    return [[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingPathComponent:@"Light.heic"]] ? dir : nil;
}

// The chosen design's folder, or the first one available; nil if there are none.
static NSString *LSRResolveWallpaperDesignDir(NSDictionary *prefs) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *chosen = prefs[@"wallpaperDesign"];
    if (LSRIsBokehDesign(chosen)) return chosen;  // a Dynamic wallpaper
    if ([chosen isKindOfClass:[NSString class]] && chosen.length) {
        NSString *dir = [kLSRWallpapersDir stringByAppendingPathComponent:chosen];
        if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"Light.heic"]]) return dir;
    }
    NSArray *designs = [[fm contentsOfDirectoryAtPath:kLSRWallpapersDir error:nil]
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *design in designs) {
        if ([design hasPrefix:@"."]) continue;  // .Photo only when picked
        NSString *dir = [kLSRWallpapersDir stringByAppendingPathComponent:design];
        if ([fm fileExistsAtPath:[dir stringByAppendingPathComponent:@"Light.heic"]]) return dir;
    }
    return nil;
}

static NSDictionary *LSRReadPrefs(void) {
    NSDictionary *prefs = nil;
    for (size_t i = 0; i < sizeof(kLSRPrefsPaths) / sizeof(kLSRPrefsPaths[0]) && !prefs; i++) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:kLSRPrefsPaths[i]];
    }
    return prefs;
}

// Settings > Wallpaper picked another design or toggled dimming: swap it in without a respring.
static void LSRWallpaperPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                     const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *prefs = LSRReadPrefs();
        NSString *dir = LSRResolveWallpaperDesignDir(prefs);
        if (dir) sLSRWallpaperDesignDir = dir;
        sLSRHomeDesignDir = LSRResolveHomeDesignDir(prefs);
        sLSRDimInDark = [prefs[@"dimWallpaperInDark"] boolValue];
        sLSRPerspectiveZoom = prefs[@"perspectiveZoom"] ? [prefs[@"perspectiveZoom"] boolValue] : YES;
        [sLSRStillCache removeAllObjects];
        [[NSNotificationCenter defaultCenter] postNotificationName:kLSRWallpaperReloadNotification object:nil];
    });
}

#pragma mark - Group: iOS 15 music player (runs in MediaRemoteUI)

// On iOS 16 the lock screen player is a Live Activity: MediaRemoteUI draws it in its own scene
// and SpringBoard only shows that scene inside a notification-list platter. MRUNowPlayingView
// has context 2 there. Its iOS 16 layout (artwork + title in one row, time labels beside the
// bar, AirPlay among the buttons, no volume) is replaced with iOS 15's, measured on Apple's
// iOS 15 lock screen (all values in pt from the platter's top left, 390pt wide screen):
//   artwork 100x100 at 16,16 (corner radius 3)
//   text column from x 128: route ("iPhone") baseline 52, title baseline 70, subtitle 87.8
//   AirPlay button centered 33.6 from the right edge, level with the artwork's center
//   progress bar center y 138.2, 16 from both edges, 4 thick, 8pt knob; times baseline 157.8, 12pt
//   buttons center y 191.1, 98 apart
//   volume bar center y 244.6 from x 58 to 59.6 before the right edge, 24pt knob; speaker icons
//   centered 37.6 / 37.3 from the edges
//   platter height 281
static const NSInteger kMRUContextCoverSheet = 2;
static const CGFloat kIOS15PlayerHeight = 281.0;
static const CGFloat kIOS15PlayerInset = 16.0;
static const CGFloat kIOS15ArtworkSize = 100.0;
static const CGFloat kIOS15ArtworkCornerRadius = 3.0;
// The playing app's icon in the artwork's corner (MediaControls 15.6.1, MRUArtworkView
// layoutSubviews, style 1): 16pt, 8pt in from the bottom right. iOS 16 dropped the icon view.
static const CGFloat kIOS15AppIconSize = 16.0;
static const CGFloat kIOS15AppIconInset = 8.0;
static const CGFloat kIOS15TextLeft = 128.0;
static const CGFloat kIOS15HeaderTop = 40.0;
static const CGFloat kIOS15HeaderHeight = 54.0;
static const CGFloat kIOS15RoutingCenterFromRight = 33.6;
static const CGFloat kIOS15RouteBaseline = 52.0;
static const CGFloat kIOS15TitleBaseline = 70.0;
static const CGFloat kIOS15SubtitleBaseline = 87.8;
static const CGFloat kIOS15TimeBarCenterY = 138.2;
static const CGFloat kIOS15TimeLabelBaseline = 157.8;
static const CGFloat kIOS15TimeLabelFontSize = 12.0;
static const CGFloat kIOS15TransportCenterY = 191.1;
static const CGFloat kIOS15TransportSpacing = 98.0;
static const CGFloat kIOS15VolumeCenterY = 244.6;
static const CGFloat kIOS15VolumeBarLeft = 58.0;
static const CGFloat kIOS15VolumeBarRightInset = 59.6;
static const CGFloat kIOS15VolumeMinIconCenter = 37.6;
static const CGFloat kIOS15VolumeMaxIconCenterFromRight = 37.3;
static const CGFloat kIOS15SliderThickness = 4.0;
static const CGFloat kIOS15TimeKnobSize = 8.0;
static const CGFloat kIOS15VolumeKnobSize = 24.0;
// iOS 15's glyphs were bigger: play/pause 34pt tall (iOS 16: 27.4), previous/next 35pt wide (32).
static const CGFloat kIOS15PlayGlyphScale = 1.25;
static const CGFloat kIOS15SkipGlyphScale = 1.1;

@interface MRUSlider : UIControl
@property (nonatomic, strong) UIView *minTrack;
@property (nonatomic) float value;
@property (nonatomic) float minimumValue;
@property (nonatomic) float maximumValue;
@end

@interface MRUArtworkView : UIControl
@property (nonatomic, strong) UIImage *iconImage;
@property (nonatomic, strong) UIImageView *artworkImageView;
@property (nonatomic, strong) UIView *artworkShadowView;
@property (nonatomic, strong) UIView *placeholderBackground;
@end

@interface MRUNowPlayingLabelView : UIControl
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, strong) UIView *routeLabel;
@property (nonatomic, strong) UIView *titleMarqueeView;
@property (nonatomic, strong) UIView *subtitleMarqueeView;
@property (nonatomic, strong) UIView *placeholderMarqueeView;
@end

@interface MRUNowPlayingHeaderView : UIView
@property (nonatomic, strong) MRUNowPlayingLabelView *labelView;
@property (nonatomic, strong) UIView *routingButton;
@property (nonatomic, strong) UIView *waveformView;
@property (nonatomic) BOOL showRoutingButton;
@property (nonatomic) BOOL showTransportButton;
@property (nonatomic) BOOL showWaveform;
@end

@interface MRUNowPlayingTimeControlsView : UIView
@property (nonatomic, strong) MRUSlider *slider;
@property (nonatomic, strong) UILabel *elapsedTimeLabel;
@property (nonatomic, strong) UILabel *remainingTimeLabel;
@property (nonatomic, strong) UILabel *liveLabel;
@end

@interface MRUNowPlayingTransportControlsView : UIView
@property (nonatomic, strong) UIView *leftButton;
@property (nonatomic, strong) UIView *centerButton;
@property (nonatomic, strong) UIView *rightButton;
@property (nonatomic) BOOL showRoutingButton;
@end

@interface MRUNowPlayingVolumeControlsView : UIView
@property (nonatomic, strong) MRUSlider *slider;
@property (nonatomic, strong) UIImageView *minImageView;
@property (nonatomic, strong) UIImageView *maxImageView;
@end

@interface MRUNowPlayingView : UIView
@property (nonatomic) NSInteger context;
@property (nonatomic) BOOL showVolumeControlsView;
@property (nonatomic, strong) MRUArtworkView *artworkView;
@property (nonatomic, strong) MRUNowPlayingHeaderView *headerView;
@property (nonatomic, strong) MRUNowPlayingTimeControlsView *timeControlsView;
@property (nonatomic, strong) MRUNowPlayingTransportControlsView *transportControlsView;
@property (nonatomic, strong) MRUNowPlayingVolumeControlsView *volumeControlsView;
@end

@interface MRUNowPlayingInfo : NSObject
@property (nonatomic, strong) NSString *artist;
@property (nonatomic, strong) NSString *album;
@end

@interface MRUMetadataController : NSObject
@property (readonly, nonatomic) MRUNowPlayingInfo *nowPlayingInfo;
@property (readonly, copy, nonatomic) NSString *bundleID;
@end

@interface MRUNowPlayingController : NSObject
@property (readonly, nonatomic) MRUMetadataController *metadataController;
@end

@interface MRUNowPlayingViewController : UIViewController
@property (nonatomic) NSInteger context;
@property (nonatomic, strong) MRUNowPlayingController *controller;
@property (nonatomic) BOOL showArtworkView;
@end

static BOOL LSRIsLockScreenPlayer(MRUNowPlayingView *view) {
    return view.context == kMRUContextCoverSheet;
}

// The lock screen player a view belongs to, or nil.
static MRUNowPlayingView *LSRLockScreenPlayerFor(UIView *view) {
    static Class playerClass;
    if (!playerClass) playerClass = NSClassFromString(@"MRUNowPlayingView");
    for (UIView *v = view; v; v = v.superview) {
        if ([v isKindOfClass:playerClass]) return LSRIsLockScreenPlayer((MRUNowPlayingView *)v) ? (MRUNowPlayingView *)v : nil;
    }
    return nil;
}

// Only touch frames that differ, so our layout never re-triggers a layout pass.
static void LSRSetFrame(UIView *view, CGRect frame) {
    if (!view) return;
    CGRect current = view.frame;
    if (fabs(current.origin.x - frame.origin.x) > 0.01 || fabs(current.origin.y - frame.origin.y) > 0.01
        || fabs(current.size.width - frame.size.width) > 0.01 || fabs(current.size.height - frame.size.height) > 0.01) {
        view.frame = frame;
    }
}

static void LSRSetCenter(UIView *view, CGPoint center) {
    if (!view) return;
    CGSize size = view.bounds.size;
    LSRSetFrame(view, CGRectMake(center.x - size.width / 2.0, center.y - size.height / 2.0, size.width, size.height));
}

// Top of a label (or a view holding one) whose text baseline should sit at `baseline`.
static CGFloat LSRTopForBaseline(CGFloat baseline, UIFont *font) {
    return baseline - (font ? font.ascender : 0.0);
}

static UILabel *LSRFirstLabelIn(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) return (UILabel *)view;
    for (UIView *sub in view.subviews) {
        UILabel *found = LSRFirstLabelIn(sub);
        if (found) return found;
    }
    return nil;
}

// iOS 15's white round knob on the progress and volume bars (iOS 16 has none).
static const void *kLSRKnobKey = &kLSRKnobKey;

static void LSRUpdateKnob(MRUSlider *slider) {
    UIView *knob = objc_getAssociatedObject(slider, kLSRKnobKey);
    MRUNowPlayingView *player = LSRLockScreenPlayerFor(slider);
    if (!player) {
        knob.hidden = YES;
        return;
    }
    BOOL volume = [slider.superview isKindOfClass:NSClassFromString(@"MRUNowPlayingVolumeControlsView")];
    CGFloat size = volume ? kIOS15VolumeKnobSize : kIOS15TimeKnobSize;
    if (!knob) {
        knob = [[UIView alloc] initWithFrame:CGRectMake(0, 0, size, size)];
        knob.userInteractionEnabled = NO;
        knob.backgroundColor = [UIColor whiteColor];
        knob.layer.cornerRadius = size / 2.0;
        if (volume) {
            knob.layer.shadowColor = [UIColor blackColor].CGColor;
            knob.layer.shadowOpacity = 0.2f;
            knob.layer.shadowRadius = 4.0;
            knob.layer.shadowOffset = CGSizeMake(0, 1);
        }
        objc_setAssociatedObject(slider, kLSRKnobKey, knob, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (knob.superview != slider) [slider addSubview:knob];
    if (slider.subviews.lastObject != knob) [slider bringSubviewToFront:knob];
    knob.hidden = NO;

    CGFloat range = slider.maximumValue - slider.minimumValue;
    CGFloat fraction = range > 0 ? (slider.value - slider.minimumValue) / range : 0.0;
    fraction = MIN(MAX(fraction, 0.0), 1.0);
    CGRect bounds = slider.bounds;
    // The knob stays inside the bar's ends, like iOS 15's.
    CGFloat x = size / 2.0 + fraction * MAX(0.0, bounds.size.width - size);
    LSRSetCenter(knob, CGPointMake(x, CGRectGetMidY(bounds)));
}

static void LSRUpdateSliderTouchTarget(MRUSlider *slider) {
    // The bar is thinner than iOS 16's; keep it easy to grab.
    if (slider.bounds.size.height < 20.0) {
        CGFloat pad = -(22.0 - slider.bounds.size.height / 2.0);
        UIEdgeInsets insets = UIEdgeInsetsMake(pad, -8.0, pad, -8.0);
        if ([slider respondsToSelector:@selector(setHitRectInset:)]) {
            ((void (*)(id, SEL, UIEdgeInsets))objc_msgSend)(slider, @selector(setHitRectInset:), insets);
        }
    }
}

// What iOS 15 showed that iOS 16's lock screen layout hides: volume slider, route label
// ("iPhone"), AirPlay in the header instead of among the buttons, no waveform/mini play button.
static void LSREnforcePlayerVisibility(MRUNowPlayingView *player) {
    if (!player.showVolumeControlsView) player.showVolumeControlsView = YES;
    MRUNowPlayingHeaderView *header = player.headerView;
    if (!header.showRoutingButton) header.showRoutingButton = YES;
    if (header.showTransportButton) header.showTransportButton = NO;
    if (header.showWaveform) header.showWaveform = NO;
    MRUNowPlayingTransportControlsView *transport = player.transportControlsView;
    if (transport.showRoutingButton) transport.showRoutingButton = NO;
}


@interface MRUAssetsProvider : NSObject
+ (instancetype)sharedAssetsProvider;
- (UIImage *)applicationIconForBundleIdentifier:(NSString *)bundleID;
@end

static const void *kLSRAppIconViewKey = &kLSRAppIconViewKey;

// Hands the playing app's icon to the artwork view, which iOS 16 still has a property for.
static void LSRUpdateAppIcon(MRUNowPlayingViewController *controller) {
    UIView *view = controller.viewIfLoaded;
    if (![view isKindOfClass:NSClassFromString(@"MRUNowPlayingView")]) return;
    MRUArtworkView *artworkView = ((MRUNowPlayingView *)view).artworkView;
    if (![artworkView respondsToSelector:@selector(setIconImage:)]) return;
    NSString *bundleID = [controller.controller.metadataController respondsToSelector:@selector(bundleID)]
        ? controller.controller.metadataController.bundleID : nil;
    static NSString *lastBundleID;
    static UIImage *lastIcon;
    if (bundleID.length && ![bundleID isEqualToString:lastBundleID]) {
        UIImage *icon = nil;
        Class provider = NSClassFromString(@"MRUAssetsProvider");
        @try {
            if ([provider respondsToSelector:@selector(sharedAssetsProvider)]) {
                id shared = [provider sharedAssetsProvider];
                if ([shared respondsToSelector:@selector(applicationIconForBundleIdentifier:)]) {
                    icon = [shared applicationIconForBundleIdentifier:bundleID];
                }
            }
        } @catch (NSException *e) {
            icon = nil;
        }
        if (![icon isKindOfClass:[UIImage class]]) icon = nil;
        lastBundleID = [bundleID copy];
        lastIcon = icon;
    }
    UIImage *icon = bundleID.length ? lastIcon : nil;
    if (artworkView.iconImage != icon) {
        artworkView.iconImage = icon;
        [artworkView setNeedsLayout];
    }
}

%group LSRMediaPlayer

%hook MRUNowPlayingViewController
- (BOOL)showRouteLabel {
    if (self.context == kMRUContextCoverSheet) return YES;
    return %orig;
}

// iOS 16 shows only the artist under the title; iOS 15 showed "Artist — Album".
- (void)updateNowPlayingInfo {
    %orig;
    if (self.context != kMRUContextCoverSheet) return;
    LSRUpdateAppIcon(self);
    MRUNowPlayingInfo *info = self.controller.metadataController.nowPlayingInfo;
    if (!info.artist.length || !info.album.length) return;
    UIView *view = self.viewIfLoaded;
    if (![view isKindOfClass:NSClassFromString(@"MRUNowPlayingView")]) return;
    MRUNowPlayingLabelView *labelView = ((MRUNowPlayingView *)view).headerView.labelView;
    if (![labelView.subtitle isEqualToString:info.artist]) return;
    labelView.subtitle = [NSString stringWithFormat:@"%@ \u2014 %@", info.artist, info.album];
}

// Tapping the artwork turns on iOS 16's full-screen album art (the lock screen shows the cover,
// the player hides its own). iOS 15 had no such thing and our layout keeps a gap where the
// artwork was. Don't turn it on; still let a tap turn it off for anyone already in it.
- (void)didSelectArtworkView:(id)artworkView {
    if (self.context == kMRUContextCoverSheet && self.showArtworkView) return;
    %orig;
}
%end

%hook MRUNowPlayingView
- (CGSize)sizeThatFits:(CGSize)size {
    CGSize fitting = %orig;
    if (!LSRIsLockScreenPlayer(self)) return fitting;
    return CGSizeMake(fitting.width, kIOS15PlayerHeight);
}

- (void)layoutSubviews {
    if (LSRIsLockScreenPlayer(self)) LSREnforcePlayerVisibility(self);
    %orig;
    if (!LSRIsLockScreenPlayer(self)) return;

    CGFloat width = self.bounds.size.width;
    CGFloat inset = kIOS15PlayerInset;
    LSRSetFrame(self.artworkView, CGRectMake(inset, inset, kIOS15ArtworkSize, kIOS15ArtworkSize));
    CGFloat headerRight = width - kIOS15RoutingCenterFromRight + 22.0;
    LSRSetFrame(self.headerView, CGRectMake(kIOS15TextLeft, kIOS15HeaderTop,
        headerRight - kIOS15TextLeft, kIOS15HeaderHeight));
    LSRSetFrame(self.timeControlsView, CGRectMake(inset, kIOS15TimeBarCenterY - 22.0, width - 2.0 * inset, 44.0));
    LSRSetFrame(self.transportControlsView, CGRectMake(0, kIOS15TransportCenterY - 22.0, width, 44.0));
    LSRSetFrame(self.volumeControlsView, CGRectMake(0, kIOS15VolumeCenterY - 22.0, width, 44.0));
    self.volumeControlsView.alpha = 1.0;
}
%end

%hook MRUArtworkView
- (void)layoutSubviews {
    %orig;
    if (!LSRLockScreenPlayerFor(self)) return;
    for (UIView *view in @[self.artworkImageView ?: [NSNull null], self.artworkShadowView ?: [NSNull null],
                           self.placeholderBackground ?: [NSNull null]]) {
        if (![view isKindOfClass:[UIView class]]) continue;
        if (fabs(view.layer.cornerRadius - kIOS15ArtworkCornerRadius) > 0.01) view.layer.cornerRadius = kIOS15ArtworkCornerRadius;
    }

    UIImageView *iconView = objc_getAssociatedObject(self, kLSRAppIconViewKey);
    UIImage *icon = [self respondsToSelector:@selector(iconImage)] ? self.iconImage : nil;
    if (!iconView && icon) {
        iconView = [UIImageView new];
        iconView.contentMode = UIViewContentModeScaleAspectFill;
        iconView.clipsToBounds = YES;
        iconView.layer.cornerRadius = round(kIOS15AppIconSize * 0.225 * 3.0) / 3.0;
        iconView.layer.cornerCurve = kCACornerCurveContinuous;
        iconView.accessibilityIgnoresInvertColors = YES;
        objc_setAssociatedObject(self, kLSRAppIconViewKey, iconView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self addSubview:iconView];
    }
    if (!iconView) return;
    if (iconView.image != icon) iconView.image = icon;
    UIImageView *artwork = self.artworkImageView;
    BOOL showsArtwork = artwork && !artwork.hidden && artwork.image;
    iconView.hidden = !icon || !showsArtwork;
    CGRect frame = showsArtwork ? artwork.frame : self.bounds;
    LSRSetFrame(iconView, CGRectMake(CGRectGetMaxX(frame) - kIOS15AppIconSize - kIOS15AppIconInset,
                                     CGRectGetMaxY(frame) - kIOS15AppIconSize - kIOS15AppIconInset,
                                     kIOS15AppIconSize, kIOS15AppIconSize));
    [self bringSubviewToFront:iconView];
}
%end

// Header: labels on the left, AirPlay on the right, level with the artwork's center.
%hook MRUNowPlayingHeaderView
- (void)layoutSubviews {
    %orig;
    if (!LSRLockScreenPlayerFor(self)) return;
    CGSize size = self.bounds.size;
    CGFloat artworkCenterY = kIOS15PlayerInset + kIOS15ArtworkSize / 2.0 - kIOS15HeaderTop;
    LSRSetFrame(self.routingButton, CGRectMake(size.width - 44.0, artworkCenterY - 22.0, 44.0, 44.0));
    LSRSetFrame(self.labelView, CGRectMake(0, 0, size.width - 52.0, size.height));
    // iOS 16's lock screen layout never shows this button, so nothing fades it in.
    if (self.routingButton.alpha < 1.0) self.routingButton.alpha = 1.0;
    // iOS 16's "playing" waveform dots above the AirPlay button.
    if (!self.waveformView.hidden) self.waveformView.hidden = YES;
}

- (void)updateVisibility {
    %orig;
    if (LSRLockScreenPlayerFor(self) && self.routingButton.alpha < 1.0) self.routingButton.alpha = 1.0;
}
%end

// Three lines: route, title, subtitle.
%hook MRUNowPlayingLabelView
- (void)layoutSubviews {
    %orig;
    if (!LSRLockScreenPlayerFor(self)) return;
    CGFloat width = self.bounds.size.width;
    UIView *route = self.routeLabel;
    if (route) {
        UILabel *label = LSRFirstLabelIn(route);
        CGFloat height = route.bounds.size.height > 0 ? route.bounds.size.height : 13.33;
        LSRSetFrame(route, CGRectMake(0, LSRTopForBaseline(kIOS15RouteBaseline - kIOS15HeaderTop, label.font),
            MIN(width, MAX(route.bounds.size.width, [route sizeThatFits:CGSizeMake(width, height)].width)), height));
        if (route.alpha < 1.0) route.alpha = 1.0;
    }
    for (UIView *line in @[self.titleMarqueeView ?: [NSNull null], self.placeholderMarqueeView ?: [NSNull null]]) {
        if (![line isKindOfClass:[UIView class]]) continue;
        LSRSetFrame(line, CGRectMake(0, LSRTopForBaseline(kIOS15TitleBaseline - kIOS15HeaderTop, LSRFirstLabelIn(line).font),
            width, line.bounds.size.height));
    }
    UIView *subtitle = self.subtitleMarqueeView;
    if (subtitle) {
        LSRSetFrame(subtitle, CGRectMake(0, LSRTopForBaseline(kIOS15SubtitleBaseline - kIOS15HeaderTop, LSRFirstLabelIn(subtitle).font),
            width, subtitle.bounds.size.height));
    }
}
%end

// Progress bar across the full width, times below it.
%hook MRUNowPlayingTimeControlsView
- (void)layoutSubviews {
    %orig;
    if (!LSRLockScreenPlayerFor(self)) return;
    CGSize size = self.bounds.size;
    CGFloat barCenterY = size.height / 2.0;
    LSRSetFrame(self.slider, CGRectMake(0, barCenterY - kIOS15SliderThickness / 2.0, size.width, kIOS15SliderThickness));
    CGFloat baseline = barCenterY + (kIOS15TimeLabelBaseline - kIOS15TimeBarCenterY);
    for (UILabel *label in @[self.elapsedTimeLabel ?: [NSNull null], self.remainingTimeLabel ?: [NSNull null],
                             self.liveLabel ?: [NSNull null]]) {
        if (![label isKindOfClass:[UILabel class]]) continue;
        if (fabs(label.font.pointSize - kIOS15TimeLabelFontSize) > 0.01) {
            label.font = [label.font fontWithSize:kIOS15TimeLabelFontSize];
        }
        CGSize fit = [label sizeThatFits:CGSizeMake(size.width, CGFLOAT_MAX)];
        CGFloat x = 0;
        if (label == self.remainingTimeLabel) x = size.width - fit.width;
        else if (label == self.liveLabel) x = (size.width - fit.width) / 2.0;
        LSRSetFrame(label, CGRectMake(x, LSRTopForBaseline(baseline, label.font), fit.width, fit.height));
    }
}
%end

// Previous, play/pause, next — 98pt apart around the center.
%hook MRUNowPlayingTransportControlsView
- (void)layoutSubviews {
    %orig;
    if (!LSRLockScreenPlayerFor(self)) return;
    CGSize size = self.bounds.size;
    CGFloat centerX = size.width / 2.0, centerY = size.height / 2.0;
    LSRSetCenter(self.leftButton, CGPointMake(centerX - kIOS15TransportSpacing, centerY));
    LSRSetCenter(self.centerButton, CGPointMake(centerX, centerY));
    LSRSetCenter(self.rightButton, CGPointMake(centerX + kIOS15TransportSpacing, centerY));
    // Scales the glyph around the button's center without touching the button's frame.
    NSArray *buttons = @[self.leftButton ?: [NSNull null], self.centerButton ?: [NSNull null], self.rightButton ?: [NSNull null]];
    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIView *button = buttons[i];
        if (![button isKindOfClass:[UIView class]]) continue;
        CGFloat scale = i == 1 ? kIOS15PlayGlyphScale : kIOS15SkipGlyphScale;
        CATransform3D wanted = CATransform3DMakeScale(scale, scale, 1.0);
        if (!CATransform3DEqualToTransform(button.layer.sublayerTransform, wanted)) button.layer.sublayerTransform = wanted;
    }
}
%end

// Speaker icons at both ends, volume bar between them.
%hook MRUNowPlayingVolumeControlsView
- (void)layoutSubviews {
    %orig;
    if (!LSRLockScreenPlayerFor(self)) return;
    CGSize size = self.bounds.size;
    CGFloat centerY = size.height / 2.0;
    LSRSetCenter(self.minImageView, CGPointMake(kIOS15VolumeMinIconCenter, centerY));
    LSRSetCenter(self.maxImageView, CGPointMake(size.width - kIOS15VolumeMaxIconCenterFromRight, centerY));
    LSRSetFrame(self.slider, CGRectMake(kIOS15VolumeBarLeft, centerY - kIOS15SliderThickness / 2.0,
        size.width - kIOS15VolumeBarLeft - kIOS15VolumeBarRightInset, kIOS15SliderThickness));
}
%end

// iOS 15's played part of the bar is solid white (iOS 16: half transparent).
static void LSRBrightenSliderFill(MRUSlider *slider) {
    UIView *fill = slider.minTrack;
    if (fill && fill.alpha < 1.0) fill.alpha = 1.0;
}

%hook MRUSlider
- (void)layoutSubviews {
    %orig;
    if (!LSRLockScreenPlayerFor(self)) return;
    LSRUpdateSliderTouchTarget(self);
    LSRBrightenSliderFill(self);
    LSRUpdateKnob(self);
}

- (void)updateVisualStyling {
    %orig;
    if (LSRLockScreenPlayerFor(self)) LSRBrightenSliderFill(self);
}

- (void)setValue:(float)value {
    %orig;
    if (LSRLockScreenPlayerFor(self)) LSRUpdateKnob(self);
}

- (void)setValue:(float)value animated:(BOOL)animated {
    %orig;
    if (LSRLockScreenPlayerFor(self)) LSRUpdateKnob(self);
}
%end

%end // LSRMediaPlayer

// SpringBoard side: the platter around the player (and any other Live Activity) gets iOS 15's
// 13pt corners like the notification cards; iOS 16 uses 23.5 for the platter, its material
// and the hosted scene view inside it.
@interface NCNotificationListSupplementaryHostingView : UIView
@end

static void LSRRoundActivityPlatter(UIView *view, NSUInteger depth) {
    CGFloat radius = view.layer.cornerRadius;
    if (radius > kIOS15CardCornerRadius + 0.01 && radius < 30.0) {
        view.layer.cornerRadius = kIOS15CardCornerRadius;
        view.layer.cornerCurve = kCACornerCurveContinuous;
    }
    if (depth >= 10) return;
    for (UIView *sub in view.subviews) LSRRoundActivityPlatter(sub, depth + 1);
}

%group LSRMediaPlatter

%hook NCNotificationListSupplementaryHostingView
- (void)_setContinuousCornerRadius:(CGFloat)radius {
    %orig(kIOS15CardCornerRadius);
}

- (void)layoutSubviews {
    %orig;
    LSRRoundActivityPlatter(self, 0);
}
%end

%end // LSRMediaPlatter

#pragma mark - Unlock animation

// iOS 15's unlock transition. Both versions drive it from CSCoverSheetTransitionsSettings, one
// block of settings per case (same or different lock/home wallpaper, first or later swipe, over
// an app). These are iOS 15.6.1's defaults (CoverSheet's setDefaultValues and
// setDefaultValuesForParallaxAndBlur): the home screen wallpaper follows the swipe with
// parallax, and the sheet only blurs when the wallpapers differ. (iOS 16's getters hide some
// of these again where its own transition doesn't use them.)
static void LSRSetTransitionValue(id settings, NSString *key, id value) {
    if (!settings) return;
    // Straight to the setter: BOOL or double, depending on the key.
    SEL setter = NSSelectorFromString([NSString stringWithFormat:@"set%@%@:",
        [[key substringToIndex:1] uppercaseString], [key substringFromIndex:1]]);
    NSMethodSignature *signature = [settings methodSignatureForSelector:setter];
    if (!signature || signature.numberOfArguments != 3) return; // A key iOS 16 doesn't have.
    const char *type = [signature getArgumentTypeAtIndex:2];
    if (type[0] == 'd') {
        ((void (*)(id, SEL, double))objc_msgSend)(settings, setter, [value doubleValue]);
    } else if (type[0] == 'B' || type[0] == 'c') {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(settings, setter, [value boolValue]);
    }
}

static void LSRApplyIOS15TransitionBase(id t) {
    NSDictionary *base = @{
        @"blursPanel": @YES, @"blurRadius": @20.0, @"blurStart": @0.0, @"blurEnd": @0.4,
        @"blurEndReducedTransparency": @0.275,
        @"fadesContent": @YES, @"maxContentAlpha": @1.0, @"contentFadeStart": @0.2, @"contentFadeEnd": @0.7,
        @"darkensContent": @YES, @"darkeningColorWhite": @0.0, @"darkeningColorAlpha": @0.2,
        @"darkeningStart": @0.0, @"darkeningEnd": @0.5,
        @"panelWallpaper": @NO, @"trackingWallpaper": @YES, @"trackingWallpaperParallaxFactor": @0.5,
        @"revealWallpaper": @NO, @"fadePanelWallpaper": @NO, @"fadePanelWallpaperStart": @0.0,
        @"fadePanelWallpaperEnd": @1.0, @"iconsFlyIn": @YES,
        // iOS 16 only: iOS 15 never zoomed the wallpaper here.
        @"scaleWallpaper": @NO,
    };
    [base enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        LSRSetTransitionValue(t, key, value);
    }];
}

// Different wallpapers: the lock screen wallpaper travels with the sheet, fades and blurs.
static void LSRApplyIOS15DifferentWallpaper(id t) {
    NSDictionary *values = @{
        @"blursPanel": @YES, @"panelWallpaper": @YES, @"trackingWallpaper": @YES,
        @"trackingWallpaperParallaxFactor": @0.3, @"fadePanelWallpaper": @YES,
        @"fadePanelWallpaperStart": @0.2, @"fadePanelWallpaperEnd": @1.0,
        @"fadesContent": @YES, @"contentFadeStart": @0.2, @"contentFadeEnd": @0.7,
    };
    [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        LSRSetTransitionValue(t, key, value);
    }];
}

static void LSRApplyIOS15Transitions(id settings) {
    SEL sels[] = {
        @selector(sameWallpaperInitialTransitionSettings), @selector(differentWallpaperInitialTransitionSettings),
        @selector(sameWallpaperSubsequentTransitionSettings), @selector(differentWallpaperSubsequentTransitionSettings),
        @selector(overAppTransitionSettings),
    };
    id t[5] = {nil};
    for (int i = 0; i < 5; i++) {
        if ([settings respondsToSelector:sels[i]]) t[i] = ((id (*)(id, SEL))objc_msgSend)(settings, sels[i]);
        LSRApplyIOS15TransitionBase(t[i]);
    }
    LSRSetTransitionValue(settings, @"tension", @300.0);
    LSRSetTransitionValue(settings, @"friction", @34.0);

    // Same wallpaper, first swipe: no blur.
    LSRSetTransitionValue(t[0], @"blursPanel", @NO);
    // Different wallpapers, first swipe.
    LSRApplyIOS15DifferentWallpaper(t[1]);
    // Same wallpaper, later swipes.
    LSRSetTransitionValue(t[2], @"blursPanel", @NO);
    LSRSetTransitionValue(t[2], @"panelWallpaper", @YES);
    // Different wallpapers later, and over an app (one shared block on iOS 15): the home
    // wallpaper is revealed underneath, the icons don't fly in, the content doesn't fade.
    for (int i = 3; i < 5; i++) {
        LSRApplyIOS15DifferentWallpaper(t[i]);
        LSRSetTransitionValue(t[i], @"revealWallpaper", @YES);
        LSRSetTransitionValue(t[i], @"iconsFlyIn", @NO);
        LSRSetTransitionValue(t[i], @"fadesContent", @NO);
    }
}

%group LSRUnlock

%hook CSCoverSheetTransitionsSettings
- (void)setDefaultValues {
    %orig;
    LSRApplyIOS15Transitions(self);
}

%end

%end // LSRUnlock

#pragma mark - Settings

// Missing file/key = never touched in Settings = on (the default).
static BOOL LSRPrefEnabled(NSDictionary *prefs, NSString *key) {
    id value = prefs[key];
    return value ? [value boolValue] : YES;
}

%ctor {
    NSDictionary *prefs = nil;
    for (size_t i = 0; i < sizeof(kLSRPrefsPaths) / sizeof(kLSRPrefsPaths[0]) && !prefs; i++) {
        prefs = [NSDictionary dictionaryWithContentsOfFile:kLSRPrefsPaths[i]];
    }

    // Also loaded into MediaRemoteUI, which draws the lock screen music player on iOS 16.
    NSString *process = [NSProcessInfo processInfo].processName;
    if ([process isEqualToString:@"MediaRemoteUI"]) {
        LSRDebugLog(@"MediaRemoteUI prefs readable: %d", prefs != nil);
        if (LSRPrefEnabled(prefs, @"mediaPlayerEnabled")) %init(LSRMediaPlayer);
        return;
    }
    if (![process isEqualToString:@"SpringBoard"]) return;
    sLSRClockEnabled = LSRPrefEnabled(prefs, @"clockEnabled");
    id clockSize = prefs[@"clockSize"];
    if ([clockSize isKindOfClass:[NSNumber class]]) sLSRClockSizeFactor = MIN(MAX([clockSize doubleValue], 0.7), 1.5);
    if (sLSRClockEnabled) %init(LSRClock);
    if (LSRPrefEnabled(prefs, @"focusEnabled")) %init(LSRFocus);
    if (LSRPrefEnabled(prefs, @"notificationsEnabled")) %init(LSRNotifications);
    if (LSRPrefEnabled(prefs, @"mediaPlayerEnabled")) %init(LSRMediaPlatter);
    if (LSRPrefEnabled(prefs, @"unlockAnimationEnabled") && NSClassFromString(@"CSCoverSheetTransitionsSettings")) %init(LSRUnlock);
    if (LSRPrefEnabled(prefs, @"liveWallpaperEnabled")) {
        sLSRWallpaperDesignDir = LSRResolveWallpaperDesignDir(prefs);
        sLSRHomeDesignDir = LSRResolveHomeDesignDir(prefs);
        sLSRDimInDark = [prefs[@"dimWallpaperInDark"] boolValue];
        sLSRPerspectiveZoom = prefs[@"perspectiveZoom"] ? [prefs[@"perspectiveZoom"] boolValue] : YES;
        // Also without any wallpaper yet: one picked in Settings > Wallpaper (a design or a
        // photo) then shows right away. Until then our views have no image and stay see-through.
        %init(LSRWallpaper);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            LSRWallpaperPrefsChanged, CFSTR("com.aronsz26.lockscreenrestore/wallpaper"), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }

#ifdef DEBUG
    // Debug builds: write the computed per-device layout for checking over SSH.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LSRLayout l = LSRCurrentLayout();
        NSString *summary = [NSString stringWithFormat:
            @"clockFontSize %.2f\ndateFontSize %.2f\ntimeBaselineY %.2f\ndateBaselineY %.2f\n"
            @"padlockScale %.2f\npadlockDrop %.2f\nscreen %@\n",
            l.clockFontSize, l.dateFontSize, l.timeBaselineY, l.dateBaselineY, l.padlockScale,
            l.padlockDrop, NSStringFromCGRect([UIScreen mainScreen].bounds)];
        [summary writeToFile:@"/var/mobile/Documents/LockScreenRestoreLayout-now.log" atomically:YES
                    encoding:NSUTF8StringEncoding error:nil];
    });
#endif
}
