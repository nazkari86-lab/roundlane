// Roundlane additions, MPL-2.0. Existing WebViews stay alive on tab switches.
#import "RoundlaneTabs.h"
#import "RoundlaneBootstrap.h"
#import "SEBOSXBrowserController.h"
#import <CommonCrypto/CommonDigest.h>

@interface SEBOSXBrowserController (RoundlaneTabSelection)
- (void)openWindowSelected:(SEBBrowserOpenWindowWebView *)item;
@end

static const NSUInteger MaxTabs = 24;
static NSString *EditorBridge(void) {
    static NSString *script; static dispatch_once_t once;
    dispatch_once(&once, ^{ script=[NSString stringWithContentsOfURL:[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"Roundlane/hub/editor-drafts.js"] encoding:NSUTF8StringEncoding error:nil]; });
    return script;
}

@interface RLTabStrip : NSView
@property NSScrollView *scroll;
@property NSView *row;
@property NSButton *plus;
@end
@implementation RLTabStrip
- (void)layout {
    [super layout];
    self.scroll.frame=NSMakeRect(6,2,MAX(20,self.bounds.size.width-46),34);
    self.plus.frame=NSMakeRect(MAX(0,self.bounds.size.width-38),4,32,30);
}
@end

@interface RoundlaneTabs ()
@property (weak) SEBOSXBrowserController *controller;
@property NSMapTable<NSWindow *, RLTabStrip *> *strips;
@property NSMutableDictionary<NSValue *,NSMutableDictionary *> *drafts;
@property NSMutableDictionary<NSValue *,NSMutableSet *> *pendingRestores;
@property NSMutableDictionary<NSValue *,NSString *> *restoreURLs;
@property NSMutableDictionary<NSValue *,NSNumber *> *captureVersions;
@property NSMutableSet<NSValue *> *closing;
@property NSMutableArray<NSDictionary *> *closed;
@property NSTimer *timer;
@property id keys;
@property BOOL restored;
@property BOOL stopping;
@property NSString *contest;
@property NSString *statePath;
@end

static NSString *SanitizedURL(NSString *value, NSString *contest) {
    if (![value isKindOfClass:NSString.class] || value.length>1048576) return nil;
    NSURLComponents *url=[NSURLComponents componentsWithString:value];
    NSURLComponents *base=[NSURLComponents componentsWithString:contest];
    if (![url.scheme isEqual:@"https"] || url.user || url.password || url.port) return nil;
    if ([url.host isEqual:@"cpp.sh"] && (!url.path.length || [url.path isEqual:@"/"])) {
        url.fragment=nil; NSMutableArray *query=[NSMutableArray new];
        for (NSURLQueryItem *q in url.queryItems) if ([q.name isEqual:@"source"] && q.value.length<=262144) [query addObject:q];
        url.queryItems=query.count?query:nil; return url.string;
    }
    NSString *path=[base.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    path=[@"/" stringByAppendingString:path];
    if (![url.host isEqual:base.host] || !([url.path isEqual:path] || [url.path hasPrefix:[path stringByAppendingString:@"/"]])) return nil;
    NSMutableArray *query=[NSMutableArray new];
    for (NSURLQueryItem *q in url.queryItems) if ([q.name isEqual:@"locale"] || [q.name isEqual:@"mobile"]) [query addObject:q];
    url.queryItems=query.count?query:nil; url.fragment=nil; return url.string;
}

// Isolated, ordinary windows exercise the same tabs without kiosk or network.
@interface RLPreviewWebView : SEBAbstractWebView
@property NSURL *fixtureURL;
@property WKWebView *fixtureView;
@end
@implementation RLPreviewWebView
- (NSURL *)url {return self.fixtureURL;}
- (id)nativeWebView {return self.fixtureView;}
@end
@interface RLPreviewController : SEBOSXBrowserController
@property NSMutableArray *retainedWindows;
@property NSURL *previewStartURL;
@end
@implementation RLPreviewController
- (NSURL *)startURL { return self.previewStartURL; }
- (SEBAbstractWebView *)openAndShowWebViewWithURL:(NSURL *)url configuration:(WKWebViewConfiguration *)config {
    if(!self.retainedWindows)self.retainedWindows=[NSMutableArray new];
    BOOL main=!self.openBrowserWindowsWebViews.count;
    SEBBrowserWindow *w=[[SEBBrowserWindow alloc]initWithContentRect:NSMakeRect(0,0,1000,650) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];w.title=@"Roundlane — вкладки, без блокировки";w.releasedWhenClosed=NO;
    RLPreviewWebView *v=[RLPreviewWebView new];v.fixtureURL=url;v.isMainBrowserWebView=main;WKWebView *native=[[WKWebView alloc]initWithFrame:NSMakeRect(0,0,1000,612)];native.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;v.fixtureView=native;w.webView=v;[w.contentView addSubview:native];
    NSURLComponents *c=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];NSString *code=@"#include <iostream>\nusing namespace std;\n\nint main() {\n    return 0;\n}\n";
    for(NSURLQueryItem *q in c.queryItems)if([q.name isEqual:@"source"])code=q.value;
    NSData *json=[NSJSONSerialization dataWithJSONObject:@[code] options:0 error:nil];NSString *encoded=[[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding] stringByReplacingOccurrencesOfString:@"<" withString:@"\\u003c"];
    NSString *html=[NSString stringWithFormat:@"<html><meta charset='utf-8'><style>body{font:16px system-ui;margin:24px}textarea{font:15px monospace;width:95%%;height:440px}</style><h3>%@</h3><textarea aria-label='Код C++'></textarea><div class='CodeMirror'></div><script>const e=document.querySelector('textarea');e.value=%@[0];document.querySelector('.CodeMirror').CodeMirror={getValue:()=>e.value,setValue:v=>{e.value=v}};</script></html>",[url.host isEqual:@"cpp.sh"]?@"C++":@"Страница соревнования",encoded];
    [native loadHTMLString:html baseURL:nil];
    SEBBrowserOpenWindowWebView *item=[[SEBBrowserOpenWindowWebView alloc]initWithTitle:main?@"Roundlane":([url.host isEqual:@"cpp.sh"]?@"C++":url.lastPathComponent) action:nil keyEquivalent:@""];item.browserWindow=w;item.webView=v;[self.openBrowserWindowsWebViews addObject:item];[self.retainedWindows addObject:w];if(main){self.mainBrowserWindow=w;self.mainWebView=v;}
    [[RoundlaneTabs shared] attach:w controller:self];if(self.mainBrowserWindow && !main)[w setFrame:self.mainBrowserWindow.frame display:NO];else[w center];[self openWindowSelected:item];return v;
}
- (void)openWindowSelected:(SEBBrowserOpenWindowWebView *)item {self.activeBrowserWindow=item.browserWindow;[item.browserWindow makeKeyAndOrderFront:nil];[[RoundlaneTabs shared] refresh];}
- (void)closeWebView:(SEBAbstractWebView *)view {for(SEBBrowserOpenWindowWebView *item in self.openBrowserWindowsWebViews.copy)if(item.webView==view){NSWindow *w=item.browserWindow;[self.openBrowserWindowsWebViews removeObject:item];[w orderOut:nil];[[RoundlaneTabs shared] removed:w];[self.retainedWindows removeObject:w];if(self.openBrowserWindowsWebViews.count)[self openWindowSelected:self.openBrowserWindowsWebViews.lastObject];}}
@end

@implementation RoundlaneTabs
+ (instancetype)shared { static RoundlaneTabs *tabs; static dispatch_once_t once; dispatch_once(&once,^{tabs=[self new];}); return tabs; }
- (instancetype)init { if ((self=[super init])) {self.strips=[NSMapTable weakToStrongObjectsMapTable];self.drafts=[NSMutableDictionary new];self.pendingRestores=[NSMutableDictionary new];self.restoreURLs=[NSMutableDictionary new];self.captureVersions=[NSMutableDictionary new];self.closing=[NSMutableSet new];self.closed=[NSMutableArray new];} return self; }
- (NSArray *)items { return self.controller.openBrowserWindowsWebViews.copy ?: @[]; }
- (void)attach:(SEBBrowserWindow *)window controller:(SEBOSXBrowserController *)controller {
    if (![RoundlaneBootstrap currentContestURL].length && !self.contest.length) return;
    if (self.stopping) { self.stopping=NO; self.restored=NO; self.contest=nil; [self.drafts removeAllObjects]; [self.pendingRestores removeAllObjects]; [self.restoreURLs removeAllObjects]; [self.captureVersions removeAllObjects]; [self.closing removeAllObjects]; [self.closed removeAllObjects]; }
    self.controller=controller;
    if (!self.contest) {
        self.contest=[RoundlaneBootstrap currentContestURL];
        unsigned char digest[CC_SHA256_DIGEST_LENGTH]; NSData *data=[self.contest dataUsingEncoding:NSUTF8StringEncoding];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
        NSMutableString *key=[NSMutableString new];for(int i=0;i<CC_SHA256_DIGEST_LENGTH;i++)[key appendFormat:@"%02x",digest[i]];
        NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Roundlane/Workspaces"];
        [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
        self.statePath=[dir stringByAppendingPathComponent:[key stringByAppendingString:@".json"]];
        __weak typeof(self) weak=self;
        self.timer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){[weak save];}];
        self.keys=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event){return [weak handleKey:event] ? nil : event;}];
    }
    RLTabStrip *strip=[[RLTabStrip alloc]initWithFrame:NSZeroRect];strip.wantsLayer=YES;strip.layer.backgroundColor=NSColor.windowBackgroundColor.CGColor;
    strip.accessibilityLabel=@"Вкладки соревнования";
    strip.scroll=[NSScrollView new];strip.scroll.hasHorizontalScroller=YES;strip.scroll.autohidesScrollers=YES;strip.scroll.drawsBackground=NO;
    strip.row=[NSView new];strip.scroll.documentView=strip.row;[strip addSubview:strip.scroll];
    strip.plus=[NSButton buttonWithTitle:@"+" target:self action:@selector(newTab:)];strip.plus.bezelStyle=NSBezelStyleRounded;strip.plus.accessibilityLabel=@"Новая вкладка";strip.plus.toolTip=@"Новая вкладка · ⌘T";[strip addSubview:strip.plus];
    strip.translatesAutoresizingMaskIntoConstraints=NO;[window.contentView addSubview:strip];
    [NSLayoutConstraint activateConstraints:@[[strip.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],[strip.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],[strip.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],[strip.heightAnchor constraintEqualToConstant:38]]];
    [self.strips setObject:strip forKey:window];[self refresh];
}
- (void)refresh {
    NSArray *items=self.items;
    for (NSWindow *window in self.strips.keyEnumerator) {
        RLTabStrip *strip=[self.strips objectForKey:window];for(NSView *view in strip.row.subviews.copy)[view removeFromSuperview];
        CGFloat x=0;NSUInteger index=0; NSRect selectedRect=NSZeroRect;
        for (SEBBrowserOpenWindowWebView *item in items) {
            BOOL main=item.webView.isMainBrowserWebView;BOOL selected=item.browserWindow==window;
            NSString *title=main?@"Roundlane":([item.webView.url.host isEqual:@"cpp.sh"]?@"C++":item.title);
            if (!title.length || [title isEqual:@"Untitled"])title=@"Новая вкладка";
            NSButton *button=[NSButton buttonWithTitle:title target:self action:@selector(selectTab:)];button.tag=index;button.bezelStyle=NSBezelStyleRounded;button.buttonType=NSButtonTypeToggle;button.state=selected?NSControlStateValueOn:NSControlStateValueOff;
            button.font=[NSFont systemFontOfSize:12 weight:selected?NSFontWeightSemibold:NSFontWeightRegular];button.frame=NSMakeRect(x,3,main?130:164,28);button.cell.lineBreakMode=NSLineBreakByTruncatingTail;button.toolTip=item.title;button.accessibilityLabel=[NSString stringWithFormat:@"Вкладка %lu: %@%@",(unsigned long)index+1,title,selected?@", выбрана":@""];
            [strip.row addSubview:button];if(selected)selectedRect=button.frame;x+=main?134:166;
            if(!main){NSButton *close=[NSButton buttonWithTitle:@"×" target:self action:@selector(closeTab:)];close.tag=index;close.bezelStyle=NSBezelStyleRounded;close.frame=NSMakeRect(x,3,26,28);close.accessibilityLabel=[@"Закрыть вкладку " stringByAppendingString:title];close.toolTip=@"Закрыть вкладку · ⌘W";[strip.row addSubview:close];x+=32;}
            index++;
        }
        strip.row.frame=NSMakeRect(0,0,MAX(x,strip.scroll.contentSize.width),34);strip.plus.enabled=items.count<MaxTabs; if(!NSIsEmptyRect(selectedRect))[strip.row scrollRectToVisible:selectedRect];
    }
}
- (void)selectTab:(NSButton *)sender {
    NSArray *items=self.items;if(sender.tag<0 || sender.tag>=items.count)return;
    [self.controller openWindowSelected:items[sender.tag]];[self refresh];[self save];
}
- (NSString *)editorURL:(NSString *)value {
    NSString *clean=SanitizedURL(value,self.contest);if(!clean)return nil;
    NSURL *url=[NSURL URLWithString:clean];if([url.host isEqual:@"cpp.sh"])return @"https://cpp.sh/";
    NSString *path=[[[NSURL URLWithString:self.contest] path] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    path=[@"/" stringByAppendingString:path];
    if(![url.path isEqual:[path stringByAppendingString:@"/submit"]] && ![url.path isEqual:[path stringByAppendingString:@"/customtest"]])return nil;
    NSURLComponents *components=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];components.query=nil;components.fragment=nil;return components.string;
}
- (NSDictionary *)record:(SEBBrowserOpenWindowWebView *)item {
    NSValue *key=[NSValue valueWithNonretainedObject:item.webView];
    NSString *url=SanitizedURL(item.webView.url.absoluteString,self.contest) ?: self.restoreURLs[key];if(!url)return nil;
    NSDictionary *buffers=self.drafts[key];
    if(buffers[@"https://cpp.sh/"] && [[NSURL URLWithString:url].host isEqual:@"cpp.sh"])url=@"https://cpp.sh/";
    NSMutableDictionary *record=[@{@"url":url} mutableCopy];if(buffers.count)record[@"editorDrafts"]=[buffers copy];return record;
}
- (void)captureItem:(SEBBrowserOpenWindowWebView *)item completed:(dispatch_block_t)completed {
    NSString *location=[self editorURL:item.webView.url.absoluteString];id native=item.webView.nativeWebView;
    if(self.stopping || !location || ![native isKindOfClass:WKWebView.class] || [native isLoading] || !EditorBridge().length){if(completed)completed();return;}
    NSValue *key=[NSValue valueWithNonretainedObject:item.webView];NSUInteger version=[self.captureVersions[key] unsignedIntegerValue]+1;self.captureVersions[key]=@(version);
    NSString *expression=@"JSON.stringify(window.__roundlaneEditor.capture())";
    NSDictionary *wanted=[self.pendingRestores[key] containsObject:location]?self.drafts[key][location]:nil;
    if(wanted){
        NSData *json=[NSJSONSerialization dataWithJSONObject:@[wanted] options:0 error:nil];NSString *payload=[[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding];
        expression=[NSString stringWithFormat:@"(()=>{const s=window.__roundlaneEditor.restore(%@[0]);return s==='waiting'?null:JSON.stringify(window.__roundlaneEditor.capture());})()",payload];
    }
    NSString *script=[EditorBridge() stringByAppendingFormat:@"\n%@",expression];__weak typeof(self) weak=self;
    [(WKWebView *)native evaluateJavaScript:script completionHandler:^(id result,NSError *error){
        typeof(self) strong=weak;
        if(strong && !strong.stopping && [strong.items containsObject:item] && [strong.captureVersions[key] unsignedIntegerValue]==version && [[strong editorURL:item.webView.url.absoluteString] isEqual:location] && !error && [result isKindOfClass:NSString.class] && [result length]<=4194304){
            NSDictionary *value=[NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if([value isKindOfClass:NSDictionary.class] && [value[@"code"] isKindOfClass:NSString.class] && [value[@"code"] length]<=262144){
                NSMutableDictionary *buffer=[@{@"code":value[@"code"]} mutableCopy];
                if([value[@"input"] isKindOfClass:NSString.class] && [value[@"input"] length]<=131072)buffer[@"input"]=value[@"input"];
                if(!strong.drafts[key])strong.drafts[key]=[NSMutableDictionary new];strong.drafts[key][location]=buffer;
                [strong.pendingRestores[key] removeObject:location];[strong.restoreURLs removeObjectForKey:key];[strong writeState];
            }
        }
        if(completed)completed();
    }];
}
- (void)closeTab:(NSButton *)sender {
    NSArray *items=self.items;if(sender.tag<0 || sender.tag>=items.count)return;
    SEBBrowserOpenWindowWebView *item=items[sender.tag];if(item.webView.isMainBrowserWebView)return;
    NSValue *key=[NSValue valueWithNonretainedObject:item.webView];if([self.closing containsObject:key])return;[self.closing addObject:key];
    __weak typeof(self) weak=self;
    [self captureItem:item completed:^{
        typeof(self) strong=weak;if(!strong || ![strong.closing containsObject:key] || ![strong.items containsObject:item])return;
        [strong.closing removeObject:key];NSDictionary *record=[strong record:item];
        if(record){[strong.closed addObject:record];if(strong.closed.count>MaxTabs)[strong.closed removeObjectAtIndex:0];}
        [strong.controller closeWebView:item.webView];
    }];
    // A stalled renderer must not discard an editor buffer or freeze the UI.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[weak.closing removeObject:key];});
}
- (void)removed:(NSWindow *)window {
    SEBBrowserWindow *browser=[window isKindOfClass:SEBBrowserWindow.class]?(id)window:nil;
    NSValue *key=browser.webView?[NSValue valueWithNonretainedObject:browser.webView]:nil;
    if(key){[self.drafts removeObjectForKey:key];[self.pendingRestores removeObjectForKey:key];[self.restoreURLs removeObjectForKey:key];[self.captureVersions removeObjectForKey:key];[self.closing removeObject:key];}
    [self.strips removeObjectForKey:window];[self refresh];[self writeState];
}
- (NSURL *)urlFromRecord:(NSDictionary *)record {NSString *url=SanitizedURL(record[@"url"],self.contest);return url?[NSURL URLWithString:url]:nil;}
- (void)openRecord:(NSDictionary *)record {
    NSURL *url=[self urlFromRecord:record];if(!url)return;
    SEBAbstractWebView *view=[self.controller openAndShowWebViewWithURL:url configuration:nil];if(!view)return;
    NSValue *key=[NSValue valueWithNonretainedObject:view];NSMutableDictionary *buffers=[NSMutableDictionary new];
    NSDictionary *saved=record[@"editorDrafts"];
    if([saved isKindOfClass:NSDictionary.class])for(NSString *candidate in saved){
        NSString *location=[self editorURL:candidate];NSDictionary *buffer=saved[candidate];
        if(location && [buffer isKindOfClass:NSDictionary.class] && [buffer[@"code"] isKindOfClass:NSString.class] && [buffer[@"code"] length]<=262144){
            NSMutableDictionary *clean=[@{@"code":buffer[@"code"]} mutableCopy];if([buffer[@"input"] isKindOfClass:NSString.class] && [buffer[@"input"] length]<=131072)clean[@"input"]=buffer[@"input"];buffers[location]=clean;
        }
    }
    if([record[@"draft"] isKindOfClass:NSString.class] && [record[@"draft"] length]<=262144 && [url.host isEqual:@"cpp.sh"])buffers[@"https://cpp.sh/"]=@{@"code":record[@"draft"]};
    self.drafts[key]=buffers;self.pendingRestores[key]=[NSMutableSet setWithArray:buffers.allKeys];self.restoreURLs[key]=url.absoluteString;
    [self pageLoaded:view];
}
- (void)pageLoaded:(id)view {for(SEBBrowserOpenWindowWebView *item in self.items)if(item.webView==view){[self captureItem:item completed:nil];break;}}
- (void)newTab:(id)sender {if(self.items.count<MaxTabs)[self.controller openAndShowWebViewWithURL:[NSURL URLWithString:self.contest] ?: self.controller.startURL configuration:nil];}
- (void)reopen {if(self.items.count>=MaxTabs || !self.closed.count)return;NSDictionary *record=self.closed.lastObject;[self.closed removeLastObject];[self openRecord:record];}
- (BOOL)handleKey:(NSEvent *)event {
    if(self.stopping || ![NSApp.keyWindow isKindOfClass:SEBBrowserWindow.class] || NSApp.modalWindow)return NO;
    BOOL command=(event.modifierFlags&NSEventModifierFlagCommand)!=0;BOOL control=(event.modifierFlags&NSEventModifierFlagControl)!=0;BOOL shift=(event.modifierFlags&NSEventModifierFlagShift)!=0;if(!command && !(control && event.keyCode==48))return NO;
    NSString *key=event.charactersIgnoringModifiers.lowercaseString;NSArray *items=self.items;
    if(command && ([key isEqual:@"t"] || event.keyCode==17)){if(shift)[self reopen];else[self newTab:nil];return YES;}
    if(command && ([key isEqual:@"w"] || event.keyCode==13)){NSUInteger index=[items indexOfObjectPassingTest:^BOOL(SEBBrowserOpenWindowWebView *item,NSUInteger i,BOOL *stop){return item.browserWindow==NSApp.keyWindow;}];if(index!=NSNotFound){NSButton *b=[NSButton new];b.tag=index;[self closeTab:b];}return YES;}
    if(event.keyCode==48){if(shift)[self.controller activatePreviousOpenWindow];else[self.controller activateNextOpenWindow];[self refresh];return YES;}
    if(command && key.length==1 && [key characterAtIndex:0]>='1' && [key characterAtIndex:0]<='9' && items.count){NSUInteger index=[key isEqual:@"9"]?items.count-1:([key integerValue]-1);if(index<items.count){NSButton *b=[NSButton new];b.tag=index;[self selectTab:b];}return YES;}
    return NO;
}
- (void)restore {
    if(self.restored || self.stopping)return;self.restored=YES;
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:self.statePath error:nil];if([attrs[NSFileSize] unsignedLongLongValue]>67108864)return;
    NSData *data=[NSData dataWithContentsOfFile:self.statePath];NSDictionary *state=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if(![state isKindOfClass:NSDictionary.class] || ![state[@"contest"] isEqual:self.contest] || ![state[@"tabs"] isKindOfClass:NSArray.class])return;
    NSUInteger count=0;for(id record in state[@"tabs"]){if(count++>=MaxTabs-1)break;if(![record isKindOfClass:NSDictionary.class])continue;[self openRecord:record];}
    NSInteger active=[state[@"active"] respondsToSelector:@selector(integerValue)]?[state[@"active"] integerValue]:0;NSArray *items=self.items;if(active>=0 && active<items.count)[self.controller openWindowSelected:items[active]];[self refresh];
}
- (void)save {
    if(self.stopping || !self.restored || !self.items.count || !self.statePath)return;
    for(SEBBrowserOpenWindowWebView *item in self.items)if(!item.webView.isMainBrowserWebView)[self captureItem:item completed:nil];
    [self writeState];
}
- (void)writeState {
    if(self.stopping || !self.statePath || !self.restored || !self.items.count)return;
    NSMutableArray *tabs=[NSMutableArray new]; NSUInteger active=0;
    for(SEBBrowserOpenWindowWebView *item in self.items){
        if(item.browserWindow==self.controller.activeBrowserWindow)active=tabs.count+(item.webView.isMainBrowserWebView?0:1);
        if(item.webView.isMainBrowserWebView)continue;
        NSDictionary *record=[self record:item];if(record && tabs.count<MaxTabs-1)[tabs addObject:record];
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"version":@2,@"contest":self.contest,@"tabs":tabs,@"active":@(active)} options:0 error:nil];
    if(data.length<=67108864 && [data writeToFile:self.statePath options:NSDataWritingAtomic error:nil])[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:self.statePath error:nil];
}

- (void)finish {
    [self.timer invalidate];self.timer=nil;
    __block NSUInteger pending=0;
    for(SEBBrowserOpenWindowWebView *item in self.items)if(!item.webView.isMainBrowserWebView){pending++;[self captureItem:item completed:^{pending--;}];}
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:1];while(pending && deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    [self writeState];self.stopping=YES;[self.timer invalidate];self.timer=nil;if(self.keys){[NSEvent removeMonitor:self.keys];self.keys=nil;} }
 + (int)diagnostic {
    NSString *base=@"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contest/723396";
    NSMutableDictionary *checks=[NSMutableDictionary new];
    checks[@"editor_bridge"]=@(EditorBridge().length>100 && [EditorBridge() containsString:@"window.ace"]);
    NSString *filtered=SanitizedURL([base stringByAppendingString:@"/my?csrf_token=secret&locale=ru"],base);
    checks[@"contest_page"]=@(filtered!=nil);checks[@"auth_removed"]=@([filtered isEqual:[base stringByAppendingString:@"/my?locale=ru"]]);
    NSUInteger i=0;for(NSString *url in @[@"https://google.com/",@"https://roundlane723396.contest.codeforces.com/enter?password=x",@"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contest/723397",@"https://cpp.sh@evil.test/",@"file:///tmp/test"]){checks[[NSString stringWithFormat:@"forbidden_%lu",(unsigned long)++i]]=@(SanitizedURL(url,base)==nil);}
    NSString *compiler=SanitizedURL(@"https://cpp.sh/?source=int%20main%28%29%7B%7D&token=secret",base);
    NSArray *query=[NSURLComponents componentsWithString:compiler].queryItems;
    checks[@"compiler_source"]=@(query.count==1 && [((NSURLQueryItem *)query.firstObject).value isEqual:@"int main(){}"]);
    BOOL ok=YES;for(NSNumber *passed in checks.allValues)ok=ok&&passed.boolValue;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"tabs_check":ok?@"passed":@"failed",@"checks":checks,@"exam_started":@NO} options:0 error:nil];fwrite(data.bytes,1,data.length,stdout);fputs("\n",stdout);return ok?0:1;
}
 + (int)preview {
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    RoundlaneTabs *tabs=self.shared;tabs.contest=@"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contest/723396";
    tabs.statePath=[NSTemporaryDirectory() stringByAppendingPathComponent:@"roundlane-tabs-preview.json"];
    RLPreviewController *browser=[RLPreviewController new];browser.openBrowserWindowsWebViews=[NSMutableArray new];browser.previewStartURL=[NSURL URLWithString:tabs.contest];
    __weak RoundlaneTabs *weak=tabs;tabs.keys=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e){if((e.modifierFlags&NSEventModifierFlagCommand)&&([e.charactersIgnoringModifiers.lowercaseString isEqual:@"q"] || e.keyCode==12)){[tabs finish];[NSApp stop:nil];return nil;}return [weak handleKey:e]?nil:e;}];
    tabs.timer=[NSTimer scheduledTimerWithTimeInterval:2 repeats:YES block:^(NSTimer *timer){[weak save];}];
    [browser openAndShowWebViewWithURL:browser.startURL configuration:nil];[tabs restore];
    if(browser.openBrowserWindowsWebViews.count==1){[browser openAndShowWebViewWithURL:[NSURL URLWithString:[tabs.contest stringByAppendingString:@"/problem/A"]] configuration:nil];[browser openAndShowWebViewWithURL:[NSURL URLWithString:@"https://cpp.sh/"] configuration:nil];}
    [NSApp activateIgnoringOtherApps:YES];[NSApp run];return 0;
}
@end
