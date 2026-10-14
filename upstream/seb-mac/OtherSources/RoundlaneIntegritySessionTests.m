// Safe self-authored diagnostics. No SEBController initialization, kiosk or keychain.
#import "RoundlaneIntegritySession.h"
#import "RoundlaneMacGuard.h"
#import "SEBLockedViewController.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *testHash(void) {
    NSData *data = [@"1234" dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *text = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [text appendFormat:@"%02x", digest[i]];
    return text;
}
static BOOL waitFor(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    return condition();
}

@interface RoundlaneProbeLockUI : NSObject <SEBLockedViewUIDelegate>
@property (copy) NSString *password;
@property BOOL wrongHidden;
@property (strong) NSAttributedString *resignActiveLogString;
@end
@implementation RoundlaneProbeLockUI
- (void)scrollToBottom {}
- (NSString *)lockedAlertPassword { return self.password; }
- (void)setLockedAlertPassword:(NSString *)password { self.password = password; }
- (void)setPasswordWrongLabelHidden:(BOOL)hidden { self.wrongHidden = hidden; }
- (void)setResignActiveLogString:(NSAttributedString *)text logStringToAppend:(NSAttributedString *)extra {}
@end

@interface RoundlaneProbeLockDelegate : NSObject <SEBLockedViewControllerDelegate>
@property (strong) RoundlaneIntegritySession *session;
@property NSUInteger exits, closes;
@property (strong) NSDate *didLockSEBTime, *didBecomeActiveTime, *didResumeExamTime;
@end
@implementation RoundlaneProbeLockDelegate
- (NSData *)configKey { return nil; }
- (NSURL *)startURL { return nil; }
- (void)retryButtonPressed {}
- (BOOL)terminalIntegrityQuarantine { return self.session.quarantined; }
- (BOOL)validateIntegrityQuitPassword:(NSString *)password { return [self.session authorizeExitWithCode:password]; }
- (void)correctPasswordEntered { if (self.session.exitAuthorized) self.exits++; }
- (void)closeLockdownWindowsAllowOverride:(BOOL)allow { self.closes++; }
@end

@interface RoundlaneProbePasswordController : SEBLockedViewController
@end
@implementation RoundlaneProbePasswordController
// Avoid persistent exam logs/keychain; passwordEntered and close logic are real.
- (void)appendErrorString:(NSString *)message withTime:(NSDate *)time {}
@end

static NSDictionary *passwordPath(RoundlaneIntegritySession *session) {
    RoundlaneProbeLockUI *ui = [RoundlaneProbeLockUI new];
    RoundlaneProbeLockDelegate *delegate = [RoundlaneProbeLockDelegate new]; delegate.session = session;
    RoundlaneProbePasswordController *lock = [RoundlaneProbePasswordController new];
    lock.UIDelegate = ui; lock.controllerDelegate = delegate;
    ui.password = @"9999"; [lock passwordEntered];
    BOOL wrongRejected = !session.exitAuthorized && delegate.exits == 0 && !ui.wrongHidden;
    [lock closeLockdownWindows];
    BOOL forcedCloseRejected = delegate.closes == 0;
    ui.password = @"1234"; [lock passwordEntered];
    [lock closeLockdownWindows];
    BOOL authorized = session.exitAuthorized && session.quarantined && delegate.exits == 1 && delegate.closes == 0 && ui.wrongHidden;
    return @{@"wrong_code_rejected":@(wrongRejected), @"forced_close_rejected":@(forcedCloseRejected), @"authorized_exit_only":@(authorized), @"real_password_controller":@YES, @"fake_exit_delegate":@YES};
}

int RoundlaneIntegritySessionDiagnostic(void) {
    NSMutableArray *cases = [NSMutableArray new];
    __block NSUInteger calls = 0, notifications = 0;
    __block BOOL callbackMain = NO;
    RoundlaneIntegritySession *session = [[RoundlaneIntegritySession alloc] initWithProbe:^NSString *{
        calls++; return calls > 1 ? @"Controlled integrity failure" : nil;
    } organizerHash:testHash() failureHandler:^(NSString *reason) { notifications++; callbackMain = NSThread.isMainThread; }];
    BOOL started = [session startWithInterval:0.02 timeout:0.1];
    BOOL healthyCannotAuthorize = ![session authorizeExitWithCode:@"1234"];
    BOOL delivered = waitFor(^BOOL { return notifications == 1; }, 1);
    NSDictionary *password = passwordPath(session);
    BOOL sticky = session.quarantined && ![session startWithInterval:0.02 timeout:0.1];
    [session stop];
    [cases addObject:@{@"name":@"periodic-failure-password-and-sticky-lock", @"passed":@(started && healthyCannotAuthorize && delivered && callbackMain && sticky && [password[@"wrong_code_rejected"] boolValue] && [password[@"forced_close_rejected"] boolValue] && [password[@"authorized_exit_only"] boolValue]), @"password_path":password, @"callback_on_main":@(callbackMain), @"notifications":@(notifications)}];

    __block NSUInteger timeoutCalls = 0, timeoutEvents = 0;
    RoundlaneIntegritySession *slow = [[RoundlaneIntegritySession alloc] initWithProbe:^NSString *{
        timeoutCalls++; if (timeoutCalls > 1) [NSThread sleepForTimeInterval:0.2]; return nil;
    } organizerHash:testHash() failureHandler:^(NSString *reason) { timeoutEvents++; }];
    BOOL slowStarted = [slow startWithInterval:0.02 timeout:0.04];
    BOOL timedOut = waitFor(^BOOL { return timeoutEvents == 1; }, 1);
    waitFor(^BOOL { return NO; }, 0.23);
    [cases addObject:@{@"name":@"watchdog-late-success-cannot-resume", @"passed":@(slowStarted && timedOut && slow.quarantined && timeoutEvents == 1 && [slow.failureReason containsString:@"timed out"])}];
    [slow stop];

    __block NSUInteger cancelledCalls = 0, cancelledEvents = 0;
    RoundlaneIntegritySession *cancelled = [[RoundlaneIntegritySession alloc] initWithProbe:^NSString *{
        cancelledCalls++; return cancelledCalls > 1 ? @"Must not be delivered" : nil;
    } organizerHash:testHash() failureHandler:^(NSString *reason) { cancelledEvents++; }];
    BOOL cancelStarted = [cancelled startWithInterval:0.1 timeout:0.1]; [cancelled stop];
    waitFor(^BOOL { return NO; }, 0.15);
    [cases addObject:@{@"name":@"stop-cancels-future-checks", @"passed":@(cancelStarted && cancelledEvents == 0 && cancelledCalls == 1 && !cancelled.quarantined)}];

    RoundlaneIntegritySession *missing = [[RoundlaneIntegritySession alloc] initWithProbe:^NSString *{ return nil; } organizerHash:nil failureHandler:nil];
    BOOL invalidRejected = ![missing startWithInterval:1 timeout:1] && missing.quarantined && ![missing authorizeExitWithCode:@""] && ![missing authorizeExitWithCode:@"1234"];
    [cases addObject:@{@"name":@"missing-code-cannot-authorize", @"passed":@(invalidRejected)}]; [missing stop];
    RoundlaneIntegritySession *exception = [[RoundlaneIntegritySession alloc] initWithProbe:^NSString *{ [NSException raise:@"ControlledTest" format:@"test only"]; return nil; } organizerHash:testHash() failureHandler:nil];
    [cases addObject:@{@"name":@"verifier-exception-fails-closed", @"passed":@(![exception startWithInterval:1 timeout:1] && exception.quarantined)}]; [exception stop];
    BOOL passed = YES; for (NSDictionary *entry in cases) passed &= [entry[@"passed"] boolValue];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"passed":@(passed), @"exam_started":@NO, @"kiosk_started":@NO, @"keychain_used":@NO, @"cases":cases} options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
    return passed ? 0 : 1;
}

int RoundlaneIntegrityMonitorDiagnostic(NSString *reportPath) {
    if (!reportPath.length) return 2;
    __block NSUInteger healthy = 0, failures = 0;
    __block NSString *violation;
    RoundlaneIntegritySession *session = [[RoundlaneIntegritySession alloc] initWithProbe:^NSString *{
        NSString *reason = nil; BOOL valid = [RoundlaneMacGuard verify:&reason];
        if (valid) healthy++; return valid ? nil : reason ?: @"Integrity verification failed";
    } organizerHash:testHash() failureHandler:^(NSString *reason) { failures++; violation = reason; }];
    BOOL started = [session startWithInterval:5 timeout:3];
    if (started) [@"monitor-ready" writeToFile:[reportPath stringByAppendingString:@".ready"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    BOOL detected = waitFor(^BOOL { return failures == 1; }, 10);
    NSDictionary *password = detected ? passwordPath(session) : @{};
    BOOL passed = started && healthy > 0 && detected && session.quarantined && [password[@"wrong_code_rejected"] boolValue] && [password[@"forced_close_rejected"] boolValue] && [password[@"authorized_exit_only"] boolValue];
    [session stop];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"passed":@(passed), @"exam_started":@NO, @"kiosk_started":@NO, @"healthy_checks":@(healthy), @"failure_notifications":@(failures), @"reason":violation ?: NSNull.null, @"password_path":password} options:NSJSONWritingPrettyPrinted error:nil];
    [json writeToFile:reportPath atomically:YES];
    fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
    return passed ? 0 : 1;
}
