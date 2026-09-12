#ifndef GrokAuth_h
#define GrokAuth_h

#import <Foundation/Foundation.h>
#import "GrokBilling.h"

static NSString *GrokHomePath(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"GROK_HOME"];
    if (override.length > 0) {
        return override.stringByExpandingTildeInPath.stringByStandardizingPath;
    }
    return [@"~/.grok" stringByExpandingTildeInPath].stringByStandardizingPath;
}

static NSString *GrokAuthPath(void) {
    return [GrokHomePath() stringByAppendingPathComponent:@"auth.json"];
}

static NSString *GrokProxyBaseURL(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"GROK_CLI_CHAT_PROXY_BASE_URL"];
    if (override.length == 0) {
        override = @"https://cli-chat-proxy.grok.com/v1";
    }
    while ([override hasSuffix:@"/"]) {
        override = [override substringToIndex:override.length - 1];
    }
    return override;
}

static NSString *GrokURLEncode(NSString *value) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSDictionary *GrokJSONFromData(NSData *data) {
    if (data.length == 0) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

static NSData *GrokHTTPRequest(NSString *method,
                               NSString *urlString,
                               NSDictionary<NSString *, NSString *> *headers,
                               NSData *body,
                               NSInteger *status,
                               NSError **error) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokAuth" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}];
        }
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method ?: @"GET";
    request.timeoutInterval = 15.0;
    request.HTTPBody = body;
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        (void)stop;
        [request setValue:value forHTTPHeaderField:key];
    }];

    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 15.0;
    config.timeoutIntervalForResource = 20.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSHTTPURLResponse *http = nil;
    __block NSError *taskError = nil;
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        responseData = data;
        http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        taskError = err;
        dispatch_semaphore_signal(done);
    }] resume];

    long timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)));
    [session finishTasksAndInvalidate];
    if (timedOut != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokAuth" code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Request timed out"}];
        }
        return nil;
    }
    if (status) {
        *status = http.statusCode;
    }
    if (taskError != nil) {
        if (error) {
            *error = taskError;
        }
        return nil;
    }
    return responseData;
}

static NSDictionary *GrokHTTPGetJSON(NSString *urlString,
                                     NSString *accessToken,
                                     NSString *userId,
                                     NSInteger *status,
                                     NSError **error) {
    NSMutableDictionary *headers = [@{
        @"Authorization": [NSString stringWithFormat:@"Bearer %@", accessToken ?: @""],
        @"Accept": @"application/json",
        @"X-XAI-Token-Auth": @"xai-grok-cli",
        @"x-grok-client-mode": @"cli",
        @"User-Agent": @"GrokCLIUsageMenuBar/0.1"
    } mutableCopy];
    if (userId.length > 0) {
        headers[@"x-userid"] = userId;
    }
    NSData *data = GrokHTTPRequest(@"GET", urlString, headers, nil, status, error);
    if (data == nil) {
        return nil;
    }
    NSDictionary *json = GrokJSONFromData(data);
    if (json == nil && error && *error == nil) {
        *error = [NSError errorWithDomain:@"GrokAuth" code:3
                                 userInfo:@{NSLocalizedDescriptionKey: @"Billing response was not JSON"}];
    }
    return json;
}

static NSDictionary *GrokSelectAuthEntry(NSDictionary *root) {
    NSDictionary *oidc = nil;
    NSDictionary *legacy = nil;
    NSDictionary *other = nil;
    NSString *oidcKey = nil;
    NSString *legacyKey = nil;
    NSString *otherKey = nil;

    for (id key in root) {
        if (![key isKindOfClass:[NSString class]]) {
            continue;
        }
        id value = root[key];
        if (![value isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *token = value[@"key"] ?: value[@"access_token"];
        if (![token isKindOfClass:[NSString class]] || token.length == 0) {
            continue;
        }
        if ([key hasPrefix:@"https://auth.x.ai::"]) {
            oidc = value;
            oidcKey = key;
        } else if ([key isEqualToString:@"https://accounts.x.ai/sign-in"]) {
            legacy = value;
            legacyKey = key;
        } else if (other == nil) {
            other = value;
            otherKey = key;
        }
    }

    NSDictionary *entry = oidc ?: legacy ?: other;
    NSString *scope = oidcKey ?: legacyKey ?: otherKey;
    if (entry == nil || scope == nil) {
        return nil;
    }
    return @{@"scope": scope, @"entry": entry};
}

static NSMutableDictionary *GrokAuthInfoFromFile(NSString *path, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (data == nil) {
        if (error && *error == nil) {
            *error = [NSError errorWithDomain:@"GrokAuth" code:4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Grok CLI is not signed in. Run grok login."}];
        }
        return nil;
    }
    NSDictionary *root = GrokJSONFromData(data);
    if (root == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokAuth" code:5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not read ~/.grok/auth.json"}];
        }
        return nil;
    }
    NSDictionary *selected = GrokSelectAuthEntry(root);
    if (selected == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokAuth" code:6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Grok CLI is not signed in. Run grok login."}];
        }
        return nil;
    }

    NSDictionary *entry = selected[@"entry"];
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"scope"] = selected[@"scope"];
    info[@"root"] = [root mutableCopy];
    info[@"accessToken"] = entry[@"key"] ?: entry[@"access_token"];
    if ([entry[@"refresh_token"] isKindOfClass:[NSString class]]) {
        info[@"refreshToken"] = entry[@"refresh_token"];
    }
    if ([entry[@"user_id"] isKindOfClass:[NSString class]]) {
        info[@"userId"] = entry[@"user_id"];
    }
    if ([entry[@"email"] isKindOfClass:[NSString class]]) {
        info[@"email"] = entry[@"email"];
    }
    NSString *clientId = entry[@"oidc_client_id"];
    if (![clientId isKindOfClass:[NSString class]] || clientId.length == 0) {
        NSString *scope = selected[@"scope"];
        NSRange marker = [scope rangeOfString:@"::"];
        if (marker.location != NSNotFound) {
            clientId = [scope substringFromIndex:NSMaxRange(marker)];
        }
    }
    if (clientId.length > 0) {
        info[@"clientId"] = clientId;
    }
    NSString *issuer = entry[@"oidc_issuer"];
    if (![issuer isKindOfClass:[NSString class]] || issuer.length == 0) {
        issuer = @"https://auth.x.ai";
    }
    info[@"issuer"] = issuer;
    NSDate *expires = GrokParseISODate(entry[@"expires_at"]);
    if (expires != nil) {
        info[@"expiresAt"] = expires;
    }
    info[@"path"] = path;
    return info;
}

static BOOL GrokWriteAuthFile(NSMutableDictionary *info, NSError **error) {
    NSString *path = info[@"path"];
    NSString *scope = info[@"scope"];
    NSMutableDictionary *root = info[@"root"];
    if (path.length == 0 || scope.length == 0 || ![root isKindOfClass:[NSMutableDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokAuth" code:7
                                     userInfo:@{NSLocalizedDescriptionKey: @"Cannot update Grok credentials"}];
        }
        return NO;
    }

    NSMutableDictionary *entry = [[root[scope] isKindOfClass:[NSDictionary class]]
                                  ? root[scope]
                                  : @{} mutableCopy];
    if ([info[@"accessToken"] isKindOfClass:[NSString class]]) {
        entry[@"key"] = info[@"accessToken"];
    }
    if ([info[@"refreshToken"] isKindOfClass:[NSString class]]) {
        entry[@"refresh_token"] = info[@"refreshToken"];
    }
    NSDate *expires = info[@"expiresAt"];
    if ([expires isKindOfClass:[NSDate class]]) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        entry[@"expires_at"] = [formatter stringFromDate:expires];
    }
    root[scope] = entry;

    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:error];
    if (data == nil) {
        return NO;
    }
    if (![data writeToFile:path options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                     ofItemAtPath:path
                                            error:nil];
    return YES;
}

static NSString *GrokDiscoverTokenEndpoint(NSString *issuer) {
    NSString *base = issuer.length > 0 ? issuer : @"https://auth.x.ai";
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    NSInteger status = 0;
    NSError *error = nil;
    NSData *data = GrokHTTPRequest(@"GET",
                                   [base stringByAppendingString:@"/.well-known/openid-configuration"],
                                   @{@"Accept": @"application/json"},
                                   nil,
                                   &status,
                                   &error);
    NSDictionary *json = GrokJSONFromData(data);
    NSString *endpoint = json[@"token_endpoint"];
    if ([endpoint isKindOfClass:[NSString class]] && endpoint.length > 0) {
        return endpoint;
    }
    return @"https://auth.x.ai/oauth2/token";
}

static BOOL GrokRefreshAccessToken(NSMutableDictionary *info, NSError **error) {
    NSString *refreshToken = info[@"refreshToken"];
    NSString *clientId = info[@"clientId"];
    if (refreshToken.length == 0 || clientId.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokAuth" code:8
                                     userInfo:@{NSLocalizedDescriptionKey: @"Grok session expired. Run grok login."}];
        }
        return NO;
    }

    NSString *endpoint = GrokDiscoverTokenEndpoint(info[@"issuer"]);
    NSString *bodyString = [NSString stringWithFormat:@"grant_type=refresh_token&client_id=%@&refresh_token=%@",
                            GrokURLEncode(clientId), GrokURLEncode(refreshToken)];
    NSData *body = [bodyString dataUsingEncoding:NSUTF8StringEncoding];
    NSInteger status = 0;
    NSError *requestError = nil;
    NSData *data = GrokHTTPRequest(@"POST",
                                   endpoint,
                                   @{
                                       @"Content-Type": @"application/x-www-form-urlencoded",
                                       @"Accept": @"application/json"
                                   },
                                   body,
                                   &status,
                                   &requestError);
    NSDictionary *json = GrokJSONFromData(data);
    NSString *access = json[@"access_token"];
    if (status < 200 || status >= 300 || ![access isKindOfClass:[NSString class]] || access.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokAuth" code:9
                                     userInfo:@{NSLocalizedDescriptionKey: @"Grok session expired. Run grok login."}];
        }
        return NO;
    }

    info[@"accessToken"] = access;
    if ([json[@"refresh_token"] isKindOfClass:[NSString class]] && [json[@"refresh_token"] length] > 0) {
        info[@"refreshToken"] = json[@"refresh_token"];
    }
    id expiresIn = json[@"expires_in"];
    NSTimeInterval lifetime = [expiresIn respondsToSelector:@selector(doubleValue)] ? [expiresIn doubleValue] : 6.0 * 3600.0;
    if (lifetime <= 0) {
        lifetime = 6.0 * 3600.0;
    }
    info[@"expiresAt"] = [NSDate dateWithTimeIntervalSinceNow:lifetime];
    return GrokWriteAuthFile(info, error);
}

static BOOL GrokTokenNeedsRefresh(NSDictionary *info) {
    NSDate *expires = info[@"expiresAt"];
    if (![expires isKindOfClass:[NSDate class]]) {
        return NO;
    }
    return [expires timeIntervalSinceNow] < 120.0;
}

static NSMutableDictionary *GrokLoadFreshAuth(NSError **error) {
    NSMutableDictionary *info = GrokAuthInfoFromFile(GrokAuthPath(), error);
    if (info == nil) {
        return nil;
    }
    if (GrokTokenNeedsRefresh(info)) {
        NSError *refreshError = nil;
        if (!GrokRefreshAccessToken(info, &refreshError)) {
            if (error) {
                *error = refreshError;
            }
            return nil;
        }
    }
    return info;
}

#endif
