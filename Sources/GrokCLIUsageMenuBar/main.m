#import "PersistentStartup.h"
#import "UsagePace.h"
#import "GrokBilling.h"
#import "GrokAuth.h"
#import "GrokIcon.h"
#import "GrokUpdater.h"
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <math.h>

static NSString * const LaunchAtLoginPreferenceKey = @"launchAtLoginPreference";
static NSString * const DisplayModeKey = @"displayMode";
static NSString * const DisplayModePercent = @"percent";
static NSString * const DisplayModeBattery = @"battery";
static NSString * const TimeModeKey = @"timeMode";
static NSString * const TimeModeClock = @"clock";
static NSString * const TimeModeCountdown = @"countdown";
static NSString * const TimeModeHidden = @"hidden";
static NSString * const MetricModeKey = @"metricMode";
static NSString * const MetricModeLeft = @"left";
static NSString * const MetricModeUsed = @"used";
static NSString * const WidgetWindowModeKey = @"widgetWindowMode";
static NSString * const WidgetWindowDaily = @"daily";
static NSString * const WidgetWindowWeekly = @"weekly";
static NSString * const RefreshIntervalKey = @"refreshIntervalSeconds";
static NSString * const LastGoodStateKey = @"lastGoodUsageState";
static NSTimeInterval const DefaultRefreshIntervalSeconds = 300.0;
static NSString * const StartupLabel = @"com.local.autostart.grok-cli-usage";

@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSTimer *pollTimer;
@property(nonatomic, strong) NSTimer *displayTimer;
@property(nonatomic, strong) NSDictionary *latestState;
@property(nonatomic, strong) NSImage *grokIcon;
@property(nonatomic, copy) NSString *launchAtLoginError;
@property(nonatomic, assign) BOOL checkingForUpdates;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        LaunchAtLoginPreferenceKey: @YES,
        DisplayModeKey: DisplayModePercent,
        TimeModeKey: TimeModeClock,
        MetricModeKey: MetricModeLeft,
        WidgetWindowModeKey: WidgetWindowDaily,
        RefreshIntervalKey: @(DefaultRefreshIntervalSeconds)
    }];

    [self ensureLaunchAtLoginIfPreferred];

    self.grokIcon = [self grokMenuBarIcon];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"--";
    self.statusItem.button.image = self.grokIcon;
    self.statusItem.button.imagePosition = NSImageLeft;
    self.statusItem.button.font = [NSFont monospacedDigitSystemFontOfSize:[NSFont systemFontSize]
                                                                    weight:NSFontWeightMedium];
    self.statusItem.menu = [self menuForCurrentState];

    [self refresh];
    [self schedulePollTimer];
    self.displayTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                         target:self
                                                       selector:@selector(updateStatusItem)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (NSImage *)grokMenuBarIcon {
    NSString *bundledIcon = [NSBundle.mainBundle pathForResource:@"GrokMenuBarIcon" ofType:@"png"];
    if (bundledIcon.length > 0) {
        NSImage *image = [[NSImage alloc] initWithContentsOfFile:bundledIcon];
        if (image != nil) {
            image.template = YES;
            image.size = NSMakeSize(18.0, 18.0);
            image.accessibilityDescription = @"Grok";
            return image;
        }
    }
    return GrokBlackHoleIcon();
}

- (NSImage *)batteryIconForPercent:(double)percent recommendedPercent:(double)recommendedPercent {
    double clamped = MAX(0.0, MIN(100.0, percent));
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(66.0, 18.0)];
    __block NSColor *foregroundColor = NSColor.blackColor;
    NSAppearance *appearance = self.statusItem.button.effectiveAppearance ?: NSApp.effectiveAppearance;
    [appearance performAsCurrentDrawingAppearance:^{
        foregroundColor = [NSColor.labelColor colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace]
            ?: NSColor.blackColor;
    }];

    [image lockFocus];

    [NSColor.blackColor set];
    if (self.grokIcon != nil) {
        [self.grokIcon drawInRect:NSMakeRect(0.0, 0.0, 18.0, 18.0)];
    }

    NSRect body = NSMakeRect(24.0, 3.0, 34.0, 12.0);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:body xRadius:2.0 yRadius:2.0];
    outline.lineWidth = 1.4;
    [outline stroke];

    NSRect nub = NSMakeRect(NSMaxX(body) + 1.0, 6.5, 2.0, 5.0);
    [[NSBezierPath bezierPathWithRoundedRect:nub xRadius:0.8 yRadius:0.8] fill];

    CGFloat fillWidth = (CGFloat)((body.size.width - 4.0) * (clamped / 100.0));
    NSBezierPath *fillPath = nil;
    if (fillWidth > 0.5) {
        NSRect fillRect = NSMakeRect(body.origin.x + 2.0, body.origin.y + 2.0, fillWidth, body.size.height - 4.0);
        fillPath = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:1.0 yRadius:1.0];
        [fillPath fill];
    }

    NSString *number = [NSString stringWithFormat:@"%.0f", clamped];
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:8.5 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.blackColor
    };
    NSSize numberSize = [number sizeWithAttributes:attributes];
    NSPoint numberPoint = NSMakePoint(NSMidX(body) - numberSize.width / 2.0,
                                      NSMidY(body) - numberSize.height / 2.0 - 0.5);
    [number drawAtPoint:numberPoint withAttributes:attributes];

    // Template images carry opacity rather than fixed colors. Remove the part of
    // each glyph that overlaps the charge so it reveals the menu-bar background;
    // the remainder keeps the system icon tint. This gives the number opposite
    // contrast on either side of the moving fill boundary in light and dark mode.
    if (fillPath != nil) {
        [NSGraphicsContext saveGraphicsState];
        [fillPath addClip];
        NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
        [number drawAtPoint:numberPoint withAttributes:attributes];
        [NSGraphicsContext restoreGraphicsState];
    }

    // Resolve the template artwork to the current menu-bar foreground color.
    [foregroundColor setFill];
    NSRectFillUsingOperation(NSMakeRect(0.0, 0.0, image.size.width, image.size.height),
                             NSCompositingOperationSourceIn);

    if (isfinite(recommendedPercent)) {
        double pace = MAX(0.0, MIN(100.0, recommendedPercent));
        CGFloat markerX = body.origin.x + 2.0 + (body.size.width - 4.0) * (CGFloat)(pace / 100.0);
        NSRect numberBounds = NSMakeRect(numberPoint.x - 0.5,
                                         numberPoint.y,
                                         numberSize.width + 1.0,
                                         numberSize.height);
        CGFloat markerAlpha = NSPointInRect(NSMakePoint(markerX, NSMidY(numberBounds)), numberBounds)
            ? 0.55
            : 1.0;
        NSBezierPath *marker = [NSBezierPath bezierPath];
        [marker moveToPoint:NSMakePoint(markerX, body.origin.y + 1.0)];
        [marker lineToPoint:NSMakePoint(markerX, NSMaxY(body) - 1.0)];
        marker.lineWidth = 1.5;
        marker.lineCapStyle = NSLineCapStyleRound;
        [[foregroundColor colorWithAlphaComponent:markerAlpha] setStroke];
        [marker stroke];

        if (fillPath != nil) {
            [NSGraphicsContext saveGraphicsState];
            [fillPath addClip];
            NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
            [marker stroke];
            [NSGraphicsContext restoreGraphicsState];
        }

        NSDictionary *foregroundAttributes = @{
            NSFontAttributeName: attributes[NSFontAttributeName],
            NSForegroundColorAttributeName: foregroundColor
        };
        [number drawAtPoint:numberPoint withAttributes:foregroundAttributes];
        if (fillPath != nil) {
            [NSGraphicsContext saveGraphicsState];
            [fillPath addClip];
            NSGraphicsContext.currentContext.compositingOperation = NSCompositingOperationDestinationOut;
            [number drawAtPoint:numberPoint withAttributes:foregroundAttributes];
            [NSGraphicsContext restoreGraphicsState];
        }
    }

    [image unlockFocus];
    image.template = NO;
    return image;
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    self.statusItem.menu = [self menuForCurrentState];
}

- (NSMenu *)menuForCurrentState {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Grok CLI Usage"];
    menu.delegate = self;

    NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"Grok CLI Usage" action:nil keyEquivalent:@""];
    header.enabled = NO;
    [menu addItem:header];
    [menu addItem:[NSMenuItem separatorItem]];

    NSDictionary *state = self.latestState;
    [self addDisabledItem:[self detailUsageTextForState:state] toMenu:menu];
    if ([state[@"weekly_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"weekly_summary"] toMenu:menu];
    }
    [self addDisabledItem:[self resetClockDetailForState:state] toMenu:menu];
    [self addDisabledItem:[self countdownDetailForState:state] toMenu:menu];

    if ([state[@"credits_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"credits_summary"] toMenu:menu];
    }
    if ([state[@"on_demand_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"on_demand_summary"] toMenu:menu];
    }
    if ([state[@"monthly_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"monthly_summary"] toMenu:menu];
    }
    if ([state[@"plan_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"plan_summary"] toMenu:menu];
    }
    if ([state[@"limit_summaries"] isKindOfClass:[NSArray class]]) {
        for (id summary in state[@"limit_summaries"]) {
            if ([summary isKindOfClass:[NSString class]]) {
                [self addDisabledItem:summary toMenu:menu];
            }
        }
    }
    [self addDisabledItem:state[@"updated_summary"] ?: @"Updated: unknown" toMenu:menu];

    if ([state[@"source_summary"] isKindOfClass:[NSString class]]) {
        [self addDisabledItem:state[@"source_summary"] toMenu:menu];
    }
    if (self.launchAtLoginError.length > 0) {
        [self addDisabledItem:[NSString stringWithFormat:@"Login item: %@", self.launchAtLoginError] toMenu:menu];
    }

    NSNumber *ok = state[@"ok"];
    if ([ok respondsToSelector:@selector(boolValue)] && ![ok boolValue] &&
        [state[@"error"] isKindOfClass:[NSString class]]) {
        [menu addItem:[NSMenuItem separatorItem]];
        [self addDisabledItem:[NSString stringWithFormat:@"Error: %@", state[@"error"]] toMenu:menu];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Show Percentage"
                      action:@selector(usePercentDisplay)
                     checked:[[self displayMode] isEqualToString:DisplayModePercent]
                      toMenu:menu];
    [self addChoiceWithTitle:@"Show Battery"
                      action:@selector(useBatteryDisplay)
                     checked:[[self displayMode] isEqualToString:DisplayModeBattery]
                      toMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Show % Left"
                      action:@selector(useLeftMetric)
                     checked:[[self metricMode] isEqualToString:MetricModeLeft]
                      toMenu:menu];
    [self addChoiceWithTitle:@"Show % Used"
                      action:@selector(useUsedMetric)
                     checked:[[self metricMode] isEqualToString:MetricModeUsed]
                      toMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Widget: Daily"
                      action:@selector(useDailyWidgetWindow)
                     checked:[[self widgetWindowMode] isEqualToString:WidgetWindowDaily]
                      toMenu:menu];
    [self addChoiceWithTitle:@"Widget: Weekly"
                      action:@selector(useWeeklyWidgetWindow)
                     checked:[[self widgetWindowMode] isEqualToString:WidgetWindowWeekly]
                      toMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Show Reset Time"
                      action:@selector(useClockTime)
                     checked:[[self timeMode] isEqualToString:TimeModeClock]
                      toMenu:menu];
    [self addChoiceWithTitle:@"Show Countdown"
                      action:@selector(useCountdownTime)
                     checked:[[self timeMode] isEqualToString:TimeModeCountdown]
                      toMenu:menu];
    [self addChoiceWithTitle:@"Hide Time"
                      action:@selector(useHiddenTime)
                     checked:[[self timeMode] isEqualToString:TimeModeHidden]
                      toMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addRefreshIntervalSubmenuToMenu:menu];

    [menu addItem:[NSMenuItem separatorItem]];
    [self addChoiceWithTitle:@"Launch at Login & Keep Running"
                      action:@selector(toggleLaunchAtLogin)
                     checked:[self launchAtLoginEnabled]
                      toMenu:menu];

    [self addActionsToMenu:menu];
    return menu;
}

- (void)addActionsToMenu:(NSMenu *)menu {
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *refresh = [[NSMenuItem alloc] initWithTitle:@"Refresh Now"
                                                     action:@selector(refresh)
                                              keyEquivalent:@"r"];
    refresh.target = self;
    [menu addItem:refresh];

    NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:self.checkingForUpdates ? @"Checking for Updates…" : @"Check for Updates"
                                                     action:@selector(checkForUpdates)
                                              keyEquivalent:@"u"];
    updates.target = self;
    updates.enabled = !self.checkingForUpdates;
    [menu addItem:updates];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                  action:@selector(quit)
                                           keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
}

- (void)addChoiceWithTitle:(NSString *)title action:(SEL)action checked:(BOOL)checked toMenu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.state = checked ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:item];
}

- (void)addRefreshIntervalSubmenuToMenu:(NSMenu *)menu {
    NSTimeInterval current = [self refreshIntervalSeconds];
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Refresh Every: %@",
                                                          [self refreshIntervalLabelForSeconds:current]]
                                                  action:nil
                                           keyEquivalent:@""];
    NSMenu *submenu = [[NSMenu alloc] initWithTitle:@"Refresh Every"];
    NSArray<NSNumber *> *intervals = @[@30.0, @60.0, @180.0, @300.0];

    for (NSNumber *interval in intervals) {
        NSTimeInterval seconds = interval.doubleValue;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[self refreshIntervalLabelForSeconds:seconds]
                                                      action:@selector(useRefreshInterval:)
                                               keyEquivalent:@""];
        item.target = self;
        item.representedObject = interval;
        item.state = fabs(seconds - current) < 0.5 ? NSControlStateValueOn : NSControlStateValueOff;
        [submenu addItem:item];
    }

    root.submenu = submenu;
    [menu addItem:root];
}

- (void)addDisabledItem:(NSString *)title toMenu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title ?: @"" action:nil keyEquivalent:@""];
    item.enabled = NO;
    [menu addItem:item];
}

- (void)updateStatusItem {
    NSDictionary *state = self.latestState;
    NSNumber *ok = state[@"ok"];
    if (![ok respondsToSelector:@selector(boolValue)] || ![ok boolValue]) {
        self.statusItem.button.toolTip = nil;
        self.statusItem.button.image = self.grokIcon;
        [self setStatusItemTitle:@"--"];
        return;
    }

    double metric = [self displayPercentForWidgetState:state];
    BOOL hideTime = [[self timeMode] isEqualToString:TimeModeHidden];
    NSString *timeText = hideTime ? @"" : [self timeTextForWidgetState:state];

    if ([[self displayMode] isEqualToString:DisplayModeBattery]) {
        double recommendedPercent = NAN;
        if ([[self metricMode] isEqualToString:MetricModeLeft]) {
            recommendedPercent = [self recommendedPercentLeftForWidgetState:state];
        }
        self.statusItem.button.image = [self batteryIconForPercent:metric recommendedPercent:recommendedPercent];
        [self setStatusItemTitle:timeText];
        self.statusItem.button.toolTip = isfinite(recommendedPercent) ? @"Contrast marker: on-pace usage target" : nil;
        return;
    }

    self.statusItem.button.toolTip = nil;
    self.statusItem.button.image = self.grokIcon;
    if (isnan(metric)) {
        [self setStatusItemTitle:timeText.length > 0 ? timeText : @"--"];
    } else {
        NSString *metricText = [NSString stringWithFormat:@"%.0f%%", metric];
        NSString *metricLabel = [self metricLabel];
        if (metricLabel.length > 0) {
            metricText = [NSString stringWithFormat:@"%@ %@", metricText, metricLabel];
        }
        [self setStatusItemTitle:hideTime ? metricText : [NSString stringWithFormat:@"%@ | %@", timeText, metricText]];
    }
}

- (void)setStatusItemTitle:(NSString *)title {
    self.statusItem.button.title = title ?: @"";
    self.statusItem.button.imagePosition = self.statusItem.button.title.length > 0 ? NSImageLeft : NSImageOnly;
}

- (NSString *)detailUsageTextForState:(NSDictionary *)state {
    double used = [self usagePercentForState:state];
    if (isnan(used)) {
        return @"Grok usage: unavailable";
    }
    double left = MAX(0.0, MIN(100.0, 100.0 - used));
    return [NSString stringWithFormat:@"Grok: %.0f%% left, %.0f%% used", left, used];
}

- (NSString *)resetClockDetailForState:(NSDictionary *)state {
    NSString *clock = [self resetClockTextForState:state];
    if (clock.length == 0) {
        return @"Reset time: unknown";
    }
    return [NSString stringWithFormat:@"Reset time: %@", clock];
}

- (NSString *)countdownDetailForState:(NSDictionary *)state {
    NSString *countdown = [self countdownTextForState:state];
    if (countdown.length == 0) {
        return @"Countdown: unknown";
    }
    return [NSString stringWithFormat:@"Countdown: %@", countdown];
}

- (double)usagePercentForState:(NSDictionary *)state {
    id value = state[@"primary_used_percent"];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return MAX(0.0, MIN(100.0, [value doubleValue]));
    }
    return NAN;
}

- (double)displayPercentForState:(NSDictionary *)state {
    double used = [self usagePercentForState:state];
    if (isnan(used)) {
        return NAN;
    }
    if ([[self metricMode] isEqualToString:MetricModeUsed]) {
        return used;
    }
    return MAX(0.0, MIN(100.0, 100.0 - used));
}

- (double)displayPercentForWidgetState:(NSDictionary *)state {
    double used = [self widgetUsagePercentForState:state];
    if (isnan(used)) {
        return NAN;
    }
    if ([[self metricMode] isEqualToString:MetricModeUsed]) {
        return used;
    }
    return MAX(0.0, MIN(100.0, 100.0 - used));
}

- (double)widgetUsagePercentForState:(NSDictionary *)state {
    id value = [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly] ? state[@"secondary_used_percent"] : state[@"primary_used_percent"];
    if (![value respondsToSelector:@selector(doubleValue)] && [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly]) {
        value = state[@"primary_used_percent"];
    }
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return MAX(0.0, MIN(100.0, [value doubleValue]));
    }
    return NAN;
}

- (NSString *)metricLabel {
    if ([[self metricMode] isEqualToString:MetricModeUsed]) {
        return @"used";
    }
    return @"";
}

- (NSNumber *)resetSecondsForState:(NSDictionary *)state {
    id value = state[@"primary_resets_at"];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return @([value doubleValue]);
    }
    return nil;
}

- (NSNumber *)widgetResetSecondsForState:(NSDictionary *)state {
    id value = [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly] ? state[@"secondary_resets_at"] : state[@"primary_resets_at"];
    if (![value respondsToSelector:@selector(doubleValue)] && [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly]) {
        value = state[@"primary_resets_at"];
    }
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return @([value doubleValue]);
    }
    return nil;
}

- (NSNumber *)widgetWindowDurationMinutesForState:(NSDictionary *)state {
    BOOL weekly = [[self widgetWindowMode] isEqualToString:WidgetWindowWeekly];
    id value = state[@"primary_window_minutes"];
    if (weekly && [state[@"secondary_resets_at"] respondsToSelector:@selector(doubleValue)]) {
        value = state[@"secondary_window_minutes"];
        if (![value respondsToSelector:@selector(doubleValue)]) {
            return @(7.0 * 24.0 * 60.0);
        }
    }
    if ([value respondsToSelector:@selector(doubleValue)] && [value doubleValue] > 0.0) {
        return @([value doubleValue]);
    }
    return nil;
}

- (double)recommendedPercentLeftForWidgetState:(NSDictionary *)state {
    NSNumber *reset = [self widgetResetSecondsForState:state];
    NSNumber *durationMinutes = [self widgetWindowDurationMinutesForState:state];
    if (reset == nil || durationMinutes == nil) {
        return NAN;
    }
    return GrokOnPacePercentLeft(reset.doubleValue,
                                 NSDate.date.timeIntervalSince1970,
                                 durationMinutes.doubleValue);
}

- (NSString *)timeTextForState:(NSDictionary *)state {
    if ([[self timeMode] isEqualToString:TimeModeCountdown]) {
        return [self countdownTextForState:state] ?: @"--:--";
    }
    return [self resetClockTextForState:state] ?: @"--";
}

- (NSString *)timeTextForWidgetState:(NSDictionary *)state {
    if ([[self timeMode] isEqualToString:TimeModeCountdown]) {
        return [self countdownTextForWidgetState:state] ?: @"--:--";
    }
    return [self resetClockTextForWidgetState:state] ?: @"--";
}

- (NSString *)resetClockTextForState:(NSDictionary *)state {
    NSNumber *seconds = [self resetSecondsForState:state];
    if (seconds == nil) {
        return nil;
    }

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seconds.doubleValue];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

- (NSString *)resetClockTextForWidgetState:(NSDictionary *)state {
    NSNumber *seconds = [self widgetResetSecondsForState:state];
    if (seconds == nil) {
        return nil;
    }

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seconds.doubleValue];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

- (NSString *)countdownTextForState:(NSDictionary *)state {
    NSNumber *seconds = [self resetSecondsForState:state];
    if (seconds == nil) {
        return nil;
    }

    NSInteger remaining = MAX(0, (NSInteger)llround(seconds.doubleValue - [NSDate date].timeIntervalSince1970));
    NSInteger hours = remaining / 3600;
    NSInteger minutes = (remaining % 3600) / 60;
    NSInteger secs = remaining % 60;
    return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
}

- (NSString *)countdownTextForWidgetState:(NSDictionary *)state {
    NSNumber *seconds = [self widgetResetSecondsForState:state];
    if (seconds == nil) {
        return nil;
    }

    NSInteger remaining = MAX(0, (NSInteger)llround(seconds.doubleValue - [NSDate date].timeIntervalSince1970));
    NSInteger hours = remaining / 3600;
    NSInteger minutes = (remaining % 3600) / 60;
    NSInteger secs = remaining % 60;
    return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)secs];
}

- (NSString *)displayMode {
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:DisplayModeKey];
    return mode.length > 0 ? mode : DisplayModePercent;
}

- (NSString *)timeMode {
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:TimeModeKey];
    return mode.length > 0 ? mode : TimeModeClock;
}

- (NSString *)metricMode {
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:MetricModeKey];
    return mode.length > 0 ? mode : MetricModeLeft;
}

- (NSString *)widgetWindowMode {
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:WidgetWindowModeKey];
    if ([mode isEqualToString:WidgetWindowWeekly]) {
        return WidgetWindowWeekly;
    }
    return WidgetWindowDaily;
}

- (NSTimeInterval)refreshIntervalSeconds {
    NSTimeInterval seconds = [NSUserDefaults.standardUserDefaults doubleForKey:RefreshIntervalKey];
    NSArray<NSNumber *> *allowed = @[@30.0, @60.0, @180.0, @300.0];
    for (NSNumber *interval in allowed) {
        if (fabs(seconds - interval.doubleValue) < 0.5) {
            return interval.doubleValue;
        }
    }
    return DefaultRefreshIntervalSeconds;
}

- (NSString *)refreshIntervalLabelForSeconds:(NSTimeInterval)seconds {
    if (fabs(seconds - 30.0) < 0.5) {
        return @"30 sec";
    }
    NSInteger minutes = (NSInteger)llround(seconds / 60.0);
    return [NSString stringWithFormat:@"%ld min", (long)minutes];
}

- (void)usePercentDisplay {
    [NSUserDefaults.standardUserDefaults setObject:DisplayModePercent forKey:DisplayModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useBatteryDisplay {
    [NSUserDefaults.standardUserDefaults setObject:DisplayModeBattery forKey:DisplayModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useClockTime {
    [NSUserDefaults.standardUserDefaults setObject:TimeModeClock forKey:TimeModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useCountdownTime {
    [NSUserDefaults.standardUserDefaults setObject:TimeModeCountdown forKey:TimeModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useHiddenTime {
    [NSUserDefaults.standardUserDefaults setObject:TimeModeHidden forKey:TimeModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useLeftMetric {
    [NSUserDefaults.standardUserDefaults setObject:MetricModeLeft forKey:MetricModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useUsedMetric {
    [NSUserDefaults.standardUserDefaults setObject:MetricModeUsed forKey:MetricModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useDailyWidgetWindow {
    [NSUserDefaults.standardUserDefaults setObject:WidgetWindowDaily forKey:WidgetWindowModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useWeeklyWidgetWindow {
    [NSUserDefaults.standardUserDefaults setObject:WidgetWindowWeekly forKey:WidgetWindowModeKey];
    [self updateStatusItem];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)useRefreshInterval:(NSMenuItem *)sender {
    NSNumber *interval = sender.representedObject;
    if (![interval respondsToSelector:@selector(doubleValue)]) {
        return;
    }

    [NSUserDefaults.standardUserDefaults setDouble:interval.doubleValue forKey:RefreshIntervalKey];
    [self schedulePollTimer];
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)schedulePollTimer {
    [self.pollTimer invalidate];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:[self refreshIntervalSeconds]
                                                      target:self
                                                    selector:@selector(refresh)
                                                    userInfo:nil
                                                     repeats:YES];
}

- (void)refresh {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *state = [self loadUsageState];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.latestState = state;
            [self updateStatusItem];
            self.statusItem.menu = [self menuForCurrentState];
        });
    });
}

- (NSDictionary *)loadUsageState {
    NSDictionary *liveState = [self loadUsageStateFromGrokBilling];
    NSNumber *liveOk = liveState[@"ok"];
    if ([liveOk respondsToSelector:@selector(boolValue)] && [liveOk boolValue]) {
        [self cacheGoodState:liveState];
        return liveState;
    }

    NSDictionary *cachedState = [self loadUsageStateFromCache];
    NSNumber *cachedOk = cachedState[@"ok"];
    if ([cachedOk respondsToSelector:@selector(boolValue)] && [cachedOk boolValue]) {
        NSMutableDictionary *state = [cachedState mutableCopy];
        NSString *liveError = liveState[@"error"];
        if ([liveError isKindOfClass:[NSString class]] && liveError.length > 0) {
            state[@"live_error"] = liveError;
        }
        return state;
    }

    NSString *liveError = [liveState[@"error"] isKindOfClass:[NSString class]] ? liveState[@"error"] : @"Grok billing unavailable";
    return @{
        @"ok": @NO,
        @"menu_title": @"--",
        @"primary_summary": @"Grok usage: unavailable",
        @"updated_summary": @"Updated: unavailable",
        @"source_summary": @"Source: unavailable",
        @"error": liveError
    };
}

- (void)cacheGoodState:(NSDictionary *)state {
    if (![state isKindOfClass:[NSDictionary class]]) {
        return;
    }
    NSError *error = nil;
    if (![NSJSONSerialization isValidJSONObject:state]) {
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:&error];
    if (data != nil) {
        [NSUserDefaults.standardUserDefaults setObject:data forKey:LastGoodStateKey];
    }
}

- (NSDictionary *)loadUsageStateFromCache {
    NSData *data = [NSUserDefaults.standardUserDefaults dataForKey:LastGoodStateKey];
    if (data.length == 0) {
        return @{@"ok": @NO, @"error": @"No cached Grok usage snapshot"};
    }
    NSDictionary *state = GrokJSONFromData(data);
    if (![state[@"ok"] respondsToSelector:@selector(boolValue)] || ![state[@"ok"] boolValue]) {
        return @{@"ok": @NO, @"error": @"Cached Grok usage snapshot is invalid"};
    }
    NSMutableDictionary *cached = [state mutableCopy];
    cached[@"source_summary"] = @"Source: Cached Grok CLI billing";
    return cached;
}

- (NSDictionary *)loadUsageStateFromGrokBilling {
    NSError *error = nil;
    NSMutableDictionary *auth = GrokLoadFreshAuth(&error);
    if (auth == nil) {
        return @{
            @"ok": @NO,
            @"error": error.localizedDescription ?: @"Grok CLI is not signed in. Run grok login."
        };
    }

    NSString *accessToken = auth[@"accessToken"];
    NSString *userId = auth[@"userId"];
    NSString *base = GrokProxyBaseURL();
    NSInteger status = 0;
    NSError *requestError = nil;
    NSDictionary *billing = GrokHTTPGetJSON([base stringByAppendingString:@"/billing?format=credits"],
                                            accessToken,
                                            userId,
                                            &status,
                                            &requestError);
    if ((status == 401 || status == 403) && [auth[@"refreshToken"] isKindOfClass:[NSString class]]) {
        NSError *refreshError = nil;
        if (GrokRefreshAccessToken(auth, &refreshError)) {
            status = 0;
            requestError = nil;
            billing = GrokHTTPGetJSON([base stringByAppendingString:@"/billing?format=credits"],
                                      auth[@"accessToken"],
                                      userId,
                                      &status,
                                      &requestError);
        }
    }
    if (billing == nil || status < 200 || status >= 300) {
        NSString *message = requestError.localizedDescription ?: [NSString stringWithFormat:@"Grok billing HTTP %ld", (long)status];
        if (status == 401 || status == 403) {
            message = @"Grok session expired. Run grok login.";
        }
        return @{@"ok": @NO, @"error": message};
    }

    NSString *plan = [self loadPlanNameWithAuth:auth];
    NSDictionary *snapshot = GrokSnapshotFromBillingObject(billing, plan);
    if (snapshot == nil) {
        return @{@"ok": @NO, @"error": @"Grok billing response had no usage window"};
    }

    NSDictionary *state = [self buildStateFromSnapshot:snapshot
                                            sourceText:@"Grok CLI billing"
                                             timestamp:[NSDate date]
                                         appServerKeys:YES];
    NSMutableDictionary *mutable = [state mutableCopy];

    if ([snapshot[@"periodKind"] isEqualToString:@"weekly"] && mutable[@"weekly_summary"] == nil) {
        NSString *weekly = [self weeklySummary:snapshot[@"primary"] appServerKeys:YES];
        if (weekly.length > 0) {
            mutable[@"weekly_summary"] = weekly;
        }
    }

    NSNumber *cap = snapshot[@"onDemandCap"];
    NSNumber *used = snapshot[@"onDemandUsed"];
    if (cap != nil && cap.doubleValue > 0.0) {
        mutable[@"on_demand_summary"] = [NSString stringWithFormat:@"On-demand: $%.2f of $%.2f",
                                         (used ?: @(0)).doubleValue / 100.0,
                                         cap.doubleValue / 100.0];
    }

    NSMutableArray<NSString *> *summaries = [NSMutableArray array];
    if ([mutable[@"limit_summaries"] isKindOfClass:[NSArray class]]) {
        [summaries addObjectsFromArray:mutable[@"limit_summaries"]];
    }
    if ([snapshot[@"productUsage"] isKindOfClass:[NSArray class]]) {
        for (NSDictionary *product in snapshot[@"productUsage"]) {
            NSNumber *percent = product[@"usedPercent"];
            NSString *name = product[@"name"] ?: @"Product";
            [summaries addObject:[NSString stringWithFormat:@"%@: %@",
                                  name,
                                  [self percentSummaryTextForUsedPercent:percent]]];
        }
    }
    if (summaries.count > 0) {
        mutable[@"limit_summaries"] = summaries;
    }
    return mutable;
}

- (NSString *)loadPlanNameWithAuth:(NSDictionary *)auth {
    NSString *accessToken = auth[@"accessToken"];
    NSString *userId = auth[@"userId"];
    NSString *base = GrokProxyBaseURL();
    NSInteger status = 0;
    NSDictionary *settings = GrokHTTPGetJSON([base stringByAppendingString:@"/settings"],
                                             accessToken,
                                             userId,
                                             &status,
                                             nil);
    NSString *display = settings[@"subscription_tier_display"];
    if ([display isKindOfClass:[NSString class]] && display.length > 0) {
        return display;
    }
    status = 0;
    NSDictionary *user = GrokHTTPGetJSON([base stringByAppendingString:@"/user?include=subscription"],
                                         accessToken,
                                         userId,
                                         &status,
                                         nil);
    NSString *tier = user[@"subscriptionTier"];
    if ([tier isKindOfClass:[NSString class]] && tier.length > 0) {
        if ([tier isEqualToString:@"XPremiumPlus"]) {
            return @"X Premium+";
        }
        return tier;
    }
    return nil;
}

- (NSDictionary *)buildStateFromSnapshot:(NSDictionary *)snapshot
                              sourceText:(NSString *)sourceText
                               timestamp:(NSDate *)timestamp
                            appServerKeys:(BOOL)appServerKeys {
    NSDictionary *primary = [self windowForSnapshot:snapshot key:@"primary"];
    NSDictionary *secondary = [self windowForSnapshot:snapshot key:@"secondary"];
    NSNumber *primaryUsed = [self numberFromDictionary:primary keys:appServerKeys ? @[@"usedPercent"] : @[@"used_percent"]];
    NSNumber *primaryReset = [self numberFromDictionary:primary keys:appServerKeys ? @[@"resetsAt"] : @[@"resets_at"]];
    NSNumber *primaryWindowMinutes = [self numberFromDictionary:primary keys:appServerKeys ? @[@"windowDurationMins"] : @[@"window_minutes"]];
    NSNumber *secondaryUsed = [self numberFromDictionary:secondary keys:appServerKeys ? @[@"usedPercent"] : @[@"used_percent"]];
    NSNumber *secondaryReset = [self numberFromDictionary:secondary keys:appServerKeys ? @[@"resetsAt"] : @[@"resets_at"]];
    NSNumber *secondaryWindowMinutes = [self numberFromDictionary:secondary keys:appServerKeys ? @[@"windowDurationMins"] : @[@"window_minutes"]];
    NSString *resetText = [self resetLabelForSeconds:primaryReset includeDate:NO];

    NSMutableDictionary *state = [@{
        @"ok": @YES,
        @"menu_title": primaryUsed != nil ? [NSString stringWithFormat:@"%@ | %.0f%%", resetText, primaryUsed.doubleValue] : @"--",
        @"primary_summary": [self rateLimitSummaryWithLabel:[self snapshotName:snapshot appServerKeys:appServerKeys]
                                                     window:primary
                                              appServerKeys:appServerKeys],
        @"updated_summary": [self updatedSummaryForDate:timestamp],
        @"source_summary": [NSString stringWithFormat:@"Source: %@", sourceText ?: @"unknown"]
    } mutableCopy];

    if (primaryUsed != nil) {
        state[@"primary_used_percent"] = primaryUsed;
    }
    if (primaryReset != nil) {
        state[@"primary_resets_at"] = primaryReset;
    }
    if (primaryWindowMinutes != nil) {
        state[@"primary_window_minutes"] = primaryWindowMinutes;
    }
    if (secondaryUsed != nil) {
        state[@"secondary_used_percent"] = secondaryUsed;
    }
    if (secondaryReset != nil) {
        state[@"secondary_resets_at"] = secondaryReset;
    }
    if (secondaryWindowMinutes != nil) {
        state[@"secondary_window_minutes"] = secondaryWindowMinutes;
    }

    NSString *weekly = [self weeklySummary:secondary appServerKeys:appServerKeys];
    if (weekly.length > 0) {
        state[@"weekly_summary"] = weekly;
    }

    NSString *credits = [self creditsSummary:[self dictionaryFromSnapshot:snapshot key:@"credits" appServerKeys:appServerKeys]];
    if (credits.length > 0) {
        state[@"credits_summary"] = credits;
    }

    NSString *plan = [self stringFromDictionary:snapshot keys:appServerKeys ? @[@"planType"] : @[@"plan_type"]];
    if (plan.length > 0) {
        state[@"plan_summary"] = [NSString stringWithFormat:@"Plan: %@", plan];
    }

    NSString *monthly = [self monthlySummary:[self dictionaryFromSnapshot:snapshot key:@"individualLimit" appServerKeys:appServerKeys]];
    if (monthly.length > 0) {
        state[@"monthly_summary"] = monthly;
    }

    return state;
}

- (NSDictionary *)windowForSnapshot:(NSDictionary *)snapshot key:(NSString *)key {
    id value = snapshot[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSDictionary *)dictionaryFromSnapshot:(NSDictionary *)snapshot key:(NSString *)key appServerKeys:(BOOL)appServerKeys {
    (void)appServerKeys;
    id value = snapshot[key];
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

- (NSString *)snapshotName:(NSDictionary *)snapshot appServerKeys:(BOOL)appServerKeys {
    NSString *name = [self stringFromDictionary:snapshot keys:appServerKeys ? @[@"limitName", @"limitId"] : @[@"limit_name", @"limit_id"]];
    return name.length > 0 ? name : @"Grok";
}

- (NSString *)rateLimitSummaryWithLabel:(NSString *)label window:(NSDictionary *)window appServerKeys:(BOOL)appServerKeys {
    if (window == nil) {
        return [NSString stringWithFormat:@"%@: unavailable", label ?: @"Grok"];
    }

    NSNumber *used = [self numberFromDictionary:window keys:appServerKeys ? @[@"usedPercent"] : @[@"used_percent"]];
    NSNumber *reset = [self numberFromDictionary:window keys:appServerKeys ? @[@"resetsAt"] : @[@"resets_at"]];
    NSString *usedText = [self percentSummaryTextForUsedPercent:used];
    NSString *resetText = [self resetLabelForSeconds:reset includeDate:NO];
    return [NSString stringWithFormat:@"%@: %@, resets %@", label ?: @"Grok", usedText, resetText];
}

- (NSString *)weeklySummary:(NSDictionary *)window appServerKeys:(BOOL)appServerKeys {
    if (window == nil) {
        return nil;
    }

    NSNumber *used = [self numberFromDictionary:window keys:appServerKeys ? @[@"usedPercent"] : @[@"used_percent"]];
    NSNumber *reset = [self numberFromDictionary:window keys:appServerKeys ? @[@"resetsAt"] : @[@"resets_at"]];
    NSString *usedText = [self percentSummaryTextForUsedPercent:used];
    NSString *resetText = [self resetLabelForSeconds:reset includeDate:YES];
    return [NSString stringWithFormat:@"Weekly: %@, resets %@", usedText, resetText];
}

- (NSString *)percentSummaryTextForUsedPercent:(NSNumber *)used {
    if (used == nil) {
        return [[self metricMode] isEqualToString:MetricModeUsed] ? @"--% used" : @"--% left";
    }

    double usedValue = MAX(0.0, MIN(100.0, used.doubleValue));
    if ([[self metricMode] isEqualToString:MetricModeUsed]) {
        return [NSString stringWithFormat:@"%.0f%% used", usedValue];
    }

    double leftValue = MAX(0.0, MIN(100.0, 100.0 - usedValue));
    return [NSString stringWithFormat:@"%.0f%% left, %.0f%% used", leftValue, usedValue];
}

- (NSString *)creditsSummary:(NSDictionary *)credits {
    if (credits == nil) {
        return nil;
    }
    NSNumber *unlimited = [credits[@"unlimited"] respondsToSelector:@selector(boolValue)] ? credits[@"unlimited"] : nil;
    if (unlimited.boolValue) {
        return @"Credits: unlimited";
    }
    id balance = credits[@"balance"];
    if ([balance isKindOfClass:[NSString class]] && [balance length] > 0) {
        return [NSString stringWithFormat:@"Credits: %@", balance];
    }
    if ([balance respondsToSelector:@selector(doubleValue)]) {
        return [NSString stringWithFormat:@"Credits: %.2f", [balance doubleValue]];
    }
    NSNumber *hasCredits = [credits[@"hasCredits"] respondsToSelector:@selector(boolValue)] ? credits[@"hasCredits"] : nil;
    if (hasCredits != nil && !hasCredits.boolValue) {
        return @"Credits: none";
    }
    return nil;
}

- (NSString *)monthlySummary:(NSDictionary *)monthly {
    if (monthly == nil) {
        return nil;
    }
    NSString *used = [self stringFromDictionary:monthly keys:@[@"used"]];
    NSString *limit = [self stringFromDictionary:monthly keys:@[@"limit"]];
    NSNumber *remaining = [self numberFromDictionary:monthly keys:@[@"remainingPercent"]];
    NSNumber *reset = [self numberFromDictionary:monthly keys:@[@"resetsAt"]];
    if (used.length == 0 && limit.length == 0 && remaining == nil) {
        return nil;
    }

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (used.length > 0 && limit.length > 0) {
        [parts addObject:[NSString stringWithFormat:@"%@ of %@", used, limit]];
    }
    if (remaining != nil) {
        [parts addObject:[NSString stringWithFormat:@"%ld%% left", (long)remaining.integerValue]];
    }
    if (reset != nil) {
        [parts addObject:[NSString stringWithFormat:@"resets %@", [self resetLabelForSeconds:reset includeDate:YES]]];
    }
    return [NSString stringWithFormat:@"Monthly: %@", [parts componentsJoinedByString:@", "]];
}

- (NSNumber *)numberFromDictionary:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    for (NSString *key in keys) {
        id value = dictionary[key];
        if ([value respondsToSelector:@selector(doubleValue)]) {
            return @([value doubleValue]);
        }
    }
    return nil;
}

- (NSString *)stringFromDictionary:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    for (NSString *key in keys) {
        id value = dictionary[key];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            return value;
        }
    }
    return nil;
}

- (NSString *)resetLabelForSeconds:(NSNumber *)seconds includeDate:(BOOL)includeDate {
    if (seconds == nil) {
        return @"unknown";
    }
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:seconds.doubleValue];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = includeDate ? NSDateFormatterMediumStyle : NSDateFormatterNoStyle;
    formatter.timeStyle = includeDate ? NSDateFormatterNoStyle : NSDateFormatterShortStyle;
    return [formatter stringFromDate:date];
}

- (NSString *)updatedSummaryForDate:(NSDate *)date {
    if (date == nil) {
        return @"Updated: unknown";
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterNoStyle;
    formatter.timeStyle = NSDateFormatterMediumStyle;
    return [NSString stringWithFormat:@"Updated: %@", [formatter stringFromDate:date]];
}

- (PersistentStartup *)startup {
    return StartupController(StartupLabel);
}

- (BOOL)launchAtLoginEnabled {
    return [NSFileManager.defaultManager fileExistsAtPath:self.startup.path] && self.startup.loaded;
}

- (NSString *)launchAtLoginStatusText {
    if ([self launchAtLoginEnabled]) return @"enabled";
    return [NSFileManager.defaultManager fileExistsAtPath:self.startup.path] ? @"inactive" : @"not_registered";
}

- (void)ensureLaunchAtLoginIfPreferred {
    NSError *error = nil;
    BOOL preferred = [NSUserDefaults.standardUserDefaults boolForKey:LaunchAtLoginPreferenceKey];
    BOOL ok = RemoveNativeLoginItem(&error) && [self.startup setEnabled:preferred error:&error];
    self.launchAtLoginError = ok ? nil : error.localizedDescription;
}

- (void)toggleLaunchAtLogin {
    NSError *error = nil;
    BOOL wasPreferred = [NSUserDefaults.standardUserDefaults boolForKey:LaunchAtLoginPreferenceKey];
    BOOL ok = RemoveNativeLoginItem(&error) && [self.startup setEnabled:!wasPreferred error:&error];
    if (ok) [NSUserDefaults.standardUserDefaults setBool:!wasPreferred forKey:LaunchAtLoginPreferenceKey];
    self.launchAtLoginError = ok ? nil : error.localizedDescription;
    self.statusItem.menu = [self menuForCurrentState];
}

- (void)quit {
    [NSApp terminate:nil];
}

- (NSAlert *)alertWithTitle:(NSString *)title message:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"";
    alert.informativeText = message ?: @"";
    alert.alertStyle = NSAlertStyleInformational;
    return alert;
}

- (void)checkForUpdates {
    if (self.checkingForUpdates) {
        return;
    }
    self.checkingForUpdates = YES;
    self.statusItem.menu = [self menuForCurrentState];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *update = GrokCheckForUpdates();
        dispatch_async(dispatch_get_main_queue(), ^{
            self.checkingForUpdates = NO;
            self.statusItem.menu = [self menuForCurrentState];
            [self handleUpdateCheckResult:update];
        });
    });
}

- (void)handleUpdateCheckResult:(NSDictionary *)update {
    [NSApp activateIgnoringOtherApps:YES];
    NSNumber *ok = update[@"ok"];
    if (![ok respondsToSelector:@selector(boolValue)] || ![ok boolValue]) {
        NSAlert *alert = [self alertWithTitle:@"Could not check for updates"
                                      message:update[@"error"] ?: @"The GitHub remote could not be reached."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    if (![update[@"updateAvailable"] boolValue]) {
        NSString *sha = GrokShortGitSHA(update[@"remoteSHA"] ?: update[@"currentSHA"]);
        NSAlert *alert = [self alertWithTitle:@"No updates"
                                      message:sha.length > 0
                                          ? [NSString stringWithFormat:@"You're on the latest main commit (%@).", sha]
                                          : @"You're on the latest main commit."];
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    NSAlert *alert = [self alertWithTitle:@"Update?"
                                  message:GrokUpdatePromptText(update)];
    [alert addButtonWithTitle:@"Yes"];
    [alert addButtonWithTitle:@"No"];
    if ([alert runModal] != NSAlertFirstButtonReturn) {
        return;
    }
    [self applyUpdate];
}

- (void)applyUpdate {
    self.checkingForUpdates = YES;
    self.statusItem.menu = [self menuForCurrentState];
    NSString *installPath = NSBundle.mainBundle.bundlePath;
    if (![installPath.pathExtension isEqualToString:@"app"]) {
        installPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Grok CLI Usage Menu Bar.app"];
    }

    NSError *pauseError = nil;
    [self.startup pause:&pauseError];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSDictionary *result = GrokApplyGitPullAndRebuild(installPath, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.checkingForUpdates = NO;
            self.statusItem.menu = [self menuForCurrentState];
            if (![result[@"ok"] boolValue]) {
                [NSApp activateIgnoringOtherApps:YES];
                NSAlert *alert = [self alertWithTitle:@"Update failed"
                                              message:result[@"error"] ?: error.localizedDescription ?: @"Unknown error"];
                [alert addButtonWithTitle:@"OK"];
                [alert runModal];
                [self ensureLaunchAtLoginIfPreferred];
                return;
            }
            NSString *appPath = result[@"appPath"] ?: installPath;
            NSTask *open = [[NSTask alloc] init];
            open.executableURL = [NSURL fileURLWithPath:@"/usr/bin/open"];
            open.arguments = @[@"-g", @"-n", appPath];
            [open launch];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [NSApp terminate:nil];
            });
        });
    });
}

- (BOOL)renderPreviewAtPath:(NSString *)path
                displayMode:(NSString *)displayMode
                      error:(NSError **)error {
    if (self.grokIcon == nil) {
        self.grokIcon = [self grokMenuBarIcon];
    }
    NSDictionary *state = [self loadUsageState];
    if (![state[@"ok"] boolValue]) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokPreview" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: state[@"error"] ?: @"Usage unavailable"}];
        }
        return NO;
    }

    double metric = [self displayPercentForWidgetState:state];
    if (isnan(metric)) {
        metric = 0.0;
    }
    double recommended = [self recommendedPercentLeftForWidgetState:state];
    NSImage *left = nil;
    if ([displayMode isEqualToString:DisplayModeBattery]) {
        left = [self batteryIconForPercent:metric recommendedPercent:recommended];
    } else {
        left = self.grokIcon;
    }

    NSString *timeText = [self countdownTextForWidgetState:state] ?: [self resetClockTextForWidgetState:state] ?: @"--";
    NSString *title = [displayMode isEqualToString:DisplayModeBattery]
        ? timeText
        : [NSString stringWithFormat:@"%@ | %.0f%%", timeText, metric];

    NSImage *canvas = [[NSImage alloc] initWithSize:NSMakeSize(284.0, 44.0)];
    [canvas lockFocus];
    [[NSColor colorWithCalibratedWhite:0.12 alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 284.0, 44.0));

    NSImage *tinted = [[NSImage alloc] initWithSize:left.size];
    [tinted lockFocus];
    [left drawInRect:NSMakeRect(0.0, 0.0, left.size.width, left.size.height)];
    [NSColor.whiteColor setFill];
    NSRectFillUsingOperation(NSMakeRect(0.0, 0.0, left.size.width, left.size.height),
                             NSCompositingOperationSourceAtop);
    [tinted unlockFocus];

    CGFloat iconY = (44.0 - left.size.height) / 2.0;
    [tinted drawInRect:NSMakeRect(16.0, iconY, left.size.width, left.size.height)];

    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:15.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    [title drawAtPoint:NSMakePoint(16.0 + left.size.width + 8.0, 12.0) withAttributes:attributes];
    [canvas unlockFocus];
    return GrokWritePNG(canvas, path, error);
}

@end

static int RunDumpUsage(void) {
    @autoreleasepool {
        AppDelegate *delegate = [AppDelegate new];
        NSDictionary *state = [delegate loadUsageState];
        NSMutableDictionary *sanitized = [NSMutableDictionary dictionary];
        for (NSString *key in state) {
            if ([key containsString:@"token"] || [key containsString:@"key"]) {
                continue;
            }
            sanitized[key] = state[key];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:sanitized options:NSJSONWritingPrettyPrinted error:nil];
        if (data != nil) {
            fwrite(data.bytes, 1, data.length, stdout);
            fputc('\n', stdout);
        }
        NSNumber *ok = state[@"ok"];
        return [ok respondsToSelector:@selector(boolValue)] && [ok boolValue] ? 0 : 1;
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "--pause-startup") == 0) {
            NSError *error = nil;
            BOOL ok = [StartupController(StartupLabel) pause:&error];
            if (!ok) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return ok ? 0 : 1;
        }
        if (argc > 1 && strcmp(argv[1], "--launch-at-login-status") == 0) {
            printf("%s\n", [[AppDelegate new] launchAtLoginStatusText].UTF8String);
            return 0;
        }
        if (argc > 1 && strcmp(argv[1], "--dump-usage") == 0) {
            return RunDumpUsage();
        }
        if (argc > 1 && strcmp(argv[1], "--check-updates") == 0) {
            NSDictionary *update = GrokCheckForUpdates();
            NSData *data = [NSJSONSerialization isValidJSONObject:update]
                ? [NSJSONSerialization dataWithJSONObject:update options:NSJSONWritingPrettyPrinted error:nil]
                : nil;
            if (data != nil) {
                fwrite(data.bytes, 1, data.length, stdout);
                fputc('\n', stdout);
            }
            return [update[@"ok"] boolValue] ? 0 : 1;
        }
        if (argc > 2 && strcmp(argv[1], "--render-icon") == 0) {
            [NSApplication sharedApplication];
            NSError *error = nil;
            BOOL ok = GrokWritePNG(GrokBlackHoleIconWithSize(256.0), @(argv[2]), &error);
            if (!ok) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return ok ? 0 : 1;
        }
        if (argc > 3 && strcmp(argv[1], "--render-preview") == 0) {
            [NSApplication sharedApplication];
            AppDelegate *delegate = [AppDelegate new];
            NSError *error = nil;
            BOOL ok = [delegate renderPreviewAtPath:@(argv[2]) displayMode:@(argv[3]) error:&error];
            if (!ok) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return ok ? 0 : 1;
        }
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
