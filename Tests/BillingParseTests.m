#import "GrokBilling.h"

static NSDictionary *JSON(NSString *string) {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

int main(void) {
    @autoreleasepool {
        NSDate *weekly = GrokParseISODate(@"2026-09-07T20:46:03.951015+00:00");
        NSCAssert(weekly != nil, @"Should parse Grok billing timestamps with 6 fractional digits");
        NSCAssert(GrokParseISODate(@"2026-09-12T06:39:38.435791Z") != nil, @"Should parse Z timestamps");
        NSCAssert(GrokParseISODate(@"2026-09-07T20:46:03Z") != nil, @"Should parse whole-second Z timestamps");

        NSCAssert([GrokHumanProductName(@"GrokChat") isEqual:@"Chat"], @"GrokChat");
        NSCAssert([GrokHumanProductName(@"GrokBuild") isEqual:@"Build"], @"GrokBuild");
        NSCAssert([GrokHumanProductName(@"PRODUCT_GROK_BUILD") isEqual:@"Build"], @"PRODUCT_GROK_BUILD");
        NSCAssert([GrokHumanProductName(@"Api") isEqual:@"API"], @"Api");

        NSDictionary *live = JSON(@"{ \"config\": { "
            "\"currentPeriod\": { \"type\": \"USAGE_PERIOD_TYPE_WEEKLY\", "
            "\"start\": \"2026-09-07T20:46:03.951015+00:00\", "
            "\"end\": \"2026-09-14T20:46:03.951015+00:00\" }, "
            "\"creditUsagePercent\": 1.0, "
            "\"onDemandCap\": { \"val\": 0 }, "
            "\"onDemandUsed\": { \"val\": 0 }, "
            "\"productUsage\": [ { \"product\": \"GrokChat\", \"usagePercent\": 1.0 }, { \"product\": \"GrokBuild\" } ], "
            "\"isUnifiedBillingUser\": true, "
            "\"prepaidBalance\": { \"val\": 0 } } }");
        NSDictionary *snapshot = GrokSnapshotFromBillingObject(live, @"X Premium+");
        NSCAssert(snapshot != nil, @"Live weekly payload should parse");
        NSCAssert([snapshot[@"planType"] isEqual:@"X Premium+"], @"Plan name");
        NSCAssert([snapshot[@"periodKind"] isEqual:@"weekly"], @"Weekly period");
        NSCAssert(fabs([snapshot[@"primary"][@"usedPercent"] doubleValue] - 1.0) < 0.001, @"Used percent");
        NSCAssert(fabs([snapshot[@"primary"][@"windowDurationMins"] doubleValue] - 10080.0) < 0.1, @"Seven-day window");
        NSCAssert(snapshot[@"credits"] == nil, @"Zero prepaid should be omitted");
        NSCAssert([snapshot[@"productUsage"] count] == 1, @"Products without a percent are skipped");
        NSCAssert([snapshot[@"productUsage"][0][@"name"] isEqual:@"Chat"], @"Chat product");

        NSDictionary *legacy = JSON(@"{ \"config\": { "
            "\"monthlyLimit\": { \"val\": 99900 }, "
            "\"used\": { \"val\": 24975 }, "
            "\"billingPeriodStart\": \"2026-07-01T00:00:00Z\", "
            "\"billingPeriodEnd\": \"2026-08-01T00:00:00Z\" } }");
        NSDictionary *legacySnapshot = GrokSnapshotFromBillingObject(legacy, nil);
        NSCAssert(fabs([legacySnapshot[@"primary"][@"usedPercent"] doubleValue] - 25.0) < 0.001, @"Legacy monthly percent");
        NSCAssert(legacySnapshot[@"individualLimit"] != nil, @"Monthly dollars");

        NSDictionary *zero = JSON(@"{ \"config\": { "
            "\"currentPeriod\": { \"type\": \"USAGE_PERIOD_TYPE_WEEKLY\", "
            "\"start\": \"2026-08-16T12:54:39Z\", \"end\": \"2026-08-23T12:54:39Z\" } } }");
        NSDictionary *zeroSnapshot = GrokSnapshotFromBillingObject(zero, nil);
        NSCAssert(fabs([zeroSnapshot[@"primary"][@"usedPercent"] doubleValue] - 0.0) < 0.001,
                  @"A confirmed weekly period with no percent is zero usage");

        NSCAssert(GrokSnapshotFromBillingObject(@{@"nope": @1}, nil) == nil,
                  @"Unrelated JSON should not produce a snapshot");
        NSCAssert([GrokPeriodKind(@"USAGE_PERIOD_TYPE_MONTHLY") isEqual:@"monthly"], @"Monthly kind");
        puts("Billing parse tests passed");
    }
    return 0;
}
