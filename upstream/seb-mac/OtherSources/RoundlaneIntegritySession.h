// Roundlane additions, MPL-2.0.
#import <Foundation/Foundation.h>

@interface RoundlaneIntegritySession : NSObject
@property (readonly) BOOL quarantined;
@property (readonly) BOOL exitAuthorized;
@property (readonly, copy) NSString *failureReason;
- (instancetype)initWithProbe:(NSString *(^)(void))probe organizerHash:(NSString *)hash failureHandler:(void (^)(NSString *))handler;
- (BOOL)startWithInterval:(NSTimeInterval)interval timeout:(NSTimeInterval)timeout;
- (void)stop;
- (BOOL)authorizeExitWithCode:(NSString *)code;
@end

// Safe diagnostic: no SEBController, kiosk, keychain or system settings.
int RoundlaneIntegritySessionDiagnostic(void);
int RoundlaneIntegrityMonitorDiagnostic(NSString *reportPath);
