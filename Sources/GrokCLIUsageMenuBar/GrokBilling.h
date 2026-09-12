#ifndef GrokBilling_h
#define GrokBilling_h

#import <Foundation/Foundation.h>
#import <math.h>

static NSDate *GrokParseISODate(id value) {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *string = value;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *date = [formatter dateFromString:string];
    if (date != nil) {
        return date;
    }
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    date = [formatter dateFromString:string];
    if (date != nil) {
        return date;
    }
    NSString *normalized = [string stringByReplacingOccurrencesOfString:@"+00:00" withString:@"Z"];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    date = [formatter dateFromString:normalized];
    if (date != nil) {
        return date;
    }
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    return [formatter dateFromString:normalized];
}

static NSNumber *GrokCentValue(id value) {
    if ([value isKindOfClass:[NSDictionary class]]) {
        id inner = value[@"val"];
        if ([inner respondsToSelector:@selector(doubleValue)]) {
            return @([inner doubleValue]);
        }
        return nil;
    }
    if ([value respondsToSelector:@selector(doubleValue)]) {
        return @([value doubleValue]);
    }
    return nil;
}

static NSNumber *GrokNumberValue(id value) {
    if ([value respondsToSelector:@selector(doubleValue)] &&
        ![value isKindOfClass:[NSString class]] &&
        ![value isKindOfClass:[NSDictionary class]]) {
        return @([value doubleValue]);
    }
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        return @([value doubleValue]);
    }
    return GrokCentValue(value);
}

static NSString *GrokPeriodKind(id type) {
    if (![type isKindOfClass:[NSString class]]) {
        return @"period";
    }
    NSString *upper = [type uppercaseString];
    if ([upper containsString:@"WEEKLY"]) {
        return @"weekly";
    }
    if ([upper containsString:@"MONTHLY"]) {
        return @"monthly";
    }
    if ([upper containsString:@"DAILY"] || [upper containsString:@"HOUR"]) {
        return @"daily";
    }
    return @"period";
}

static NSString *GrokHumanProductName(id product) {
    if (![product isKindOfClass:[NSString class]] || [product length] == 0) {
        return @"Product";
    }
    NSString *name = product;
    if ([name hasPrefix:@"PRODUCT_"]) {
        name = [name substringFromIndex:8];
    }
    name = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    if ([name.uppercaseString hasPrefix:@"GROK "]) {
        name = [name substringFromIndex:5];
    }
    static NSDictionary<NSString *, NSString *> *aliases;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        aliases = @{
            @"GrokChat": @"Chat",
            @"GrokBuild": @"Build",
            @"GrokImagine": @"Imagine",
            @"GrokVoice": @"Voice",
            @"GROK CHAT": @"Chat",
            @"GROK BUILD": @"Build",
            @"Api": @"API",
            @"API": @"API",
            @"Chat": @"Chat",
            @"Build": @"Build",
            @"Imagine": @"Imagine",
            @"Voice": @"Voice"
        };
    });
    NSString *mapped = aliases[product] ?: aliases[name] ?: aliases[name.capitalizedString];
    if (mapped.length > 0) {
        return mapped;
    }
    if ([name hasPrefix:@"Grok"] && name.length > 4) {
        return [name substringFromIndex:4];
    }
    return name.capitalizedString;
}

static NSMutableDictionary *GrokWindowDict(double usedPercent, NSDate *start, NSDate *end, NSString *kind) {
    NSMutableDictionary *window = [NSMutableDictionary dictionary];
    if (isfinite(usedPercent)) {
        window[@"usedPercent"] = @(MAX(0.0, MIN(100.0, usedPercent)));
    }
    if (end != nil) {
        window[@"resetsAt"] = @(end.timeIntervalSince1970);
    }
    double minutes = NAN;
    if (start != nil && end != nil) {
        minutes = [end timeIntervalSinceDate:start] / 60.0;
    } else if ([kind isEqualToString:@"weekly"]) {
        minutes = 7.0 * 24.0 * 60.0;
    } else if ([kind isEqualToString:@"monthly"]) {
        minutes = 30.0 * 24.0 * 60.0;
    } else if ([kind isEqualToString:@"daily"]) {
        minutes = 24.0 * 60.0;
    }
    if (isfinite(minutes) && minutes > 0.0) {
        window[@"windowDurationMins"] = @(minutes);
    }
    return window;
}

static double GrokUsedPercentFromConfig(NSDictionary *config) {
    id percent = config[@"creditUsagePercent"];
    if ([percent respondsToSelector:@selector(doubleValue)] && ![percent isKindOfClass:[NSDictionary class]]) {
        return MAX(0.0, MIN(100.0, [percent doubleValue]));
    }

    NSNumber *monthlyLimit = GrokCentValue(config[@"monthlyLimit"]);
    NSNumber *used = GrokCentValue(config[@"used"]);
    if (used == nil) {
        NSDictionary *usage = [config[@"usage"] isKindOfClass:[NSDictionary class]] ? config[@"usage"] : nil;
        used = GrokCentValue(usage[@"totalUsed"]) ?: GrokCentValue(usage[@"includedUsed"]);
    }
    if (monthlyLimit != nil && monthlyLimit.doubleValue > 0.0 && used != nil) {
        return MAX(0.0, MIN(100.0, (used.doubleValue / monthlyLimit.doubleValue) * 100.0));
    }

    NSNumber *cap = GrokCentValue(config[@"onDemandCap"]);
    NSNumber *onDemandUsed = GrokCentValue(config[@"onDemandUsed"]);
    if (cap != nil && cap.doubleValue > 0.0 && onDemandUsed != nil) {
        return MAX(0.0, MIN(100.0, (onDemandUsed.doubleValue / cap.doubleValue) * 100.0));
    }

    if ([config[@"currentPeriod"] isKindOfClass:[NSDictionary class]] ||
        [config[@"billingPeriodEnd"] isKindOfClass:[NSString class]]) {
        return 0.0;
    }
    return NAN;
}

// Maps the Grok CLI `/usage` billing payload onto the same snapshot shape the
// Codex menu bar uses: primary/secondary windows, credits, plan, products.
static NSDictionary *GrokSnapshotFromBillingObject(id json, NSString *planName) {
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *root = json;
    if ([root[@"result"] isKindOfClass:[NSDictionary class]]) {
        root = root[@"result"];
    }
    NSDictionary *config = [root[@"config"] isKindOfClass:[NSDictionary class]] ? root[@"config"] : root;
    if (![config isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    NSDictionary *period = [config[@"currentPeriod"] isKindOfClass:[NSDictionary class]] ? config[@"currentPeriod"] : nil;
    NSString *kind = GrokPeriodKind(period[@"type"]);
    NSDate *start = GrokParseISODate(period[@"start"] ?: config[@"billingPeriodStart"]);
    NSDate *end = GrokParseISODate(period[@"end"] ?: config[@"billingPeriodEnd"]);
    double usedPercent = GrokUsedPercentFromConfig(config);
    if (isnan(usedPercent) && end == nil) {
        return nil;
    }

    NSMutableDictionary *primary = GrokWindowDict(usedPercent, start, end, kind);
    NSMutableDictionary *snapshot = [@{
        @"limitName": @"Grok",
        @"limitId": @"grok",
        @"primary": primary
    } mutableCopy];
    snapshot[@"periodKind"] = kind;

    NSString *plan = planName;
    if (plan.length == 0) {
        plan = [root[@"subscriptionTier"] isKindOfClass:[NSString class]] ? root[@"subscriptionTier"] : nil;
    }
    if (plan.length == 0) {
        plan = [config[@"subscriptionTier"] isKindOfClass:[NSString class]] ? config[@"subscriptionTier"] : nil;
    }
    if (plan.length > 0) {
        snapshot[@"planType"] = plan;
    }

    NSNumber *prepaid = GrokCentValue(config[@"prepaidBalance"]);
    if (prepaid != nil && prepaid.doubleValue > 0.0) {
        snapshot[@"credits"] = @{
            @"balance": [NSString stringWithFormat:@"$%.2f", prepaid.doubleValue / 100.0],
            @"hasCredits": @YES
        };
    }

    NSNumber *monthlyLimit = GrokCentValue(config[@"monthlyLimit"]);
    NSNumber *monthlyUsed = GrokCentValue(config[@"used"]);
    if (monthlyUsed == nil) {
        NSDictionary *usage = [config[@"usage"] isKindOfClass:[NSDictionary class]] ? config[@"usage"] : nil;
        monthlyUsed = GrokCentValue(usage[@"totalUsed"]) ?: GrokCentValue(usage[@"includedUsed"]);
    }
    if (monthlyLimit != nil && monthlyLimit.doubleValue > 0.0 && monthlyUsed != nil) {
        double remaining = MAX(0.0, MIN(100.0, 100.0 - (monthlyUsed.doubleValue / monthlyLimit.doubleValue) * 100.0));
        NSMutableDictionary *monthly = [@{
            @"used": [NSString stringWithFormat:@"$%.2f", monthlyUsed.doubleValue / 100.0],
            @"limit": [NSString stringWithFormat:@"$%.2f", monthlyLimit.doubleValue / 100.0],
            @"remainingPercent": @(remaining)
        } mutableCopy];
        NSDate *monthlyEnd = GrokParseISODate(config[@"billingPeriodEnd"]);
        if (monthlyEnd != nil) {
            monthly[@"resetsAt"] = @(monthlyEnd.timeIntervalSince1970);
        }
        snapshot[@"individualLimit"] = monthly;

        if (![kind isEqualToString:@"monthly"]) {
            double monthlyPercent = MAX(0.0, MIN(100.0, (monthlyUsed.doubleValue / monthlyLimit.doubleValue) * 100.0));
            NSDate *monthlyStart = GrokParseISODate(config[@"billingPeriodStart"]);
            snapshot[@"secondary"] = GrokWindowDict(monthlyPercent, monthlyStart, monthlyEnd, @"monthly");
        }
    }

    NSNumber *onDemandCap = GrokCentValue(config[@"onDemandCap"]);
    NSNumber *onDemandUsed = GrokCentValue(config[@"onDemandUsed"]);
    if (onDemandCap != nil && onDemandCap.doubleValue > 0.0) {
        snapshot[@"onDemandCap"] = onDemandCap;
        snapshot[@"onDemandUsed"] = onDemandUsed ?: @(0);
    }

    NSMutableArray<NSDictionary *> *products = [NSMutableArray array];
    id productUsage = config[@"productUsage"];
    if ([productUsage isKindOfClass:[NSArray class]]) {
        for (id item in productUsage) {
            if (![item isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            id percent = item[@"usagePercent"];
            if (![percent respondsToSelector:@selector(doubleValue)]) {
                continue;
            }
            [products addObject:@{
                @"name": GrokHumanProductName(item[@"product"]),
                @"usedPercent": @(MAX(0.0, MIN(100.0, [percent doubleValue])))
            }];
        }
    }
    if (products.count > 0) {
        snapshot[@"productUsage"] = products;
    }

    return snapshot;
}

#endif
