#import "GrokAuth.h"

int main(void) {
    @autoreleasepool {
        NSString *json = @"{"
            "\"https://auth.x.ai::b1a00492-073a-47ea-816f-4c329264a828\": {"
            "\"auth_mode\": \"oidc\","
            "\"key\": \"access-token\","
            "\"refresh_token\": \"refresh-token\","
            "\"expires_at\": \"2099-01-01T00:00:00Z\","
            "\"oidc_client_id\": \"b1a00492-073a-47ea-816f-4c329264a828\","
            "\"oidc_issuer\": \"https://auth.x.ai\","
            "\"user_id\": \"user-1\","
            "\"email\": \"user@example.com\""
            "},"
            "\"https://accounts.x.ai/sign-in\": {"
            "\"key\": \"legacy-token\""
            "}"
            "}";
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"grok-auth-test.json"];
        NSCAssert([[json dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES], @"write fixture");
        NSError *error = nil;
        NSMutableDictionary *info = GrokAuthInfoFromFile(path, &error);
        NSCAssert(info != nil, @"Should parse auth.json");
        NSCAssert([info[@"accessToken"] isEqual:@"access-token"], @"Prefer OIDC over legacy session");
        NSCAssert([info[@"userId"] isEqual:@"user-1"], @"user id");
        NSCAssert([info[@"clientId"] isEqual:@"b1a00492-073a-47ea-816f-4c329264a828"], @"client id");
        NSCAssert(!GrokTokenNeedsRefresh(info), @"Far-future expiry should not refresh");

        info[@"expiresAt"] = [NSDate dateWithTimeIntervalSinceNow:-10];
        NSCAssert(GrokTokenNeedsRefresh(info), @"Expired tokens need refresh");

        NSCAssert([GrokURLEncode(@"a b/c") isEqual:@"a%20b%2Fc"], @"Form encoding");
        NSCAssert([GrokHomePath() length] > 0, @"Grok home");
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        puts("Auth parse tests passed");
    }
    return 0;
}
