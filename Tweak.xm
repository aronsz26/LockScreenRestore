// LockScreenRestore — iOS 15 lock screen look on iOS 16 (tested on 16.1.1, Dopamine rootless):
// thin white clock, date below it as "Sunday, September 27", focus pill under the date, big
// padlock that stays open after Face ID, notifications listed top-down under the clock, no
// vibrancy tint, no depth effect, no widgets. Sizes/positions match Apple's iOS 15 render.
//
// Class/selector names come from live runtime introspection + view-hierarchy dumps on-device.
//
// Three independently switchable groups (Settings > LockScreenRestore, all on by default),
// applied at SpringBoard launch — the settings page has a respring button.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Read straight from disk: NSUserDefaults in SpringBoard's constructor didn't see the values
// (cfprefsd). The settings page flushes to disk before its respring.
static NSString *const kLSRPrefsPath = @"/var/mobile/Library/Preferences/com.aronsz26.lockscreenrestore.plist";
static BOOL sLSRClockEnabled = YES;

@interface SBFLockScreenDateView : UIView
- (void)setCustomTimeFont:(UIFont *)font;
- (UIFont *)customTimeFont;
@end

@interface BSUIVibrancyEffectView : UIView
@property (nonatomic) BOOL isEnabled;
@end

@interface CSProminentDisplayView : UIView
@property (readonly, nonatomic) BSUIVibrancyEffectView *vibrancyEffectView;
@end

@interface CSProminentTextElementView : UIView
@property (nonatomic, strong) NSDate *date;
@property (readonly, nonatomic) UILabel *textLabel;
@end

@interface CSProminentTimeView : CSProminentTextElementView
@end

@interface CSProminentSubtitleDateView : CSProminentTextElementView
@end

@interface _UIAnimatingLabel : UILabel
@end

@interface SBUIProudLockIconView : UIView
@end

@interface PBUIPosterFloatingLayerReplica : UIView
@end

// Measured against Apple's iOS 15 lock screen render (390pt-wide screen, 1.156 px/pt): digits
// 57pt tall (SF digits are 0.717em -> 80pt font), "Monday, June 7" 140pt wide (-> 19.5pt),
// padlock top at 54.5pt, digits top at 119pt, date cap top at 196pt.
static const CGFloat kIOS15ClockFontSize = 80.0;
static const CGFloat kIOS15DateFontSize = 19.5;
// Offsets from where iOS 16 puts the top of the date view (screen y 85). A label's glyph top
// sits 0.235em below its top edge for digits and ~0.24em for capitals. The 80pt time label is
// vertically centered in a view iOS still sizes for 100pt (119 vs 95.7 tall -> 11.7 lower).
static const CGFloat kIOS15TimeTop = 3.8;    // 119.3 - 0.235 * 80 - 11.7 - 85
static const CGFloat kIOS15DateTop = 100.4;  // 196.3 - 0.24 * 19.5 - (36 - 23.3) / 2 - 85
static const CGFloat kIOS15PadlockScale = 2.0;
static const CGFloat kIOS15PadlockDrop = 12.3;

static UIFont *LSRClockFont(void) {
    return [UIFont systemFontOfSize:kIOS15ClockFontSize weight:UIFontWeightThin];
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
    if (fabs(self.customTimeFont.pointSize - kIOS15ClockFontSize) > 0.5) {
        [self setCustomTimeFont:LSRClockFont()];
    }
    %orig;
}
%end

#pragma mark - Time on top, date below
//
// iOS positions CSProminentTimeView / CSProminentSubtitleDateView via setFrame:/setCenter:.
// Transforms on top of that get mis-compensated by UIKit, so instead we record the positions
// iOS assigns (per container) and substitute the iOS 15 positions, anchored to where iOS 16
// puts the date.

// Set while we assign positions ourselves, so nested setFrame:/setCenter: calls pass straight
// through instead of being recorded as iOS's values.
static BOOL sLSRApplying = NO;

static const void *kLSRSysTimeTopKey = &kLSRSysTimeTopKey;
static const void *kLSRSysDateTopKey = &kLSRSysDateTopKey;

static void LSRRecord(UIView *container, const void *key, CGFloat value) {
    objc_setAssociatedObject(container, key, @(value), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static NSNumber *LSRRecorded(UIView *container, const void *key) {
    return objc_getAssociatedObject(container, key);
}

// NO = leave it alone (not enough info yet, or iOS already uses the iOS 15 order).
static BOOL LSRDesiredTop(UIView *container, BOOL isTime, CGFloat *outTop) {
    NSNumber *timeTop = LSRRecorded(container, kLSRSysTimeTopKey);
    NSNumber *dateTop = LSRRecorded(container, kLSRSysDateTopKey);
    if (!timeTop || !dateTop) return NO;
    if (dateTop.doubleValue >= timeTop.doubleValue) return NO;
    *outTop = dateTop.doubleValue + (isTime ? kIOS15TimeTop : kIOS15DateTop);
    return YES;
}

static void LSRMoveTop(UIView *view, CGFloat top) {
    CGPoint center = view.center;
    center.y = top + view.bounds.size.height / 2.0;
    sLSRApplying = YES;
    view.center = center;
    sLSRApplying = NO;
}

// Re-place the other view too, so both are right in the same pass whatever order iOS uses.
static void LSRRepositionSibling(UIView *container, BOOL siblingIsTime) {
    Class cls = NSClassFromString(siblingIsTime ? @"CSProminentTimeView" : @"CSProminentSubtitleDateView");
    for (UIView *sub in container.subviews) {
        if (![sub isKindOfClass:cls]) continue;
        CGFloat top;
        if (LSRDesiredTop(container, siblingIsTime, &top)) LSRMoveTop(sub, top);
        return;
    }
}

%hook CSProminentTimeView
// Covers a label that already had its font before being added here (setFont: hook above only
// applies once the label is inside this view). Only assign when different.
- (void)layoutSubviews {
    %orig;
    UILabel *label = self.textLabel;
    UIFont *font = LSRClockFont();
    if (label && ![label.font isEqual:font]) label.font = font;
}

- (void)setFrame:(CGRect)frame {
    UIView *container = self.superview;
    if (sLSRApplying || !container) {
        %orig;
        return;
    }
    LSRRecord(container, kLSRSysTimeTopKey, frame.origin.y);
    CGFloat top;
    if (LSRDesiredTop(container, YES, &top)) frame.origin.y = top;
    sLSRApplying = YES;
    %orig(frame);
    sLSRApplying = NO;
    LSRRepositionSibling(container, NO);
}

- (void)setCenter:(CGPoint)center {
    UIView *container = self.superview;
    if (sLSRApplying || !container) {
        %orig;
        return;
    }
    CGFloat height = self.bounds.size.height;
    LSRRecord(container, kLSRSysTimeTopKey, center.y - height / 2.0);
    CGFloat top;
    if (LSRDesiredTop(container, YES, &top)) center.y = top + height / 2.0;
    sLSRApplying = YES;
    %orig(center);
    sLSRApplying = NO;
    LSRRepositionSibling(container, NO);
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
    UIFont *regular = [UIFont systemFontOfSize:kIOS15DateFontSize weight:UIFontWeightRegular];
    if (![label.font isEqual:regular]) label.font = regular;
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

// The time label gets its ~100pt font assigned directly (base font / customTimeFont hooks
// didn't reach it), so size it here.
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
    UIView *container = self.superview;
    if (sLSRApplying || !container) {
        %orig;
        return;
    }
    LSRRecord(container, kLSRSysDateTopKey, frame.origin.y);
    CGFloat top;
    if (LSRDesiredTop(container, NO, &top)) frame.origin.y = top;
    sLSRApplying = YES;
    %orig(frame);
    sLSRApplying = NO;
    LSRRepositionSibling(container, YES);
}

- (void)setCenter:(CGPoint)center {
    UIView *container = self.superview;
    if (sLSRApplying || !container) {
        %orig;
        return;
    }
    CGFloat height = self.bounds.size.height;
    LSRRecord(container, kLSRSysDateTopKey, center.y - height / 2.0);
    CGFloat top;
    if (LSRDesiredTop(container, NO, &top)) center.y = top + height / 2.0;
    sLSRApplying = YES;
    %orig(center);
    sLSRApplying = NO;
    LSRRepositionSibling(container, YES);
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
    BSUIVibrancyEffectView *vibrancy = self.vibrancyEffectView;
    if (vibrancy.isEnabled) vibrancy.isEnabled = NO;
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
    // The 12x17pt glyph is only centered by its parent, never re-framed, so a transform is safe.
    UIView *glyph = LSRFindSubview(self, NSClassFromString(@"BSUICAPackageView"));
    CGAffineTransform t = CGAffineTransformMake(kIOS15PadlockScale, 0, 0, kIOS15PadlockScale, 0, kIOS15PadlockDrop);
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
// it, drop it below our moved date (the adjunct list starts where iOS 16's date area ended),
// and remove iOS 16's replacement: the focus name + symbol at the bottom of the notification
// list. The notification count in that bottom view is left alone.

// The pill sits at y≈213 by default; with the iOS 15 clock the date's glyphs end at y≈214, and
// iOS 15 put the pill ~10pt below the date. With the iOS 16 clock the default spot is already
// clear of the time.
static const CGFloat kIOS15FocusPillDrop = 11.8;

static CGFloat LSRFocusPillDrop(void) {
    return sLSRClockEnabled ? kIOS15FocusPillDrop : 0.0;
}

%group LSRFocus

%hook CSFocusActivityManager
- (BOOL)_shouldHideFocusActivityIndicator {
    return NO;
}
%end

%hook CSFocusActivityView
+ (CGSize)activityViewSize {
    CGSize size = %orig;
    size.height += LSRFocusPillDrop();
    return size;
}

- (CGRect)_activityIndicatorFrame {
    // The pill is vertically centered, so the taller view above already moves it down by
    // half the extra height; add the other half here.
    CGRect frame = %orig;
    frame.origin.y += LSRFocusPillDrop() / 2.0;
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
}
