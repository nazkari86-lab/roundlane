// Roundlane additions, MPL-2.0.
#import <Foundation/Foundation.h>

@interface RoundlaneMacGuard : NSObject
+ (BOOL)verify:(NSString **)reason;
+ (int)diagnostic;
@end
