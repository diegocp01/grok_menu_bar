#ifndef GrokUpdater_h
#define GrokUpdater_h

#import <Foundation/Foundation.h>
#import "GrokAuth.h"

static NSString * const GrokDefaultGitRemote = @"https://github.com/diegocp01/grok_menu_bar.git";
static NSString * const GrokSourceRepoPathKey = @"sourceRepoPath";

static NSString *GrokTrimGitSHA(NSString *sha) {
    if (![sha isKindOfClass:[NSString class]]) {
        return @"";
    }
    return [[sha stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
}

static BOOL GrokGitSHAsEqual(NSString *left, NSString *right) {
    NSString *a = GrokTrimGitSHA(left);
    NSString *b = GrokTrimGitSHA(right);
    if (a.length == 0 || b.length == 0) {
        return NO;
    }
    NSUInteger n = MIN(a.length, b.length);
    if (n < 7) {
        return [a isEqualToString:b];
    }
    return [[a substringToIndex:n] isEqualToString:[b substringToIndex:n]];
}

static NSString *GrokShortGitSHA(NSString *sha) {
    NSString *trimmed = GrokTrimGitSHA(sha);
    if (trimmed.length >= 7) {
        return [trimmed substringToIndex:7];
    }
    return trimmed;
}

static NSDictionary<NSString *, NSString *> *GrokGitHubRepoFromRemote(NSString *remote) {
    if (![remote isKindOfClass:[NSString class]] || remote.length == 0) {
        remote = GrokDefaultGitRemote;
    }
    NSString *value = remote;
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    value = [value stringByReplacingOccurrencesOfString:@".git" withString:@""];
    value = [value stringByReplacingOccurrencesOfString:@"git@github.com:" withString:@"https://github.com/"];
    value = [value stringByReplacingOccurrencesOfString:@"ssh://git@github.com/" withString:@"https://github.com/"];
    NSURL *url = [NSURL URLWithString:value];
    NSArray<NSString *> *parts = [url.path componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *tokens = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) {
            [tokens addObject:part];
        }
    }
    if (tokens.count < 2) {
        return @{@"owner": @"diegocp01", @"name": @"grok_menu_bar"};
    }
    return @{@"owner": tokens[tokens.count - 2], @"name": tokens[tokens.count - 1]};
}

static BOOL GrokRemotePointsAtAppRepo(NSString *remote) {
    NSDictionary *repo = GrokGitHubRepoFromRemote(remote);
    return [repo[@"name"] isEqualToString:@"grok_menu_bar"];
}

static NSString *GrokFirstLine(NSString *text) {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        return @"";
    }
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length > 0) {
            return trimmed;
        }
    }
    return @"";
}

static NSArray<NSString *> *GrokCommitSummariesFromGitHub(id commits) {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    if (![commits isKindOfClass:[NSArray class]]) {
        return items;
    }
    for (id commit in commits) {
        if (![commit isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *message = nil;
        id inner = commit[@"commit"];
        if ([inner isKindOfClass:[NSDictionary class]] && [inner[@"message"] isKindOfClass:[NSString class]]) {
            message = inner[@"message"];
        } else if ([commit[@"message"] isKindOfClass:[NSString class]]) {
            message = commit[@"message"];
        }
        NSString *line = GrokFirstLine(message);
        if (line.length > 0) {
            [items addObject:line];
        }
    }
    return items;
}

// Parses GitHub compare JSON, or a single commit payload from /commits/main.
static NSDictionary *GrokParseGitHubUpdatePayload(id json, NSString *currentSHA) {
    if (![json isKindOfClass:[NSDictionary class]]) {
        return @{@"ok": @NO, @"error": @"GitHub returned invalid JSON"};
    }

    NSString *remoteSHA = nil;
    NSInteger aheadBy = 0;
    NSArray<NSString *> *summaries = @[];

    if ([json[@"sha"] isKindOfClass:[NSString class]]) {
        remoteSHA = json[@"sha"];
        summaries = GrokCommitSummariesFromGitHub(json[@"commit"] ? @[json] : @[]);
        aheadBy = GrokGitSHAsEqual(currentSHA, remoteSHA) ? 0 : 1;
    }

    if ([json[@"ahead_by"] respondsToSelector:@selector(integerValue)]) {
        aheadBy = MAX(0, [json[@"ahead_by"] integerValue]);
    }
    id headCommit = json[@"commits"];
    if ([headCommit isKindOfClass:[NSArray class]]) {
        summaries = GrokCommitSummariesFromGitHub(headCommit);
        id last = [headCommit lastObject];
        if ([last isKindOfClass:[NSDictionary class]] && [last[@"sha"] isKindOfClass:[NSString class]]) {
            remoteSHA = last[@"sha"];
        }
    }
    NSString *status = [json[@"status"] isKindOfClass:[NSString class]] ? json[@"status"] : nil;
    if ([status isEqualToString:@"identical"] || ([status isEqualToString:@"behind"] && aheadBy == 0)) {
        aheadBy = 0;
        if (remoteSHA.length == 0) {
            remoteSHA = currentSHA;
        }
    }

    if (remoteSHA.length == 0 && aheadBy == 0 && currentSHA.length > 0) {
        remoteSHA = currentSHA;
    }
    if (remoteSHA.length == 0) {
        return @{@"ok": @NO, @"error": @"GitHub response had no commit SHA"};
    }

    BOOL same = GrokGitSHAsEqual(currentSHA, remoteSHA);
    if (same) {
        aheadBy = 0;
    } else if (aheadBy <= 0) {
        aheadBy = MAX(1, (NSInteger)summaries.count);
    }

    return @{
        @"ok": @YES,
        @"updateAvailable": @(aheadBy > 0 && !same),
        @"aheadBy": @(aheadBy),
        @"currentSHA": currentSHA ?: @"",
        @"remoteSHA": remoteSHA,
        @"commits": summaries
    };
}

static NSString *GrokUpdatePromptText(NSDictionary *update) {
    NSInteger ahead = [update[@"aheadBy"] integerValue];
    NSArray *commits = [update[@"commits"] isKindOfClass:[NSArray class]] ? update[@"commits"] : @[];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSUInteger shown = MIN(commits.count, (NSUInteger)8);
    for (NSUInteger i = 0; i < shown; i++) {
        [lines addObject:[NSString stringWithFormat:@"• %@", commits[i]]];
    }
    if (commits.count > shown) {
        [lines addObject:[NSString stringWithFormat:@"• … %lu more", (unsigned long)(commits.count - shown)]];
    }

    NSString *countText = ahead == 1 ? @"1 new commit" : [NSString stringWithFormat:@"%ld new commits", (long)ahead];
    NSString *body = lines.count > 0 ? [lines componentsJoinedByString:@"\n"] : @"New commits, including merged PRs, are on main.";
    return [NSString stringWithFormat:@"%@ on GitHub main.\n\n%@\n\nPull, rebuild, and restart now?", countText, body];
}

static NSString *GrokGitExecutable(void) {
    NSArray<NSString *> *candidates = @[
        @"/usr/bin/git",
        @"/opt/homebrew/bin/git",
        @"/usr/local/bin/git"
    ];
    for (NSString *path in candidates) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return @"/usr/bin/git";
}

static NSString *GrokRunProcess(NSString *launchPath,
                                NSArray<NSString *> *arguments,
                                NSString *directory,
                                NSInteger *status) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:launchPath];
    task.arguments = arguments;
    if (directory.length > 0) {
        task.currentDirectoryURL = [NSURL fileURLWithPath:directory];
    }
    NSPipe *outPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = errPipe;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        if (status) {
            *status = -1;
        }
        return error.localizedDescription ?: @"Could not start process";
    }
    [task waitUntilExit];
    if (status) {
        *status = task.terminationStatus;
    }
    NSData *outData = [outPipe.fileHandleForReading readDataToEndOfFile];
    NSData *errData = [errPipe.fileHandleForReading readDataToEndOfFile];
    NSString *outText = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] ?: @"";
    if (task.terminationStatus == 0) {
        return [outText stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    NSString *errText = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"";
    NSString *combined = errText.length > 0 ? errText : outText;
    return [combined stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *GrokGit(NSString *repo, NSArray<NSString *> *arguments, NSInteger *status) {
    NSMutableArray<NSString *> *args = [@[@"-C", repo] mutableCopy];
    [args addObjectsFromArray:arguments];
    return GrokRunProcess(GrokGitExecutable(), args, nil, status);
}

static BOOL GrokDirectoryHasGit(NSString *path) {
    if (path.length == 0) {
        return NO;
    }
    BOOL isDir = NO;
    NSString *git = [path stringByAppendingPathComponent:@".git"];
    if ([NSFileManager.defaultManager fileExistsAtPath:git isDirectory:&isDir]) {
        return YES;
    }
    return NO;
}

static NSString *GrokOriginURL(NSString *repo) {
    NSInteger status = 0;
    NSString *url = GrokGit(repo, @[@"remote", @"get-url", @"origin"], &status);
    return status == 0 ? url : nil;
}

static NSString *GrokWalkToGitRoot(NSString *start) {
    NSString *path = start.stringByStandardizingPath;
    NSFileManager *fm = NSFileManager.defaultManager;
    while (path.length > 1) {
        if (GrokDirectoryHasGit(path) && GrokRemotePointsAtAppRepo(GrokOriginURL(path))) {
            return path;
        }
        NSString *parent = path.stringByDeletingLastPathComponent;
        if ([parent isEqualToString:path]) {
            break;
        }
        path = parent;
        (void)fm;
    }
    return nil;
}

static NSString *GrokManagedClonePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/Grok CLI Usage Menu Bar/src"];
}

static NSString *GrokBundledGitCommit(void) {
    NSString *sha = NSBundle.mainBundle.infoDictionary[@"GrokGitCommit"];
    return [sha isKindOfClass:[NSString class]] ? GrokTrimGitSHA(sha) : @"";
}

static NSString *GrokBundledGitRemote(void) {
    NSString *remote = NSBundle.mainBundle.infoDictionary[@"GrokGitRemote"];
    if ([remote isKindOfClass:[NSString class]] && remote.length > 0) {
        return remote;
    }
    return GrokDefaultGitRemote;
}

static NSString *GrokFindSourceRepo(void) {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:GrokSourceRepoPathKey];
    if (GrokDirectoryHasGit(saved) && GrokRemotePointsAtAppRepo(GrokOriginURL(saved))) {
        return saved.stringByStandardizingPath;
    }

    NSString *fromBundle = GrokWalkToGitRoot(NSBundle.mainBundle.bundlePath);
    if (fromBundle.length > 0) {
        return fromBundle;
    }

    NSString *home = NSHomeDirectory();
    NSArray<NSString *> *candidates = @[
        [home stringByAppendingPathComponent:@"Documents/code_projects/menu_bar_widgets/grok_menu_bar"],
        [home stringByAppendingPathComponent:@"Documents/grok_menu_bar"],
        [home stringByAppendingPathComponent:@"src/grok_menu_bar"],
        [home stringByAppendingPathComponent:@"Developer/grok_menu_bar"],
        GrokManagedClonePath()
    ];
    for (NSString *path in candidates) {
        if (GrokDirectoryHasGit(path) && GrokRemotePointsAtAppRepo(GrokOriginURL(path))) {
            return path.stringByStandardizingPath;
        }
    }
    return nil;
}

static NSString *GrokEnsureSourceRepo(NSString *remote, NSError **error) {
    NSString *existing = GrokFindSourceRepo();
    if (existing.length > 0) {
        [NSUserDefaults.standardUserDefaults setObject:existing forKey:GrokSourceRepoPathKey];
        return existing;
    }

    NSString *dest = GrokManagedClonePath();
    NSString *parent = dest.stringByDeletingLastPathComponent;
    NSError *dirError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:parent
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&dirError]) {
        if (error) {
            *error = dirError;
        }
        return nil;
    }
    if (GrokDirectoryHasGit(dest) && GrokRemotePointsAtAppRepo(GrokOriginURL(dest))) {
        [NSUserDefaults.standardUserDefaults setObject:dest forKey:GrokSourceRepoPathKey];
        return dest;
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:dest]) {
        [NSFileManager.defaultManager removeItemAtPath:dest error:nil];
    }

    NSInteger status = 0;
    NSString *output = GrokRunProcess(GrokGitExecutable(),
                                      @[@"clone", @"--branch", @"main", remote ?: GrokDefaultGitRemote, dest],
                                      nil,
                                      &status);
    if (status != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"GrokUpdater" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: output.length > 0 ? output : @"git clone failed"}];
        }
        return nil;
    }
    [NSUserDefaults.standardUserDefaults setObject:dest forKey:GrokSourceRepoPathKey];
    return dest;
}

static NSDictionary *GrokCheckGitHubForUpdates(NSString *currentSHA, NSString *remote) {
    NSDictionary *repo = GrokGitHubRepoFromRemote(remote);
    NSString *owner = repo[@"owner"];
    NSString *name = repo[@"name"];
    NSString *sha = GrokTrimGitSHA(currentSHA);
    NSString *url = nil;
    if (sha.length >= 7) {
        url = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/compare/%@...main",
               owner, name, sha];
    } else {
        url = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/commits/main", owner, name];
    }

    NSInteger status = 0;
    NSError *error = nil;
    NSData *data = GrokHTTPRequest(@"GET",
                                   url,
                                   @{
                                       @"Accept": @"application/vnd.github+json",
                                       @"User-Agent": @"GrokCLIUsageMenuBar/0.1"
                                   },
                                   nil,
                                   &status,
                                   &error);
    if (status == 404 && sha.length >= 7) {
        data = GrokHTTPRequest(@"GET",
                               [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/commits/main", owner, name],
                               @{
                                   @"Accept": @"application/vnd.github+json",
                                   @"User-Agent": @"GrokCLIUsageMenuBar/0.1"
                               },
                               nil,
                               &status,
                               &error);
    }
    if (data == nil || status < 200 || status >= 300) {
        NSString *message = error.localizedDescription ?: [NSString stringWithFormat:@"GitHub HTTP %ld", (long)status];
        return @{@"ok": @NO, @"error": message};
    }
    NSDictionary *json = GrokJSONFromData(data);
    return GrokParseGitHubUpdatePayload(json, sha);
}

static NSDictionary *GrokCheckGitFetchForUpdates(NSString *repo, NSString *currentSHA) {
    NSInteger status = 0;
    NSString *fetchOut = GrokGit(repo, @[@"fetch", @"origin", @"main"], &status);
    if (status != 0) {
        return @{@"ok": @NO, @"error": fetchOut.length > 0 ? fetchOut : @"git fetch failed"};
    }
    NSString *remoteSHA = GrokGit(repo, @[@"rev-parse", @"origin/main"], &status);
    if (status != 0 || remoteSHA.length == 0) {
        return @{@"ok": @NO, @"error": @"Could not read origin/main"};
    }
    NSString *log = GrokGit(repo, @[@"log", @"--format=%s", [NSString stringWithFormat:@"%@..origin/main", currentSHA.length >= 7 ? currentSHA : @"HEAD"]], &status);
    NSMutableArray<NSString *> *commits = [NSMutableArray array];
    if (status == 0 && log.length > 0) {
        for (NSString *line in [log componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            if (line.length > 0) {
                [commits addObject:line];
            }
        }
    }
    BOOL same = GrokGitSHAsEqual(currentSHA, remoteSHA);
    NSInteger ahead = same ? 0 : MAX(1, (NSInteger)commits.count);
    return @{
        @"ok": @YES,
        @"updateAvailable": @(!same),
        @"aheadBy": @(ahead),
        @"currentSHA": currentSHA ?: @"",
        @"remoteSHA": remoteSHA,
        @"commits": commits,
        @"repoPath": repo
    };
}

static NSString *GrokCurrentCommitSHA(NSString *repo) {
    NSString *bundled = GrokBundledGitCommit();
    if (bundled.length >= 7) {
        return bundled;
    }
    if (repo.length > 0) {
        NSInteger status = 0;
        NSString *head = GrokGit(repo, @[@"rev-parse", @"HEAD"], &status);
        if (status == 0 && head.length > 0) {
            return GrokTrimGitSHA(head);
        }
    }
    return bundled;
}

static NSDictionary *GrokCheckForUpdates(void) {
    NSString *remote = GrokBundledGitRemote();
    NSString *repo = GrokFindSourceRepo();
    NSString *current = GrokCurrentCommitSHA(repo);
    NSDictionary *github = GrokCheckGitHubForUpdates(current, remote);
    if ([github[@"ok"] boolValue]) {
        NSMutableDictionary *result = [github mutableCopy];
        if (repo.length > 0) {
            result[@"repoPath"] = repo;
        }
        return result;
    }
    if (repo.length > 0) {
        return GrokCheckGitFetchForUpdates(repo, current);
    }
    return github;
}

static NSDictionary *GrokApplyGitPullAndRebuild(NSString *installAppPath, NSError **error) {
    NSString *remote = GrokBundledGitRemote();
    NSString *repo = GrokEnsureSourceRepo(remote, error);
    if (repo.length == 0) {
        return @{@"ok": @NO, @"error": error && *error ? (*error).localizedDescription : @"Could not find the git checkout"};
    }

    NSInteger status = 0;
    NSString *fetchOut = GrokGit(repo, @[@"fetch", @"origin", @"main"], &status);
    if (status != 0) {
        return @{@"ok": @NO, @"error": fetchOut.length > 0 ? fetchOut : @"git fetch failed"};
    }
    NSString *pullOut = GrokGit(repo, @[@"pull", @"--ff-only", @"origin", @"main"], &status);
    if (status != 0) {
        return @{@"ok": @NO, @"error": pullOut.length > 0 ? pullOut : @"git pull --ff-only failed"};
    }

    NSString *buildOutDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"grok-cli-usage-update-%@", NSUUID.UUID.UUIDString]];
    NSString *script = [repo stringByAppendingPathComponent:@"scripts/build.sh"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:script]) {
        return @{@"ok": @NO, @"error": @"scripts/build.sh is missing after git pull"};
    }

    NSTask *build = [[NSTask alloc] init];
    build.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    build.arguments = @[script];
    build.currentDirectoryURL = [NSURL fileURLWithPath:repo];
    NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
    env[@"OUT_DIR"] = buildOutDir;
    build.environment = env;
    NSPipe *pipe = [NSPipe pipe];
    build.standardOutput = pipe;
    build.standardError = pipe;
    NSError *launchError = nil;
    if (![build launchAndReturnError:&launchError]) {
        return @{@"ok": @NO, @"error": launchError.localizedDescription ?: @"Could not start build"};
    }
    [build waitUntilExit];
    NSString *buildLog = [[NSString alloc] initWithData:[pipe.fileHandleForReading readDataToEndOfFile]
                                               encoding:NSUTF8StringEncoding] ?: @"";
    if (build.terminationStatus != 0) {
        NSString *tail = buildLog;
        if (tail.length > 800) {
            tail = [tail substringFromIndex:tail.length - 800];
        }
        return @{@"ok": @NO, @"error": [NSString stringWithFormat:@"Build failed:\n%@", tail]};
    }

    NSString *builtApp = [buildOutDir stringByAppendingPathComponent:@"Grok CLI Usage Menu Bar.app"];
    if (![NSFileManager.defaultManager fileExistsAtPath:builtApp]) {
        return @{@"ok": @NO, @"error": @"Build finished but the .app is missing"};
    }

    NSString *destination = installAppPath.length > 0 ? installAppPath :
        [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Grok CLI Usage Menu Bar.app"];
    NSString *parent = destination.stringByDeletingLastPathComponent;
    [NSFileManager.defaultManager createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil];

    status = 0;
    NSString *dittoOut = GrokRunProcess(@"/usr/bin/ditto", @[@"--noqtn", builtApp, destination], nil, &status);
    if (status != 0) {
        return @{@"ok": @NO, @"error": dittoOut.length > 0 ? dittoOut : @"Could not replace the app"};
    }
    GrokRunProcess(@"/usr/bin/xattr", @[@"-cr", destination], nil, &status);
    GrokRunProcess(@"/usr/bin/codesign", @[@"--force", @"--sign", @"-", @"--options", @"runtime", destination], nil, &status);

    [NSFileManager.defaultManager removeItemAtPath:buildOutDir error:nil];
    return @{@"ok": @YES, @"appPath": destination, @"repoPath": repo};
}

#endif
