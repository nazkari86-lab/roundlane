// Roundlane additions, licensed under the Mozilla Public License 2.0.
#import "RoundlaneBootstrap.h"
#import "RoundlaneMacGuard.h"
#import "SafeExamBrowser-Swift.h"
#import <CommonCrypto/CommonDigest.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#include <unistd.h>

static NSString *sessionDirectory;
static NSString *sessionProfile;
static NSString *sessionQuitHash;
static NSString *sessionContestURL;
static NSTask *hubTask;
static BOOL preparationFailed;

static NSURL *resources(void) {
    return [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"Roundlane"];
}

static NSString *normalizedGroup(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [trimmed hasPrefix:@"codeforces.com/"] ? [@"https://" stringByAppendingString:trimmed] : trimmed;
}

static BOOL validGroup(NSString *text) {
    NSURLComponents *url = [NSURLComponents componentsWithString:text];
    BOOL host = [url.host isEqual:@"codeforces.com"] ||
        [url.host rangeOfString:@"\\A[a-z][a-z0-9]{2,19}\\.contest\\.codeforces\\.com\\z" options:NSRegularExpressionSearch].location != NSNotFound;
    return url.host.length && host && [url.scheme isEqual:@"https"] && !url.port && !url.user && !url.password && !url.fragment && !url.query
        && [url.percentEncodedPath rangeOfString:@"\\A/group/[A-Za-z0-9_-]+/contest/[1-9][0-9]*/?\\z" options:NSRegularExpressionSearch].location != NSNotFound;
}

static NSString *const testContest = @"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contest/723396";

static NSArray *contestRules(NSString *contest) {
    if (!validGroup(contest)) return nil;
    NSURLComponents *url = [NSURLComponents componentsWithString:contest];
    NSString *path = [url.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    path = [@"/" stringByAppendingString:path];
    NSArray *parts = [path componentsSeparatedByString:@"/"];
    NSString *host = [NSRegularExpression escapedPatternForString:url.host];
    NSString *group = [NSRegularExpression escapedPatternForString:[NSString stringWithFormat:@"/group/%@",parts[2]]];
    NSString *base = [NSString stringWithFormat:@"^https://%@",host];
    NSString *contestPath = [NSRegularExpression escapedPatternForString:path];
    NSMutableArray *expressions = [NSMutableArray arrayWithArray:@[
        @"^http://127\\.0\\.0\\.1:18765/",
        [NSString stringWithFormat:@"%@%@/?([?#].*)?$",base,contestPath],
        [NSString stringWithFormat:@"%@%@/",base,contestPath],
        [NSString stringWithFormat:@"%@%@/?([?#].*)?$",base,group],
        [NSString stringWithFormat:@"%@%@/contests/?([?#].*)?$",base,group],
        [NSString stringWithFormat:@"%@/enter([?#].*)?$",base],
        [NSString stringWithFormat:@"%@/[a-f0-9]+/logout([?#].*)?$",base],
        [url.host isEqual:@"codeforces.com"] ? @"^$" : [NSString stringWithFormat:@"%@/([?#].*)?$",base],
        [NSString stringWithFormat:@"^blob:https://%@/",host],
        @"^https://assets\\.codeforces\\.com/",
        @"^https://challenges\\.cloudflare\\.com/",
        @"^https://cpp\\.sh/"
    ]];
    // WebKit's content rule compiler does not support regex disjunctions.
    // Participant AJAX routes live under the group, outside /contest/.
    for (NSString *endpoint in @[@"customtest",@"submitSource",@"judgeProtocol",@"submissionVerdict",@"standings",@"contests",@"newProblemQuestion",@"changeProblemQuestionOrAnnouncementDataPage"]) {
        [expressions addObject:[NSString stringWithFormat:@"%@%@/data/%@([?#].*)?$",base,group,endpoint]];
    }
    // PushStream receives verdicts and announcements on the selected host.
    for (NSString *endpoint in @[@"ws",@"ev",@"lp"]) [expressions addObject:[NSString stringWithFormat:@"%@/%@/",base,endpoint]];
    [expressions addObject:[NSString stringWithFormat:@"^wss://%@/ws/",host]];
    for (NSString *directory in @[@"s",@"data",@"cdn-cgi"]) [expressions addObject:[NSString stringWithFormat:@"%@/%@/",base,directory]];
    for (NSString *extension in @[@"css",@"js",@"png",@"jpg",@"jpeg",@"gif",@"svg",@"ico",@"woff",@"woff2",@"ttf",@"eot"]) [expressions addObject:[NSString stringWithFormat:@"%@/[^?#]*\\.%@([?#].*)?$",base,extension]];
    NSMutableArray *rules = [NSMutableArray new];
    for (NSString *expression in expressions) [rules addObject:@{@"action":@1,@"active":@YES,@"regex":@YES,@"expression":expression}];
    return rules;
}

static BOOL validCode(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    return [text rangeOfString:@"\\A[A-Za-z0-9]{4,32}\\z" options:NSRegularExpressionSearch].location != NSNotFound;
}

// Only the user's Keychain receives the organizer's plaintext code.
static NSMutableDictionary *codeQuery(NSString *service) {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:service,(__bridge id)kSecAttrAccount:@"organizer"} mutableCopy];
}
static NSString *readCode(NSString *service, OSStatus *status) {
    NSMutableDictionary *query=codeQuery(service);query[(__bridge id)kSecReturnData]=@YES;
    query[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
    query[(__bridge id)kSecUseAuthenticationUI]=(__bridge id)kSecUseAuthenticationUIFail;
    CFTypeRef value=NULL;*status=SecItemCopyMatching((__bridge CFDictionaryRef)query,&value);
    NSData *data=CFBridgingRelease(value);if(*status!=errSecSuccess)return nil;
    NSString *code=[data isKindOfClass:NSData.class] && data.length<=128?[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]:nil;
    if(!validCode(code)){*status=errSecDecode;return nil;}return code;
}
static OSStatus writeCode(NSString *service, NSString *code) {
    if(!validCode(code))return errSecParam;
    NSMutableDictionary *query=codeQuery(service);NSDictionary *value=@{(__bridge id)kSecValueData:[code dataUsingEncoding:NSUTF8StringEncoding]};
    OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)query,(__bridge CFDictionaryRef)value);
    if(status==errSecItemNotFound){[query addEntriesFromDictionary:value];query[(__bridge id)kSecAttrLabel]=@"Roundlane — код выхода";status=SecItemAdd((__bridge CFDictionaryRef)query,NULL);}
    return status;
}
static NSString *codeService(void) {
    NSArray *args=NSProcessInfo.processInfo.arguments;NSUInteger index=[args indexOfObject:@"--code-store-test-scope"];
    if(index!=NSNotFound){if(index+1>=args.count)return nil;NSUUID *uuid=[[NSUUID alloc]initWithUUIDString:args[index+1]];return uuid?[@"local.roundlane.organizer.exit-code.tests." stringByAppendingString:uuid.UUIDString]:nil;}
    return @"local.roundlane.organizer.exit-code";
}
static BOOL codeDiagnosticsOnly(void) {
    NSArray *args=NSProcessInfo.processInfo.arguments;
    return ([args containsObject:@"--preflight-only"] || [args containsObject:@"--preflight-check"]) && ![args containsObject:@"--code-store-test-scope"];
}

static NSString *randomCode(void) {
    NSString *alphabet = @"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
    NSMutableString *code = [NSMutableString new];
    for (NSUInteger i = 0; i < 12; i++) [code appendFormat:@"%C", [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)]];
    return code;
}

static NSString *hashCode(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hash = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [hash appendFormat:@"%02X", digest[i]];
    return hash;
}

static BOOL validHash(NSString *hash) {
    return [hash isKindOfClass:NSString.class] && [hash rangeOfString:@"\\A[A-Fa-f0-9]{64}\\z" options:NSRegularExpressionSearch].location != NSNotFound;
}

static NSDictionary *competitionSettings(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *input = value;
    BOOL participant=[input[@"format"] isEqual:@"roundlane-participant"];
    NSSet *keys = [NSSet setWithArray:participant?@[@"format", @"version", @"groupURL", @"quitPasswordHash", @"signature"]:@[@"format", @"version", @"groupURL", @"quitPasswordHash"]];
    if (![[NSSet setWithArray:input.allKeys] isEqual:keys]
        || (!participant && ![input[@"format"] isEqual:@"roundlane-competition"])
        || ![input[@"version"] isKindOfClass:NSNumber.class]
        || CFGetTypeID((__bridge CFTypeRef)input[@"version"]) == CFBooleanGetTypeID()
        || !strchr("csilqCSILQ", [input[@"version"] objCType][0])
        || ![input[@"version"] isEqual:@1]
        || ![input[@"groupURL"] isKindOfClass:NSString.class]
        || !validGroup(normalizedGroup(input[@"groupURL"])) || !validHash(input[@"quitPasswordHash"])) return nil;
    NSMutableDictionary *result=[@{@"format":participant?@"roundlane-participant":@"roundlane-competition", @"version":@1,
        @"groupURL":normalizedGroup(input[@"groupURL"]), @"quitPasswordHash":[input[@"quitPasswordHash"] uppercaseString]} mutableCopy];
    if(participant){
        if(![input[@"signature"] isKindOfClass:NSString.class])return nil;
        NSString *payload=[NSString stringWithFormat:@"Roundlane participant v1\n%@\n%@\n",result[@"groupURL"],result[@"quitPasswordHash"]];
        if(![RoundlaneReleaseBinding verifyParticipant:input[@"signature"] payload:payload])return nil;
        result[@"signature"]=input[@"signature"];
    }
    return result;
}

static NSDictionary *readCompetition(NSString *path, NSString **message) {
    NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!file) { if (message) *message = @"Не удалось открыть файл настроек"; return nil; }
    NSError *error = nil;
    NSData *data = [file readDataUpToLength:65537 error:&error];
    [file closeAndReturnError:nil];
    if (!data || error) { if (message) *message = @"Не удалось прочитать файл настроек"; return nil; }
    if (data.length > 65536) { if (message) *message = @"Файл настроек слишком большой (максимум 64 КиБ)"; return nil; }
    NSDictionary *result = competitionSettings([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
    if (!result && message) *message = @"Неверный файл настроек: проверьте версию, группу и код выхода";
    return result;
}

static NSString *argumentValue(NSString *key) {
    NSArray *args = NSProcessInfo.processInfo.arguments;
    NSUInteger index = [args indexOfObject:key];
    return index != NSNotFound && index + 1 < args.count ? args[index + 1] : nil;
}

static NSMutableDictionary *profileWithHash(NSString *quitHash, NSString *contest) {
    NSData *data = [NSData dataWithContentsOfURL:[resources() URLByAppendingPathComponent:@"contest.seb"]];
    if (!data) return nil;
    NSMutableDictionary *settings = [[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:nil error:nil] mutableCopy];
    if (![settings isKindOfClass:NSMutableDictionary.class] || !validHash(quitHash) || !validGroup(contest)) return nil;
    settings[@"URLFilterRules"] = contestRules(contest);
    settings[@"hashedQuitPassword"] = quitHash.uppercaseString;
    settings[@"allowQuit"] = @YES;
    settings[@"showQuitButton"] = @YES;
    settings[@"sebConfigPurpose"] = @0;
    settings[@"lockdownModePolicy"] = @1;
    settings[@"allowPreferencesWindow"] = @NO;
    settings[@"downloadAndOpenSebConfig"] = @NO;
    settings[@"allowSwitchToApplications"] = @NO;
    settings[@"browserWindowWebView"] = @3;
    return settings;
}

static NSMutableDictionary *profile(NSString *code) {
    return validCode(code) ? profileWithHash(hashCode(code), testContest) : nil;
}

// A disposable browser for organizer checks. It never calls prepare or SEBController.
@interface RoundlaneBrowserCheck : NSObject <WKNavigationDelegate, WKUIDelegate, NSWindowDelegate, NSApplicationDelegate>
@property NSWindow *window;
@property WKWebView *web;
@property NSTextField *status;
@property NSArray *rules;
@property NSString *contestURL;
@end

@implementation RoundlaneBrowserCheck
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {return NO;}
- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)files {[sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];}
- (BOOL)allowed:(NSURL *)url {
    if ([url.absoluteString isEqual:@"about:blank"]) return YES;
    for (NSDictionary *rule in self.rules) {
        if ([url.absoluteString rangeOfString:rule[@"expression"] options:NSRegularExpressionSearch | NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}
- (void)close:(id)sender { [self.web stopLoading]; [NSApp stop:nil]; [self.window orderOut:nil]; }
- (BOOL)windowShouldClose:(NSWindow *)window { [self close:nil]; return YES; }
- (void)back:(id)sender { [self.web goBack]; }
- (void)reload:(id)sender { [self.web reload]; }
- (void)codeforces:(id)sender { [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.contestURL]]]; }
- (void)compiler:(id)sender {
    NSString *source = [NSString stringWithContentsOfURL:[resources() URLByAppendingPathComponent:@"starter.cpp"] encoding:NSUTF8StringEncoding error:nil];
    NSURLComponents *url = [NSURLComponents componentsWithString:@"https://cpp.sh/"];
    url.queryItems = @[[NSURLQueryItem queryItemWithName:@"source" value:source ?: @""]];
    [self.web loadRequest:[NSURLRequest requestWithURL:url.URL]];
}
- (void)webView:(WKWebView *)web decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decision {
    // Cloudflare builds a local srcdoc iframe; it makes no external navigation.
    WKSecurityOrigin *origin = action.sourceFrame.securityOrigin;
    BOOL serviceFrame = action.targetFrame && !action.targetFrame.mainFrame &&
        [action.request.URL.absoluteString isEqual:@"about:srcdoc"] &&
        [origin.protocol isEqual:@"https"] &&
        ([origin.host isEqual:[NSURL URLWithString:self.contestURL].host] || [origin.host isEqual:@"challenges.cloudflare.com"]) && [self allowed:action.sourceFrame.request.URL];
    BOOL allowed = serviceFrame || [self allowed:action.request.URL];
    if (!allowed) self.status.stringValue = @"Адрес заблокирован фильтром соревнования";
    decision(allowed ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (WKWebView *)webView:(WKWebView *)web createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if ([self allowed:action.request.URL]) [web loadRequest:action.request];
    else self.status.stringValue = @"Адрес заблокирован фильтром соревнования";
    return nil;
}
- (void)webView:(WKWebView *)web didStartProvisionalNavigation:(WKNavigation *)navigation { self.status.stringValue = @"Загрузка сайта…"; }
- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
    self.status.stringValue = @"Страница загружена. Проверьте вход и работу сайта";
}
- (void)webView:(WKWebView *)web didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (error.code != NSURLErrorCancelled) self.status.stringValue = @"Сайт не загрузился. Проверьте сеть и повторите";
}
- (void)webView:(WKWebView *)web didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self webView:web didFailProvisionalNavigation:navigation withError:error]; }
- (void)webView:(WKWebView *)web runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completion {
    NSAlert *alert = [NSAlert new]; alert.messageText = message; [alert runModal]; completion();
}
- (void)webView:(WKWebView *)web runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completion {
    NSAlert *alert = [NSAlert new]; alert.messageText = message; [alert addButtonWithTitle:@"OK"]; [alert addButtonWithTitle:@"Отмена"]; completion([alert runModal] == NSAlertFirstButtonReturn);
}
- (void)show {
    self.contestURL = argumentValue(@"--contest-url") ?: testContest;
    NSDictionary *settings = profileWithHash(hashCode(@"1234"), self.contestURL);
    self.rules = settings[@"URLFilterRules"];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1100,760) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Roundlane — проверка сайтов, без блокировки";
    self.window.contentMinSize = NSMakeSize(700,500); self.window.delegate = self; self.window.releasedWhenClosed = NO;
    NSView *view = self.window.contentView;
    NSStackView *bar = [NSStackView new]; bar.orientation = NSUserInterfaceLayoutOrientationHorizontal; bar.spacing = 8;
    for (NSArray *item in @[@[@"Назад",@"back:"],@[@"Обновить",@"reload:"],@[@"Codeforces",@"codeforces:"],@[@"C++",@"compiler:"],@[@"Закрыть",@"close:"]]) {
        NSButton *button = [NSButton buttonWithTitle:item[0] target:self action:NSSelectorFromString(item[1])]; button.bezelStyle = NSBezelStyleRounded; [bar addArrangedSubview:button];
    }
    self.status = [NSTextField labelWithString:@"Подготовка фильтра…"]; self.status.accessibilityLabel = @"Результат проверки сайта";
    self.status.font = [NSFont systemFontOfSize:12]; self.status.textColor = NSColor.secondaryLabelColor;
    WKWebViewConfiguration *config = [WKWebViewConfiguration new]; config.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    self.web = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:config]; self.web.navigationDelegate = self; self.web.UIDelegate = self;
    for (NSView *v in @[bar,self.status,self.web]) { v.translatesAutoresizingMaskIntoConstraints = NO; [view addSubview:v]; }
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:12],[bar.topAnchor constraintEqualToAnchor:view.topAnchor constant:8],
        [self.status.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor],[self.status.topAnchor constraintEqualToAnchor:bar.bottomAnchor constant:6],
        [self.status.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-12],
        [self.web.topAnchor constraintEqualToAnchor:self.status.bottomAnchor constant:8],[self.web.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [self.web.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],[self.web.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]
    ]];
    NSMenu *menu = [NSMenu new]; NSMenuItem *app = [NSMenuItem new]; app.submenu = [NSMenu new];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Закрыть проверку" action:@selector(close:) keyEquivalent:@"q"]; quit.target = self;
    [app.submenu addItem:quit]; [menu addItem:app];
    NSMenuItem *edit = [[NSMenuItem alloc] initWithTitle:@"Правка" action:nil keyEquivalent:@""];
    edit.submenu = [[NSMenu alloc] initWithTitle:@"Правка"];
    for (NSArray *command in @[@[@"Отменить",@"undo:",@"z"],@[@"Вырезать",@"cut:",@"x"],@[@"Копировать",@"copy:",@"c"],@[@"Вставить",@"paste:",@"v"],@[@"Выделить всё",@"selectAll:",@"a"]]) {
        [edit.submenu addItem:[[NSMenuItem alloc] initWithTitle:command[0] action:NSSelectorFromString(command[1]) keyEquivalent:command[2]]];
    }
    [menu addItem:edit]; NSApp.mainMenu = menu;
    NSMutableArray *filter = [NSMutableArray arrayWithObject:@{@"trigger":@{@"url-filter":@".*"},@"action":@{@"type":@"block"}}];
    for (NSDictionary *rule in self.rules) [filter addObject:@{@"trigger":@{@"url-filter":rule[@"expression"]},@"action":@{@"type":@"ignore-previous-rules"}}];
    // Blob workers inherit their approved origin. Their network requests still use the URL filter.
    for (NSString *expression in @[[NSString stringWithFormat:@"^blob:https://%@/",[NSRegularExpression escapedPatternForString:[NSURL URLWithString:self.contestURL].host]], @"^blob:https://challenges\\.cloudflare\\.com/"]) {
        [filter addObject:@{@"trigger":@{@"url-filter":expression},@"action":@{@"type":@"ignore-previous-rules"}}];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:filter options:0 error:nil];
    [WKContentRuleListStore.defaultStore compileContentRuleListForIdentifier:@"RoundlaneBrowserCheck" encodedContentRuleList:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] completionHandler:^(WKContentRuleList *list, NSError *error) {
        if (!list || error) { self.status.stringValue = @"Фильтр не подготовлен. Проверка остановлена"; return; }
        [self.web.configuration.userContentController addContentRuleList:list];
        [self.web evaluateJavaScript:@"navigator.userAgent" completionHandler:^(id value,NSError *error) {
            if (![value isKindOfClass:NSString.class] || error) { self.status.stringValue = @"Не удалось подготовить браузер"; return; }
            NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            // Match SEBBrowserController's default WebKit/Safari suffix as well as its SEB identifiers.
            NSString *webkit = @"605.1.15";
            NSRange range = [value rangeOfString:@"AppleWebKit/"];
            if (range.location != NSNotFound) webkit = [[[value substringFromIndex:NSMaxRange(range)] componentsSeparatedByString:@" "] firstObject];
            self.web.customUserAgent = [value stringByAppendingFormat:@" Version/18.3 Safari/%@ SEB/%@ SEB/3.5.4 SEB/3.6 SEB/3.6.1 SEB/3.7",webkit,version];
            NSString *url = argumentValue(@"--browser-check-url") ?: self.contestURL;
            NSURL *initialURL = [NSURL URLWithString:url];
            if (!initialURL || ![self allowed:initialURL]) { self.status.stringValue = @"Адрес заблокирован фильтром соревнования"; return; }
            [self.web loadRequest:[NSURLRequest requestWithURL:initialURL]];
        }];
    }];
    [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
@end

@interface RoundlaneOrganizer : NSObject <NSTextFieldDelegate, NSWindowDelegate>
@property NSWindow *window;
@property NSTextField *group;
@property NSTextField *code;
@property NSTextField *status;
@property NSButton *start;
@property NSButton *clipboardButton;
@property NSButton *generateButton;
@property NSButton *openButton;
@property NSButton *saveButton;
@property NSDictionary *loadedSettings;
@property NSString *settingsError;
@property BOOL checking;
@property BOOL inspectionOnly;
@property NSButton *browserCheckButton;
@property NSButton *closeButton;
@property BOOL codeRestoreFailed;
@property NSDictionary *result;
@end

@implementation RoundlaneOrganizer
- (NSTextField *)label:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [NSFont systemFontOfSize:13];
    return label;
}
- (NSButton *)button:(NSString *)text action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:text target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}
- (void)show {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Roundlane"];
    NSMenuItem *application = [NSMenuItem new];
    application.submenu = [[NSMenu alloc] initWithTitle:@"Roundlane"];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Закрыть Roundlane" action:@selector(close:) keyEquivalent:@"q"];
    quit.target = self;
    [application.submenu addItem:quit];
    [menu addItem:application];
    NSMenuItem *edit = [[NSMenuItem alloc] initWithTitle:@"Правка" action:nil keyEquivalent:@""];
    edit.submenu = [[NSMenu alloc] initWithTitle:@"Правка"];
    for (NSArray *command in @[@[@"Отменить", @"undo:", @"z"], @[@"Вырезать", @"cut:", @"x"],
        @[@"Копировать", @"copy:", @"c"], @[@"Вставить", @"paste:", @"v"], @[@"Выделить всё", @"selectAll:", @"a"]]) {
        [edit.submenu addItem:[[NSMenuItem alloc] initWithTitle:command[0] action:NSSelectorFromString(command[1]) keyEquivalent:command[2]]];
    }
    [menu addItem:edit];
    NSApp.mainMenu = menu;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 365)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Roundlane";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.contentMinSize = NSMakeSize(500, 365);
    self.window.contentMaxSize = NSMakeSize(900, 365);
    NSView *view = self.window.contentView;
    NSTextField *groupLabel = [self label:@"Соревнование Codeforces"];
    self.group = [NSTextField textFieldWithString:[NSUserDefaults.standardUserDefaults stringForKey:@"lastGroupURL"] ?: @""];
    self.group.placeholderString = @"https://…contest.codeforces.com/group/…/contest/…";
    self.group.accessibilityLabel = @"Ссылка на соревнование Codeforces";
    self.group.font = [NSFont systemFontOfSize:14];
    self.group.delegate = self;
    NSTextField *codeLabel = [self label:@"Код выхода"];
    NSString *initialCode=@"1234";
    if(!argumentValue(@"--settings") && !codeDiagnosticsOnly()) {
        OSStatus status=errSecParam;NSString *service=codeService();NSString *saved=service?readCode(service,&status):nil;
        if(saved)initialCode=saved;else if(status!=errSecItemNotFound){initialCode=@"";self.codeRestoreFailed=YES;}
    }
    self.code = [NSTextField textFieldWithString:initialCode];
    self.code.font = [NSFont monospacedDigitSystemFontOfSize:17 weight:NSFontWeightMedium];
    self.code.accessibilityLabel = @"Код выхода организатора";
    self.code.delegate = self;
    NSButton *generate = [self button:@"Новый код" action:@selector(generateCode:)];
    self.generateButton = generate;
    generate.accessibilityHelp = @"Создать случайный пароль из 12 букв и цифр";
    self.clipboardButton = [self button:@"Копировать" action:@selector(copyCode:)];
    self.clipboardButton.accessibilityHelp = @"Скопировать код выхода";
    self.openButton = [self button:@"Открыть настройки" action:@selector(openSettings:)];
    self.openButton.accessibilityLabel = @"Открыть общий файл соревнования";
    self.saveButton = [self button:@"Сохранить настройки" action:@selector(saveSettings:)];
    self.saveButton.accessibilityLabel = @"Сохранить общий файл соревнования";
    self.status = [self label:@""];
    self.status.textColor = NSColor.secondaryLabelColor;
    self.status.maximumNumberOfLines = 2;
    self.status.lineBreakMode = NSLineBreakByWordWrapping;
    self.status.accessibilityLabel = @"Состояние подготовки";
    NSButton *close = [self button:@"Закрыть" action:@selector(close:)];
    self.closeButton = close;
    NSButton *browserCheck = [self button:@"Проверить сайты" action:@selector(browserCheck:)];
    self.browserCheckButton = browserCheck;
    browserCheck.accessibilityHelp = @"Открыть браузер проверки без блокировки компьютера";
    close.keyEquivalent = @"\033";
    self.start = [self button:self.checking ? @"Проверить запуск" : @"Начать соревнование" action:@selector(start:)];
    // A Return in either editor must never enter the exam.
    self.start.keyEquivalent = @"";
    self.start.accessibilityHelp = @"Открыть подтверждение с кодом выхода";
    for (NSView *control in @[groupLabel, self.group, codeLabel, self.code, generate, self.clipboardButton, self.openButton, self.saveButton, self.status, close, browserCheck, self.start]) {
        control.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:control];
    }
    [NSLayoutConstraint activateConstraints:@[
        [groupLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24],
        [groupLabel.topAnchor constraintEqualToAnchor:view.topAnchor constant:24],
        [self.group.topAnchor constraintEqualToAnchor:groupLabel.bottomAnchor constant:8],
        [self.group.leadingAnchor constraintEqualToAnchor:groupLabel.leadingAnchor],
        [self.group.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-24],
        [self.group.heightAnchor constraintEqualToConstant:30],
        [codeLabel.topAnchor constraintEqualToAnchor:self.group.bottomAnchor constant:24],
        [codeLabel.leadingAnchor constraintEqualToAnchor:groupLabel.leadingAnchor],
        [self.code.topAnchor constraintEqualToAnchor:codeLabel.bottomAnchor constant:8],
        [self.code.leadingAnchor constraintEqualToAnchor:groupLabel.leadingAnchor],
        [self.code.widthAnchor constraintEqualToConstant:175],
        [self.code.heightAnchor constraintEqualToConstant:30],
        [generate.leadingAnchor constraintEqualToAnchor:self.code.trailingAnchor constant:12],
        [generate.centerYAnchor constraintEqualToAnchor:self.code.centerYAnchor],
        [self.clipboardButton.leadingAnchor constraintEqualToAnchor:generate.trailingAnchor constant:8],
        [self.clipboardButton.centerYAnchor constraintEqualToAnchor:self.code.centerYAnchor],
        [self.openButton.leadingAnchor constraintEqualToAnchor:groupLabel.leadingAnchor],
        [self.openButton.topAnchor constraintEqualToAnchor:self.code.bottomAnchor constant:16],
        [self.saveButton.leadingAnchor constraintEqualToAnchor:self.openButton.trailingAnchor constant:8],
        [self.saveButton.centerYAnchor constraintEqualToAnchor:self.openButton.centerYAnchor],
        [self.status.leadingAnchor constraintEqualToAnchor:groupLabel.leadingAnchor],
        [self.status.trailingAnchor constraintEqualToAnchor:self.group.trailingAnchor],
        [self.status.topAnchor constraintEqualToAnchor:self.openButton.bottomAnchor constant:16],
        [self.status.heightAnchor constraintGreaterThanOrEqualToConstant:36],
        [self.start.trailingAnchor constraintEqualToAnchor:self.group.trailingAnchor],
        [self.start.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-24],
        [close.leadingAnchor constraintEqualToAnchor:groupLabel.leadingAnchor],
        [browserCheck.leadingAnchor constraintEqualToAnchor:close.trailingAnchor constant:8],
        [browserCheck.centerYAnchor constraintEqualToAnchor:self.start.centerYAnchor],
        [close.centerYAnchor constraintEqualToAnchor:self.start.centerYAnchor]
    ]];
    self.group.nextKeyView = self.code;
    self.code.nextKeyView = generate;
    generate.nextKeyView = self.clipboardButton;
    self.clipboardButton.nextKeyView = self.openButton;
    self.openButton.nextKeyView = self.saveButton;
    self.saveButton.nextKeyView = close;
    close.nextKeyView = browserCheck;
    browserCheck.nextKeyView = self.start;
    self.start.nextKeyView = self.group;
    [self refresh];
    if (argumentValue(@"--settings")) [self loadSettings:argumentValue(@"--settings")];
    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    NSUInteger errorIndex = [arguments indexOfObject:@"--startup-error"];
    if (errorIndex != NSNotFound && errorIndex + 1 < arguments.count) {
        self.status.stringValue = arguments[errorIndex + 1];
        self.status.textColor = NSColor.systemRedColor;
    }
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.group];
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp runModalForWindow:self.window];
    [self.window orderOut:nil];
}
- (void)refresh {
    NSString *message = @"";
    BOOL error = NO;
    NSString *group = normalizedGroup(self.group.stringValue);
    if (self.settingsError) {
        message = self.settingsError;
        error = YES;
    } else if (!group.length) {
        message = @"Вставьте ссылку на соревнование";
    } else if (!validGroup(group)) {
        message = @"Нужна ссылка /group/…/contest/…";
        error = YES;
    } else if (!self.loadedSettings && !validCode(self.code.stringValue)) {
        message = self.codeRestoreFailed ? @"Сохранённый код недоступен. Введите его снова" : @"Код: 4–32 латинских букв или цифр";
        error = YES;
    } else if (!profileWithHash(self.loadedSettings ? self.loadedSettings[@"quitPasswordHash"] : hashCode(self.code.stringValue), group) || ![NSFileManager.defaultManager isExecutableFileAtPath:
        [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/contest-hub-server"]]) {
        message = @"Приложение повреждено. Установите Roundlane заново";
        error = YES;
    } else {
        message = self.checking ? @"Проверка без блокировки компьютера" : self.loadedSettings ? @"Настройки загружены. Код выхода у организатора" : @"Готово к старту";
    }
    self.status.stringValue = message;
    self.status.textColor = error ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    self.clipboardButton.enabled = !self.loadedSettings && validCode(self.code.stringValue);
    self.generateButton.enabled = !self.loadedSettings;
    self.saveButton.enabled = !self.loadedSettings && !self.settingsError && validGroup(group) && validCode(self.code.stringValue);
    self.start.enabled = !self.inspectionOnly && !error && group.length > 0;
    BOOL organizerTools = [NSProcessInfo.processInfo.arguments containsObject:@"--organizer-tools"] && !self.loadedSettings;
    self.browserCheckButton.hidden = !organizerTools;
    self.browserCheckButton.enabled = organizerTools && validGroup(group);
    self.closeButton.nextKeyView = organizerTools ? self.browserCheckButton : self.start;
}
- (void)controlTextDidChange:(NSNotification *)notification { [self refresh]; }
- (void)browserCheck:(id)sender {
    if (self.browserCheckButton.hidden || !self.browserCheckButton.enabled || self.loadedSettings) return;
    if (!validGroup(normalizedGroup(self.group.stringValue))) { [self refresh]; return; }
    NSTask *task = [NSTask new]; task.executableURL = NSBundle.mainBundle.executableURL;
    task.arguments = @[@"--browser-check", @"--contest-url", normalizedGroup(self.group.stringValue)];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) self.status.stringValue = @"Не удалось открыть проверку сайтов";
}
- (void)generateCode:(id)sender {
    if (self.loadedSettings) return;
    NSString *previous = self.code.stringValue;
    do { self.code.stringValue = randomCode(); }
    while ([self.code.stringValue isEqual:previous]);
    [self refresh];
}
- (void)copyCode:(id)sender {
    if (self.loadedSettings || !validCode(self.code.stringValue)) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:self.code.stringValue forType:NSPasteboardTypeString];
    self.status.stringValue = @"Код скопирован";
}
- (void)loadSettings:(NSString *)path {
    NSString *message = nil;
    NSDictionary *settings = readCompetition(path, &message);
    if (!settings) { self.settingsError = message; [self refresh]; return; }
    self.loadedSettings = settings;
    self.settingsError = nil;
    self.group.stringValue = settings[@"groupURL"];
    self.group.enabled = NO;
    self.code.stringValue = @"У организатора";
    self.code.font = [NSFont systemFontOfSize:14];
    self.code.enabled = NO;
    [self refresh];
}
- (void)openSettings:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.title = @"Открыть настройки соревнования";
    panel.allowedFileTypes = @[@"roundlane"];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    if ([panel runModal] == NSModalResponseOK) [self loadSettings:panel.URL.path];
}
- (void)saveSettings:(id)sender {
    if (self.loadedSettings || self.settingsError || !validCode(self.code.stringValue)) return;
    if (self.code.stringValue.length < 12) {
        NSAlert *warning = [NSAlert new]; warning.messageText = @"Короткий код можно подобрать по файлу";
        warning.informativeText = @"В файле хранится SHA-256 кода. Для распространения настроек лучше случайный пароль из 12 символов. Сохраните пароль отдельно у организаторов.";
        [warning addButtonWithTitle:@"Отмена"]; [warning addButtonWithTitle:@"Сохранить всё равно"];
        if ([warning runModal] != NSAlertSecondButtonReturn) return;
    }
    NSDictionary *settings = competitionSettings(@{@"format":@"roundlane-competition", @"version":@1,
        @"groupURL":normalizedGroup(self.group.stringValue), @"quitPasswordHash":hashCode(self.code.stringValue)});
    if (!settings) { [self refresh]; return; }
    NSSavePanel *panel = NSSavePanel.savePanel;
    panel.title = @"Сохранить настройки соревнования";
    panel.allowedFileTypes = @[@"roundlane"];
    panel.nameFieldStringValue = @"competition.roundlane";
    if ([panel runModal] != NSModalResponseOK) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:settings options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    NSError *error = nil;
    if (![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
        self.status.stringValue = @"Не удалось сохранить настройки. Выберите другую папку";
        return;
    }
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:panel.URL.path error:nil];
    if (![self rememberCode]) return;
    self.status.stringValue = @"Настройки и код сохранены";
}
- (void)start:(id)sender {
    NSString *group = normalizedGroup(self.group.stringValue);
    if (!validGroup(group) || self.settingsError || (!self.loadedSettings && !validCode(self.code.stringValue)) || self.inspectionOnly) { [self refresh]; return; }
    self.group.stringValue = group;
    NSAlert *confirm = [NSAlert new];
    confirm.messageText = self.checking ? @"Проверить запуск?" : @"Начать соревнование?";
    NSString *codeDescription = self.loadedSettings ? @"Код выхода у организатора" : [@"Код выхода: " stringByAppendingString:self.code.stringValue];
    confirm.informativeText = [NSString stringWithFormat:@"%@\n\n%@\n%@", group, codeDescription,
        self.checking ? @"Без блокировки компьютера" : @"Выход: Cmd+Q → код. Рабочий стол будет заблокирован."];
    [confirm addButtonWithTitle:self.checking ? @"Проверить" : @"Начать соревнование"];
    [confirm addButtonWithTitle:@"Назад"];
    confirm.buttons.firstObject.keyEquivalent = @"";
    confirm.buttons.lastObject.keyEquivalent = @"\033";
    if ([confirm runModal] != NSAlertFirstButtonReturn) return;
    if (![self rememberCode]) return;
    [NSUserDefaults.standardUserDefaults setObject:group forKey:@"lastGroupURL"];
    self.result = @{@"group":group, @"quitPasswordHash":self.loadedSettings ? self.loadedSettings[@"quitPasswordHash"] : hashCode(self.code.stringValue)};
    [NSApp stopModal];
}
- (BOOL)rememberCode {
    if(self.loadedSettings || codeDiagnosticsOnly() || !validCode(self.code.stringValue))return YES;
    NSString *service=codeService();OSStatus status=service?writeCode(service,self.code.stringValue):errSecParam;
    if(status!=errSecSuccess){self.status.stringValue=@"Не удалось запомнить код. Связка ключей недоступна";self.status.textColor=NSColor.systemRedColor;return NO;}
    if(!argumentValue(@"--code-store-test-scope") && validGroup(normalizedGroup(self.group.stringValue)))[NSUserDefaults.standardUserDefaults setObject:normalizedGroup(self.group.stringValue) forKey:@"lastGroupURL"];
    return YES;
}
- (void)close:(id)sender {
    if (![self rememberCode]) { NSAlert *alert=[NSAlert new];alert.messageText=@"Код не сохранён";alert.informativeText=@"После следующего запуска код нужно будет ввести снова. Сохраните его отдельно.";[alert addButtonWithTitle:@"Закрыть"];[alert runModal]; }
    [NSApp stopModal];
}
- (BOOL)windowShouldClose:(NSWindow *)sender { [self close:nil]; return NO; }
@end

@implementation RoundlaneBootstrap

 + (int)codeStoreCheck {
    NSString *service=[@"local.roundlane.organizer.exit-code.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    OSStatus status=errSecParam;BOOL absent=readCode(service,&status)==nil && status==errSecItemNotFound;
    BOOL stored=writeCode(service,@"7391")==errSecSuccess;
    BOOL restored=[readCode(service,&status) isEqual:@"7391"] && status==errSecSuccess;
    BOOL changed=writeCode(service,@"7392")==errSecSuccess && [readCode(service,&status) isEqual:@"7392"];
    BOOL invalid=writeCode(service,@"x")==errSecParam;
    OSStatus deleted=SecItemDelete((__bridge CFDictionaryRef)codeQuery(service));
    BOOL ok=absent && stored && restored && changed && invalid && deleted==errSecSuccess;
    printf("{\"passed\":%s,\"checks\":6,\"keychain\":true,\"exam_started\":false}\n",ok?"true":"false");return ok?0:1;
}
+ (int)codeStoreFixture {
    NSString *service=codeService();if(!service || ![NSProcessInfo.processInfo.arguments containsObject:@"--code-store-test-scope"])return 2;
    OSStatus status=writeCode(service,@"7391");printf("{\"written\":%s,\"test_only\":true}\n",status==errSecSuccess?"true":"false");return status==errSecSuccess?0:1;
}
+ (int)codeStoreFixtureDelete {
    NSString *service=codeService();if(!service || ![NSProcessInfo.processInfo.arguments containsObject:@"--code-store-test-scope"])return 2;
    OSStatus status=SecItemDelete((__bridge CFDictionaryRef)codeQuery(service));return status==errSecSuccess || status==errSecItemNotFound?0:1;
}

+ (int)checkBrowser {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    RoundlaneBrowserCheck *check = [RoundlaneBrowserCheck new];
    NSApp.delegate=check;
    [NSApp finishLaunching];
    [check show];
    [NSApp run];
    return 0;
}

+ (int)checkSettings:(NSString *)path {
    NSString *error = nil;
    NSDictionary *input = readCompetition(path, &error);
    NSDictionary *settings = input ? profileWithHash(input[@"quitPasswordHash"], input[@"groupURL"]) : nil;
    BOOL ok = settings && [settings[@"hashedQuitPassword"] isEqual:input[@"quitPasswordHash"]]
        && [settings[@"allowQuit"] boolValue] && [settings[@"showQuitButton"] boolValue];
    NSMutableDictionary *result = [@{@"settings_check":ok ? @"passed" : @"failed", @"profile_hash_matches":@(ok), @"exam_started":@NO} mutableCopy];
    if (ok) { result[@"groupURL"] = input[@"groupURL"]; result[@"rules"] = settings[@"URLFilterRules"]; result[@"contest_only"] = @YES; result[@"participant_direct_start"] = @([input[@"format"] isEqual:@"roundlane-participant"]); }
    else result[@"error"] = error ?: @"Не удалось подготовить профиль SEB";
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(json.bytes, 1, json.length, stdout);
    fputs("\n", stdout);
    return ok ? 0 : 1;
}

+ (int)selfTest {
    NSDictionary *settings = profile(@"1234");
    BOOL ok = settings && validGroup(testContest)
        && !validGroup(@"https://codeforces.com.evil.test/group/test")
        && !validGroup(@"https://user@codeforces.com/group/test")
        && !validGroup(@"https://codeforces.com:443/group/test")
        && !validCode(@"123") && !validCode(@"пароль") && !validCode(@"1234\n")
        && [settings[@"hashedQuitPassword"] isEqual:@"03AC674216F3E15C761EE1A5E255F067953623C8B388B4459E13F978D7C846F4"]
        && [settings[@"lockdownModePolicy"] integerValue] == 1
        && [settings[@"allowQuit"] boolValue] && [settings[@"showQuitButton"] boolValue]
        && [settings[@"URLFilterEnable"] boolValue] && [settings[@"URLFilterEnableContentFilter"] boolValue]
        && ![settings[@"allowPreferencesWindow"] boolValue]
        && ![settings[@"allowSwitchToApplications"] boolValue]
        && [NSFileManager.defaultManager isExecutableFileAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Helpers/contest-hub-server"]];
    NSMutableDictionary *cases = [@{
        testContest:@YES,
        [testContest stringByAppendingString:@"/problem/A"]:@YES,
        [testContest stringByAppendingString:@"/submit"]:@YES,
        [testContest stringByAppendingString:@"/my"]:@YES,
        [testContest stringByAppendingString:@"/standings/groupmates/true"]:@YES,
        @"https://roundlane723396.contest.codeforces.com/enter?back=%2Fgroup%2Ftqy1SBMbAa":@YES,
        @"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contests":@YES,
        @"https://cpp.sh/":@YES,
        @"https://codeforces.com/":@NO,
        @"https://codeforces.com/problemset":@NO,
        @"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contest/723397":@NO,
        @"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contest/7233960":@NO,
        @"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/blog":@NO,
        @"https://roundlane723396.contest.codeforces.com/profile/user1":@NO,
        @"https://other.contest.codeforces.com/":@NO,
        @"https://google.com/":@NO,
        @"https://chatgpt.com/":@NO
    } mutableCopy];
    NSString *serviceBase = @"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/data/";
    for (NSString *endpoint in @[@"customtest",@"submitSource",@"judgeProtocol",@"submissionVerdict",@"standings",@"contests",@"newProblemQuestion",@"changeProblemQuestionOrAnnouncementDataPage"]) {
        cases[[serviceBase stringByAppendingString:endpoint]] = @YES;
        cases[[[serviceBase stringByAppendingString:endpoint] stringByAppendingString:@"-extra"]] = @NO;
    }
    cases[@"wss://roundlane723396.contest.codeforces.com/ws/channel?_=1"] = @YES;
    cases[@"https://roundlane723396.contest.codeforces.com/ev/channel?_=1"] = @YES;
    cases[@"https://roundlane723396.contest.codeforces.com/lp/channel?_=1"] = @YES;
    cases[@"wss://other.contest.codeforces.com/ws/channel"] = @NO;
    cases[[serviceBase stringByAppendingString:@"changeParticipantType"]] = @NO;
    cases[[serviceBase stringByAppendingString:@"answerProblemQuestion"]] = @NO;
    for (NSString *url in cases) {
        BOOL allowed = NO;
        for (NSDictionary *rule in settings[@"URLFilterRules"]) {
            NSError *regexError = nil;
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:rule[@"expression"] options:NSRegularExpressionCaseInsensitive error:&regexError];
            if (regexError) ok = NO;
            if ([regex firstMatchInString:url options:0 range:NSMakeRange(0,url.length)]) allowed = YES;
        }
        if (allowed != [cases[url] boolValue]) ok = NO;
    }
    ok = ok && !validGroup(@"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contests")
        && !validGroup(@"https://roundlane723396.contest.codeforces.com/group/tqy1SBMbAa/contest/%37%32%33%33%39%36");
    NSData *result = [NSJSONSerialization dataWithJSONObject:@{@"self_test":ok ? @"passed" : @"failed", @"contest_policy_cases":@(cases.count), @"native_seb_runtime":@YES, @"lockdown_mode":@"classic", @"apple_aac_required":@NO, @"exam_started":@NO} options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(result.bytes, 1, result.length, stdout);
    fputs("\n", stdout);
    return ok ? 0 : 1;
}

// The organizer runs in a short-lived copy of this same executable. It never loads
// the SEB nib/delegate. The parent can then use the untouched NSApplicationMain
// lifecycle (including SEBApplication) only after manual confirmation.
+ (NSDictionary *)organizer {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp finishLaunching];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--require-organizer-auth"]) {
        NSDictionary *bundle=readCompetition([[resources() URLByAppendingPathComponent:@"competition.roundlane"] path],nil);
        if(![bundle[@"format"] isEqual:@"roundlane-participant"])return nil;
        for(;;){
            NSAlert *gate=[NSAlert new];gate.messageText=@"Режим организатора";gate.informativeText=@"Введите код организатора для этого приложения";
            [gate addButtonWithTitle:@"Открыть"];[gate addButtonWithTitle:@"Отмена"];
            NSSecureTextField *code=[[NSSecureTextField alloc]initWithFrame:NSMakeRect(0,0,320,28)];code.accessibilityLabel=@"Код организатора";gate.accessoryView=code;
            [NSApp activateIgnoringOtherApps:YES];[gate.window makeFirstResponder:code];
            if([gate runModal]!=NSAlertFirstButtonReturn)return nil;
            BOOL accepted=validCode(code.stringValue) && [hashCode(code.stringValue) isEqual:bundle[@"quitPasswordHash"]];code.stringValue=@"";
            if(accepted)break;
            NSAlert *error=[NSAlert new];error.messageText=@"Неверный код";[error addButtonWithTitle:@"Повторить"];[error runModal];
        }
    }
    RoundlaneOrganizer *organizer = [RoundlaneOrganizer new];
    organizer.checking = [NSProcessInfo.processInfo.arguments containsObject:@"--preflight-check"];
    organizer.inspectionOnly = [NSProcessInfo.processInfo.arguments containsObject:@"--preflight-only"];
    [organizer show];
    return organizer.result;
}

static NSString *participantPath(void) {
    NSString *base=[NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,NSUserDomainMask,YES) firstObject];
    return [[base stringByAppendingPathComponent:@"Roundlane"] stringByAppendingPathComponent:@"participant.roundlane"];
}
static void rememberParticipant(NSDictionary *input) {
    NSString *path=participantPath();
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSData *data=[NSJSONSerialization dataWithJSONObject:input options:NSJSONWritingSortedKeys error:nil];
    if([data writeToFile:path options:NSDataWritingAtomic error:nil]) [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
}
static void participantFailure(NSString *message) {
    preparationFailed=YES;
    fprintf(stderr,"Roundlane participant launch failed: %s\n",message.UTF8String);
    if([NSProcessInfo.processInfo.arguments containsObject:@"--preflight-check"] || [NSProcessInfo.processInfo.arguments containsObject:@"--participant-default-check"]) {
        NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"preflight_check":@"failed",@"error":message,@"exam_started":@NO} options:0 error:nil];
        fwrite(data.bytes,1,data.length,stdout);fputs("\n",stdout);return;
    }
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSAlert *alert=[NSAlert new];alert.messageText=@"Не удалось открыть соревнование";alert.informativeText=message;[alert addButtonWithTitle:@"Закрыть"];[alert runModal];
}

+ (BOOL)prepare {
    preparationFailed=NO;
    BOOL checking = [NSProcessInfo.processInfo.arguments containsObject:@"--preflight-check"] || [NSProcessInfo.processInfo.arguments containsObject:@"--participant-default-check"];
    NSString *startupError = nil;
    if (![RoundlaneMacGuard verify:&startupError]) {
        fprintf(stderr, "Roundlane startup integrity failure: %s\n", startupError.UTF8String);
        startupError = @"Не удалось проверить защиту приложения. Переустановите Roundlane";
    }
    NSString *settingsPath=argumentValue(@"--settings");
    if(!settingsPath && [NSProcessInfo.processInfo.arguments containsObject:@"--participant-file"])settingsPath=NSProcessInfo.processInfo.environment[@"ROUNDLANE_PARTICIPANT_FILE"]?:@"";
    BOOL diagnostic=[NSProcessInfo.processInfo.arguments containsObject:@"--preflight-only"] || checking;
    if(!settingsPath && (!diagnostic || [NSProcessInfo.processInfo.arguments containsObject:@"--participant-default-check"]) && ![NSProcessInfo.processInfo.arguments containsObject:@"--organizer-tools"]) {
        NSString *bundled=[[resources() URLByAppendingPathComponent:@"competition.roundlane"] path];
        if([NSFileManager.defaultManager fileExistsAtPath:bundled])settingsPath=bundled;
    }
    if(!settingsPath && !diagnostic && ![NSProcessInfo.processInfo.arguments containsObject:@"--organizer-tools"] && [NSFileManager.defaultManager fileExistsAtPath:participantPath()])settingsPath=participantPath();
    NSString *settingsMessage=nil;
    NSDictionary *participant=settingsPath?readCompetition(settingsPath,&settingsMessage):nil;
    if(settingsPath && !participant){participantFailure(settingsMessage?:@"Неверный файл соревнования");return NO;}
    BOOL direct=[participant[@"format"] isEqual:@"roundlane-participant"] && ![NSProcessInfo.processInfo.arguments containsObject:@"--organizer-tools"];
    if(direct && startupError){participantFailure(startupError);return NO;}
    if(direct && [NSProcessInfo.processInfo.arguments containsObject:@"--preflight-only"]){participantFailure(@"Для проверки файла используйте --check-settings или --preflight-check");return NO;}
    for (;;) {
        if(direct && startupError){participantFailure(startupError);return NO;}
        NSDictionary *input = nil;
        if(direct) input=@{@"group":participant[@"groupURL"],@"quitPasswordHash":participant[@"quitPasswordHash"]};
        else {
        NSTask *organizer = [NSTask new];
        organizer.executableURL = NSBundle.mainBundle.executableURL;
        NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"--organizer-ui"];
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--organizer-tools"]) [arguments addObject:@"--organizer-tools"];
        NSDictionary *boundDefaults=readCompetition([[resources() URLByAppendingPathComponent:@"competition.roundlane"] path],nil);
        if(!checking && [boundDefaults[@"format"] isEqual:@"roundlane-participant"]) [arguments addObject:@"--require-organizer-auth"];
        if (checking) [arguments addObject:@"--preflight-check"];
        if ([NSProcessInfo.processInfo.arguments containsObject:@"--preflight-only"]) [arguments addObject:@"--preflight-only"];
        if (argumentValue(@"--code-store-test-scope")) [arguments addObjectsFromArray:@[@"--code-store-test-scope", argumentValue(@"--code-store-test-scope")]];
        if (argumentValue(@"--settings")) [arguments addObjectsFromArray:@[@"--settings", argumentValue(@"--settings")]];
        if (startupError) [arguments addObjectsFromArray:@[@"--startup-error", startupError]];
        organizer.arguments = arguments;
        NSPipe *resultPipe = [NSPipe pipe];
        organizer.standardOutput = resultPipe;
        NSError *launchError = nil;
        if (![organizer launchAndReturnError:&launchError]) return NO;
        NSData *resultData = [resultPipe.fileHandleForReading readDataToEndOfFile];
        [organizer waitUntilExit];
        input = [NSJSONSerialization JSONObjectWithData:resultData options:0 error:nil];
        if (organizer.terminationStatus != 0 || ![input isKindOfClass:NSDictionary.class]) return NO;
        }
        NSString *integrityReason = nil;
        if (![RoundlaneMacGuard verify:&integrityReason]) {
            fprintf(stderr, "Roundlane pre-exam integrity failure: %s\n", integrityReason.UTF8String);
            startupError = @"Не удалось проверить защиту приложения. Переустановите Roundlane";
            continue;
        }
        NSString *groupURL = input[@"group"];
        NSString *quitHash = input[@"quitPasswordHash"];
        if (![groupURL isKindOfClass:NSString.class] || !validGroup(groupURL) || !validHash(quitHash)) return NO;
        NSMutableDictionary *settings = profileWithHash(quitHash, groupURL);
        if (!settings) return NO;
        sessionQuitHash = [quitHash copy];
        sessionContestURL = [groupURL copy];
        sessionDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"Roundlane-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSError *error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:sessionDirectory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:&error]) {participantFailure(@"Не удалось создать временные файлы. Проверьте свободное место и права доступа");return NO;}
        sessionProfile = [sessionDirectory stringByAppendingPathComponent:@"session.seb"];
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:settings format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if (![data writeToFile:sessionProfile options:NSDataWritingAtomic error:&error]) { [self cleanup];participantFailure(@"Не удалось сохранить настройки. Проверьте свободное место и права доступа");return NO; }
        [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:sessionProfile error:nil];
        hubTask = [NSTask new];
        hubTask.executableURL = [NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Contents/Helpers/contest-hub-server"];
        NSString *token = NSUUID.UUID.UUIDString;
        hubTask.arguments = @[[resources() URLByAppendingPathComponent:@"hub"].path, token, groupURL, [resources() URLByAppendingPathComponent:@"starter.cpp"].path, sessionDirectory];
        NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
        environment[@"ROUNDLANE_PARENT_PID"] = [NSString stringWithFormat:@"%d", getpid()];
        hubTask.environment = environment;
        if (![hubTask launchAndReturnError:&error]) {
            [self cleanup];
            startupError = @"Не удалось подготовить стартовую страницу. Попробуйте ещё раз";
            continue;
        }
        // Verify this helper's token; another listener on the same port must not pass readiness.
        NSURL *health = [NSURL URLWithString:@"http://127.0.0.1:18765/health"];
        for (NSUInteger attempt = 0; attempt < 20; attempt++) {
            NSURLRequest *request = [NSURLRequest requestWithURL:health cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:0.3];
            NSHTTPURLResponse *response = nil;
            NSData *body = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
            NSString *received = body ? [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding] : nil;
            if (response.statusCode == 200 && [received isEqual:token]) {
                if (!checking) {if(direct)rememberParticipant(participant);return YES;}
                // Exercise the production input/profile/helper path, but stop before
                // loading SEB or changing any presentation/system settings.
                NSDictionary *result = @{@"preflight_check":@"passed", @"lockdown_mode":@"classic",
                    @"profile_created":@YES, @"helper_token_verified":@YES, @"organizer_panel_shown":@(!direct), @"participant_signature_verified":@(direct),
                    @"allow_quit":[settings objectForKey:@"allowQuit"],
                    @"show_quit_button":[settings objectForKey:@"showQuitButton"],
                    @"quit_hash_matches":@([settings[@"hashedQuitPassword"] isEqual:quitHash.uppercaseString]),
                    @"apple_aac_required":@NO, @"exam_started":@NO,
                    @"temporary_directory":sessionDirectory};
                NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
                fwrite(json.bytes, 1, json.length, stdout);
                fputs("\n", stdout);
                [self cleanup];
                return NO;
            }
            if (!hubTask.running) break;
            [NSThread sleepForTimeInterval:0.1];
        }
        [self cleanup];
        // Stay outside SEB on failure. Use the isolated organizer UI again;
        // never fall back to a cached exam profile.
        startupError = @"Стартовая страница занята. Завершите другую сессию и повторите старт";
    }
}

+ (void)configureExamMenu {
    NSMenu *main = NSApp.mainMenu;
    for (NSMenuItem *top in main.itemArray.copy) {
        if (top.submenu == NSApp.helpMenu) { [main removeItem:top]; continue; }
        for (NSMenuItem *item in top.submenu.itemArray.copy) {
            if (item.action == NSSelectorFromString(@"showAbout:") || item.action == NSSelectorFromString(@"showHelp:") || item.action == NSSelectorFromString(@"openPreferences:")) {
                [top.submenu removeItem:item];
            } else if (item.action == NSSelectorFromString(@"requestedQuit:")) {
                item.title = @"Завершить соревнование";
            }
        }
        if ([top.title isEqual:@"SEB"]) { top.title = @"Roundlane"; top.submenu.title = @"Roundlane"; }
        // Do not leave orphan separators after removing About and Settings.
        for (NSMenuItem *item in top.submenu.itemArray.copy) {
            if (item.isSeparatorItem && (top.submenu.itemArray.firstObject == item || top.submenu.itemArray.lastObject == item))
                [top.submenu removeItem:item];
        }
    }
}

+ (NSString *)currentContestURL { return sessionContestURL; }
+ (BOOL)preparationFailed { return preparationFailed; }
+ (NSString *)profilePath { return sessionProfile; }
+ (NSString *)organizerQuitHash { return sessionQuitHash; }

+ (void)cleanup {
    if (hubTask.running) [hubTask terminate];
    hubTask = nil;
    if (sessionDirectory) [NSFileManager.defaultManager removeItemAtPath:sessionDirectory error:nil];
    sessionDirectory = nil;
    sessionProfile = nil;
    sessionQuitHash = nil;
}
@end
