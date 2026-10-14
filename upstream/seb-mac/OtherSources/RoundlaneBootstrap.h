// Roundlane additions, licensed under the Mozilla Public License 2.0.
#import <Cocoa/Cocoa.h>

@interface RoundlaneBootstrap : NSObject
+ (BOOL)prepare;
+ (BOOL)preparationFailed;
+ (NSDictionary *)organizer;
+ (int)selfTest;
+ (int)checkSettings:(NSString *)path;
+ (int)checkBrowser;
+ (int)codeStoreCheck;
+ (int)codeStoreFixture;
+ (int)codeStoreFixtureDelete;
+ (NSString *)currentContestURL;
+ (NSString *)profilePath;
+ (NSString *)organizerQuitHash;
+ (void)configureExamMenu;
+ (void)cleanup;
@end
