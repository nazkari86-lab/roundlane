// Roundlane additions, MPL-2.0.
#import <Cocoa/Cocoa.h>
@class SEBOSXBrowserController, SEBBrowserWindow;
@interface RoundlaneTabs : NSObject
+ (instancetype)shared;
+ (NSString *)editorBridge;
+ (int)diagnostic;
+ (int)preview;
- (void)attach:(SEBBrowserWindow *)window controller:(SEBOSXBrowserController *)controller;
- (void)refresh;
- (void)restore;
- (void)finish;
- (void)removed:(NSWindow *)window;
- (void)pageLoaded:(id)view;
@end
