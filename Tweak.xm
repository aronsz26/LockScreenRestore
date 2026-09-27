// LockScreenRestore — iOS 15 lock screen look on iOS 16 (rootless):
// thin white clock, date below it as "Sunday, September 27", focus pill under the date, big
// padlock that stays open after Face ID, notifications listed top-down under the clock, no
// vibrancy tint, no depth effect, no widgets.
//
// Sizes and positions adapt to the device: they come from the per-device values SpringBoard
// still carries from iOS 15 (SBFLockScreenMetrics) plus ratios measured against Apple's iOS 15
// lock screen, and are converted with the real font metrics at runtime.
//
// Three independently switchable groups (Settings > LockScreenRestore, all on by default),
// applied at SpringBoard launch — the settings page has a respring button.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreText/CoreText.h>

// Read straight from disk: NSUserDefaults in SpringBoard's constructor didn't see the values
// (cfprefsd). The settings page flushes to disk before its respring.
static NSString *const kLSRPrefsPath = @"/var/mobile/Library/Preferences/com.aronsz26.lockscreenrestore.plist";
static BOOL sLSRClockEnabled = YES;

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

        layout.clockFontSize = round(iOS16TimeSize * kIOS15ClockScale);
        layout.dateFontSize = LSRClassMetric(@"SBFLockScreenMetrics", @"dateLabelFontSize", 20.0);
        layout.dateBaselineY = LSRClassMetric(@"SBFLockScreenMetrics", @"subtitleBaselineOffsetFromTopOfScreen", 211.0);
        layout.timeBaselineY = layout.dateBaselineY - kIOS15TimeBaselineAboveDate * layout.clockFontSize;
        layout.padlockScale = 1.0 / LSRClassMetric(@"SBFLockScreenMetrics", @"proudLockScaleFactor", 0.5);

        CGFloat digitsTop = layout.timeBaselineY - kSFDigitHeight * layout.clockFontSize;
        CGFloat padlockCenter = digitsTop - kIOS15PadlockCenterAboveDigits * layout.clockFontSize;
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

// The time label gets iOS 16's font assigned directly (customTimeFont doesn't reach it).
- (void)setFont:(UIFont *)font {
    if ([self.superview isKindOfClass:NSClassFromString(@"CSProminentTimeView")]) font = LSRClockFont();
    %orig(font);
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
    NSString *replacement = LSRIOS15DateTextForLabel(self, attributedText.string);
    if (attributedText.length && ![replacement isEqualToString:attributedText.string]) {
        NSDictionary *attributes = [attributedText attributesAtIndex:0 effectiveRange:NULL];
        attributedText = [[NSAttributedString alloc] initWithString:replacement attributes:attributes];
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

static const CGFloat kIOS15FocusPillGap = 10.0;

@interface CSFocusActivityView : UIView
@end

%group LSRFocus

%hook CSFocusActivityManager
- (BOOL)_shouldHideFocusActivityIndicator {
    return NO;
}
%end

%hook CSFocusActivityView
- (CGRect)_activityIndicatorFrame {
    CGRect frame = %orig;
    UIView *display = sLSRDisplayView;
    if (!sLSRClockEnabled || !display || !self.window || display.window != self.window) return frame;

    LSRLayout layout = LSRCurrentLayout();
    CGFloat wantedTop = layout.dateBaselineY + kSFDescender * layout.dateFontSize + kIOS15FocusPillGap;
    CGFloat itemTop = [self convertPoint:CGPointZero toView:display].y;
    // Only ever move it down, never up into the date.
    frame.origin.y = MAX(frame.origin.y, round((wantedTop - itemTop) * 3.0) / 3.0);

    UIView *item = self.superview;
    Class itemClass = NSClassFromString(@"CSAdjunctItemView");
    while (item && ![item isKindOfClass:itemClass]) item = item.superview;
    if (item.clipsToBounds) item.clipsToBounds = NO;
    return frame;
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

%group LSRNotifications

%hook NCNotificationListView
- (BOOL)layoutFromBottom {
    return NO;
}

- (void)setLayoutFromBottom:(BOOL)layoutFromBottom {
    %orig(NO);
}
%end

// iOS 15 cards had ~8pt side margins (measured 8.6pt incl. anti-aliasing); iOS 16 uses 10.
%hook CSCombinedListViewController
- (CGFloat)horizontalInsetMargin {
    return 8.0;
}
%end

%end // LSRNotifications

#pragma mark - Settings

// Missing file/key = never touched in Settings = on (the default).
static BOOL LSRPrefEnabled(NSDictionary *prefs, NSString *key) {
    id value = prefs[key];
    return value ? [value boolValue] : YES;
}

%ctor {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kLSRPrefsPath];
    sLSRClockEnabled = LSRPrefEnabled(prefs, @"clockEnabled");
    if (sLSRClockEnabled) %init(LSRClock);
    if (LSRPrefEnabled(prefs, @"focusEnabled")) %init(LSRFocus);
    if (LSRPrefEnabled(prefs, @"notificationsEnabled")) %init(LSRNotifications);

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
