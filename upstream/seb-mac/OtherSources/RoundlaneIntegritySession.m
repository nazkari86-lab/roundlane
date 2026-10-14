// Roundlane additions, MPL-2.0. Sticky quarantine; authorization never resumes an exam.
#import "RoundlaneIntegritySession.h"
#import <CommonCrypto/CommonDigest.h>
#include <math.h>

@interface RoundlaneIntegritySession ()
@property (copy) NSString *(^probe)(void);
@property (copy) void (^failureHandler)(NSString *);
@property (strong) NSData *organizerDigest;
@property (strong) dispatch_source_t timer;
@property (strong) dispatch_queue_t queue;
@property BOOL active;
@property NSUInteger generation;
@property NSUInteger probeToken;
@property NSUInteger inFlight;
@property BOOL failed;
@property BOOL authorized;
@property (copy) NSString *reason;
@end

static int hexDigit(unichar c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

@implementation RoundlaneIntegritySession
- (instancetype)initWithProbe:(NSString *(^)(void))probe organizerHash:(NSString *)hash failureHandler:(void (^)(NSString *))handler {
    self = [super init];
    if (self) {
        _probe = [probe copy]; _failureHandler = [handler copy];
        _queue = dispatch_queue_create("local.roundlane.integrity", DISPATCH_QUEUE_SERIAL);
        if ([hash isKindOfClass:NSString.class] && hash.length == CC_SHA256_DIGEST_LENGTH * 2) {
            unsigned char digest[CC_SHA256_DIGEST_LENGTH];
            BOOL valid = YES;
            for (NSUInteger i = 0; i < sizeof(digest); i++) {
                int a = hexDigit([hash characterAtIndex:i * 2]), b = hexDigit([hash characterAtIndex:i * 2 + 1]);
                if (a < 0 || b < 0) { valid = NO; break; }
                digest[i] = (unsigned char)(a * 16 + b);
            }
            if (valid) _organizerDigest = [NSData dataWithBytes:digest length:sizeof(digest)];
        }
    }
    return self;
}
- (BOOL)quarantined { @synchronized(self) { return _failed; } }
- (BOOL)exitAuthorized { @synchronized(self) { return _authorized; } }
- (NSString *)failureReason { @synchronized(self) { return [_reason copy]; } }

- (void)fail:(NSString *)reason generation:(NSUInteger)generation {
    void (^handler)(NSString *);
    NSString *message;
    @synchronized(self) {
        if (!_active || _generation != generation || _failed) return;
        _failed = YES; _inFlight = 0;
        _reason = [reason copy] ?: @"Integrity verification failed";
        message = _reason; handler = _failureHandler;
        if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
    }
    // Publication of failure precedes any UI callback; late success cannot clear it.
    __weak RoundlaneIntegritySession *weakSelf = self;
    void (^notify)(void) = ^{
        RoundlaneIntegritySession *session = weakSelf;
        if (!session) return;
        @synchronized(session) {
            if (!session.active || session.generation != generation || !session.failed) return;
        }
        if (handler) handler(message);
    };
    if (NSThread.isMainThread) notify(); else dispatch_async(dispatch_get_main_queue(), notify);
}

- (void)checkWithTimeout:(NSTimeInterval)timeout generation:(NSUInteger)generation {
    NSUInteger token;
    NSString *(^probe)(void);
    @synchronized(self) {
        if (!_active || _generation != generation || _failed || _inFlight) return;
        token = ++_probeToken; _inFlight = token; probe = _probe;
    }
    // Separate queue: a blocked verifier must not also block its watchdog.
    __weak RoundlaneIntegritySession *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RoundlaneIntegritySession *session = weakSelf;
        if (!session) return;
        @synchronized(session) {
            if (!session.active || session.generation != generation || session.inFlight != token || session.failed) return;
            [session fail:@"Integrity verification timed out" generation:generation];
        }
    });
    NSString *reason = nil;
    NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
    @try { reason = probe ? probe() : @"Integrity verifier is missing"; }
    @catch (NSException *error) { reason = @"Integrity verifier raised an exception"; }
    if (NSProcessInfo.processInfo.systemUptime - started >= timeout) reason = @"Integrity verification timed out";
    @synchronized(self) {
        if (!_active || _generation != generation || _failed || _inFlight != token) return;
        if (reason) { [self fail:reason generation:generation]; return; }
        _inFlight = 0;
    }
}

- (BOOL)startWithInterval:(NSTimeInterval)interval timeout:(NSTimeInterval)timeout {
    NSUInteger generation;
    @synchronized(self) {
        if (_failed) return NO;
        if (_active) return YES;
        _active = YES; generation = ++_generation;
    }
    if (!_organizerDigest || !isfinite(interval) || !isfinite(timeout) || interval <= 0 || timeout <= 0 || interval > 60 || timeout > 60) {
        [self fail:@"Invalid integrity session/code configuration" generation:generation]; return NO;
    }
    // Startup verification finishes before the caller opens an exam window.
    [self checkWithTimeout:timeout generation:generation];
    @synchronized(self) {
        if (_failed || !_active || _generation != generation) return NO;
        __weak RoundlaneIntegritySession *weakSelf = self;
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
        dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), (uint64_t)(interval * NSEC_PER_SEC), (uint64_t)(MIN(interval / 10, 0.25) * NSEC_PER_SEC));
        dispatch_source_set_event_handler(_timer, ^{ [weakSelf checkWithTimeout:timeout generation:generation]; });
        dispatch_resume(_timer);
        return YES;
    }
}
- (BOOL)authorizeExitWithCode:(NSString *)code {
    @synchronized(self) {
        if (!_failed || !_organizerDigest || ![code isKindOfClass:NSString.class] || !code.length || code.length > 256) return NO;
        NSData *input = [code dataUsingEncoding:NSUTF8StringEncoding];
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(input.bytes, (CC_LONG)input.length, digest);
        const unsigned char *expected = _organizerDigest.bytes;
        unsigned char difference = 0;
        for (NSUInteger i = 0; i < sizeof(digest); i++) difference |= digest[i] ^ expected[i];
        if (difference) return NO;
        _authorized = YES;
        return YES;
    }
}
- (void)stop {
    @synchronized(self) {
        _active = NO; _generation++; _inFlight = 0;
        if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
        // Deliberately retain failed/authorized state until process exit.
    }
}
- (void)dealloc { if (_timer) dispatch_source_cancel(_timer); }
@end
