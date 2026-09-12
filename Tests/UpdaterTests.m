#import "GrokUpdater.h"

int main(void) {
    @autoreleasepool {
        NSCAssert(GrokGitSHAsEqual(@"217185e", @"217185ef00aabb"), @"Short SHA matches long SHA");
        NSCAssert(!GrokGitSHAsEqual(@"217185e", @"deadbeef"), @"Different SHAs");
        NSCAssert([GrokShortGitSHA(@"217185ef00") isEqual:@"217185e"], @"Short SHA");

        NSDictionary *repo = GrokGitHubRepoFromRemote(@"https://github.com/diegocp01/grok_menu_bar.git");
        NSCAssert([repo[@"owner"] isEqual:@"diegocp01"], @"HTTPS owner");
        NSCAssert([repo[@"name"] isEqual:@"grok_menu_bar"], @"HTTPS name");
        repo = GrokGitHubRepoFromRemote(@"git@github.com:diegocp01/grok_menu_bar.git");
        NSCAssert([repo[@"owner"] isEqual:@"diegocp01"] && [repo[@"name"] isEqual:@"grok_menu_bar"], @"SSH remote");
        NSCAssert(GrokRemotePointsAtAppRepo(@"https://github.com/diegocp01/grok_menu_bar.git"), @"Repo match");
        NSCAssert(!GrokRemotePointsAtAppRepo(@"https://github.com/diegocp01/top_bar_codex_credits.git"), @"Other repo");

        NSDictionary *identical = GrokParseGitHubUpdatePayload(@{
            @"status": @"identical",
            @"ahead_by": @0,
            @"commits": @[]
        }, @"217185eadd");
        NSCAssert([identical[@"ok"] boolValue], @"Identical compare is ok");
        NSCAssert(![identical[@"updateAvailable"] boolValue], @"Identical is not an update");

        NSDictionary *ahead = GrokParseGitHubUpdatePayload(@{
            @"status": @"ahead",
            @"ahead_by": @2,
            @"commits": @[
                @{@"sha": @"aaa1111", @"commit": @{@"message": @"Fix billing parse\n\nDetails"}},
                @{@"sha": @"bbb2222deadbeef", @"commit": @{@"message": @"Merge pull request #4 from diegocp01/updater"}}
            ]
        }, @"217185eadd");
        NSCAssert([ahead[@"updateAvailable"] boolValue], @"Ahead compare is an update");
        NSCAssert([ahead[@"aheadBy"] integerValue] == 2, @"ahead_by");
        NSCAssert([ahead[@"remoteSHA"] hasPrefix:@"bbb2222"], @"Tip SHA");
        NSCAssert([ahead[@"commits"] count] == 2, @"Commit summaries");
        NSCAssert([ahead[@"commits"][1] containsString:@"Merge pull request #4"], @"Merged PR subject");

        NSString *prompt = GrokUpdatePromptText(ahead);
        NSCAssert([prompt containsString:@"Update"] || [prompt containsString:@"2 new commits"], @"Prompt count");
        NSCAssert([prompt containsString:@"Merge pull request #4"], @"Prompt includes merged PR");

        NSDictionary *tip = GrokParseGitHubUpdatePayload(@{
            @"sha": @"217185eaddffff",
            @"commit": @{@"message": @"Add Grok CLI usage menu bar app."}
        }, @"217185eaddffff");
        NSCAssert(![tip[@"updateAvailable"] boolValue], @"Same tip commit is not an update");

        NSDictionary *newTip = GrokParseGitHubUpdatePayload(@{
            @"sha": @"ffffffffffffffff",
            @"commit": @{@"message": @"Later commit"}
        }, @"217185e");
        NSCAssert([newTip[@"updateAvailable"] boolValue], @"Different tip is an update");

        NSCAssert(GrokFirstLine(@"Foo\nBar") , @"First line");
        NSCAssert([GrokFirstLine(@"Foo\nBar") isEqual:@"Foo"], @"First line value");
        puts("Updater tests passed");
    }
    return 0;
}
