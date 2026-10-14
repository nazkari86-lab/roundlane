//
//  main.m
//  SEB
//
//  Created by Daniel R. Schneider on 29.04.10.
//  Copyright (c) 2010-2026 Daniel R. Schneider, ETH Zurich, IT Services,
//  based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen
//  Project concept: Thomas Piendl, Daniel R. Schneider, Damian Buechel,
//  Dirk Bauer, Kai Reuter, Tobias Halbherr, Karsten Burger, Marco Lehre,
//  Brigitte Schmucki, Oliver Rahs. French localization: Nicolas Dunand
//
//  ``The contents of this file are subject to the Mozilla Public License
//  Version 2.0 (the "License"); you may not use this file except in
//  compliance with the License. You may obtain a copy of the License at
//  http://www.mozilla.org/MPL/
//
//  Software distributed under the License is distributed on an "AS IS"
//  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
//  License for the specific language governing rights and limitations
//  under the License.
//
//  The Original Code is Safe Exam Browser for Mac OS X.
//
//  The Initial Developer of the Original Code is Daniel R. Schneider.
//  Portions created by Daniel R. Schneider are Copyright
//  (c) 2010-2026 Daniel R. Schneider, ETH Zurich, IT Services,
//  based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen. All Rights Reserved.
//
//  Contributor(s): ______________________________________.
//


#import <Cocoa/Cocoa.h>
#import "NSWindow+SEBWindow.h"
#import "WebKit+WebKitExtensions.h"
#import "RoundlaneBootstrap.h"
#import "RoundlaneTabs.h"
#import "RoundlaneMacGuard.h"
#import "RoundlaneIntegritySession.h"
#import "NSUserDefaults+SEBEncryptedUserDefaults.h"
#import "SEBBrowserWindowDocument.h"
#import "SEBBrowserWindow.h"
#import "SEBOSXBrowserController.h"
#import "SEBAbstractWebView.h"

@interface SEBOSXBrowserController (RoundlaneRuntimeCheck)
- (SEBBrowserWindowDocument *)createBrowserWindowDocumentWithError:(NSError **)error;
@end

int main(int argc, char *argv[])
{
    @autoreleasepool {

    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    NSSet *switches=[NSSet setWithArray:@[@"--self-test",@"--tabs-check",@"--tabs-preview",@"--roundlane-integrity-check",@"--roundlane-session-check",@"--runtime-settings-check",@"--runtime-webview-check",@"--browser-check",@"--code-store-check",@"--code-store-fixture",@"--code-store-fixture-delete",@"--organizer-ui",@"--organizer-tools",@"--require-organizer-auth",@"--participant-file",@"--participant-default-check",@"--preflight-check",@"--preflight-only"]];
    NSSet *values=[NSSet setWithArray:@[@"--settings",@"--check-settings",@"--roundlane-monitor-check",@"--code-store-test-scope",@"--startup-error",@"--contest-url",@"--browser-check-url"]];
    for(NSUInteger i=1;i<arguments.count;i++){
        NSString *arg=arguments[i];
        if([switches containsObject:arg])continue;
        if([values containsObject:arg]){
            if(i+1>=arguments.count || [arguments[i+1] hasPrefix:@"--"]){fprintf(stderr,"Missing value for %s; exam not started\n",arg.UTF8String);return 64;}
            i++;continue;
        }
        if([arg hasPrefix:@"--"]){fprintf(stderr,"Unknown option %s; exam not started\n",arg.UTF8String);return 64;}
    }
    if ([arguments containsObject:@"--code-store-check"]) return [RoundlaneBootstrap codeStoreCheck];
    if ([arguments containsObject:@"--code-store-fixture"]) return [RoundlaneBootstrap codeStoreFixture];
    if ([arguments containsObject:@"--code-store-fixture-delete"]) return [RoundlaneBootstrap codeStoreFixtureDelete];
    if ([arguments containsObject:@"--tabs-check"]) return [RoundlaneTabs diagnostic];
    if ([arguments containsObject:@"--tabs-preview"]) return [RoundlaneTabs preview];
    if ([arguments containsObject:@"--roundlane-integrity-check"]) return [RoundlaneMacGuard diagnostic];
    if ([arguments containsObject:@"--roundlane-session-check"]) return RoundlaneIntegritySessionDiagnostic();
    NSUInteger monitorIndex = [arguments indexOfObject:@"--roundlane-monitor-check"];
    if (monitorIndex != NSNotFound)
        return monitorIndex + 1 < arguments.count ? RoundlaneIntegrityMonitorDiagnostic(arguments[monitorIndex + 1]) : 2;
    // No main nib, SEBController, window controllers, or kiosk presentation.
    if ([arguments containsObject:@"--runtime-webview-check"]) {
        [NSApplication sharedApplication];
        NSDocumentController *documents = NSDocumentController.sharedDocumentController;
        NSError *error = nil;
        NSDocument *document = [documents makeUntitledDocumentOfType:documents.defaultType error:&error];
        if (![document isKindOfClass:SEBBrowserWindowDocument.class]) {
            fprintf(stderr, "Missing internal browser document registration: %s\n", error.description.UTF8String ?: "no document type");
            return 1;
        }
        // Use the bundled exam profile in memory; don't touch the user's keychain.
        [NSUserDefaults setUserDefaultsPrivate:YES];
        NSDictionary *profile = [NSDictionary dictionaryWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"contest" ofType:@"seb" inDirectory:@"Roundlane"]];
        if (!profile) return 3;
        [NSUserDefaults.standardUserDefaults storeSEBDictionary:profile];
        SEBOSXBrowserController *browser = [SEBOSXBrowserController new];
        SEBBrowserWindowDocument *wiredDocument = [browser createBrowserWindowDocumentWithError:&error];
        if (!wiredDocument || wiredDocument.browserController != browser || wiredDocument.windowControllers.count != 0) return 4;
        SEBBrowserWindow *window = [[SEBBrowserWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES];
        window.browserController = browser;
        [NSUserDefaults.standardUserDefaults setSecureInteger:3 forKey:@"org_safeexambrowser_SEB_browserWindowWebView"];
        SEBAbstractWebView *view = [[SEBAbstractWebView alloc] initNewTabMainWebView:YES withCommonHost:YES configuration:nil overrideSpellCheck:NO delegate:window];
        if (![view.nativeWebView isKindOfClass:WKWebView.class]) return 2;
        NSString *integrityReason = nil;
        if (![RoundlaneMacGuard verify:&integrityReason]) {
            fprintf(stderr, "WebView integrity failure: %s\n", integrityReason.UTF8String);
            return 5;
        }
        fputs("{\"runtime_webview_check\":\"passed\",\"exam_started\":false}\n", stdout);
        return 0;
    }
    // Exercise the settings initialization that precedes awakeFromNib, without
    // loading SEBController, its nib, or any kiosk/system settings.
    if ([arguments containsObject:@"--runtime-settings-check"]) {
        // This diagnostic uses an ephemeral settings store and cryptographic key.
        // Never read, rotate or request access to the user's existing keychain.
        [NSUserDefaults setUserDefaultsPrivate:YES];
        [NSUserDefaults.standardUserDefaults setSEBDefaults];
        NSString *integrityReason = nil;
        if (![RoundlaneMacGuard verify:&integrityReason]) {
            fprintf(stderr, "Settings integrity failure: %s\n", integrityReason.UTF8String);
            return 5;
        }
        fputs("{\"runtime_settings_check\":\"passed\",\"ephemeral_settings\":true,\"exam_started\":false}\n", stdout);
        return 0;
    }
    // This branch must never initialize SEB or change any kiosk/system settings.
    if ([arguments containsObject:@"--browser-check"]) return [RoundlaneBootstrap checkBrowser];
    NSUInteger settingsIndex = [arguments indexOfObject:@"--check-settings"];
    if (settingsIndex != NSNotFound) {
        return settingsIndex + 1 < arguments.count ? [RoundlaneBootstrap checkSettings:arguments[settingsIndex + 1]] : 1;
    }

    if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test"]) {
        return [RoundlaneBootstrap selfTest];
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--organizer-ui"]) {
        NSDictionary *input = [RoundlaneBootstrap organizer];
        if (input) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:input options:0 error:nil];
            fwrite(json.bytes, 1, json.length, stdout);
        }
        return 0;
    }
    if (![RoundlaneBootstrap prepare]) return [RoundlaneBootstrap preparationFailed] ? 1 : 0;

//        NSBundle *webKit = [NSBundle bundleWithIdentifier:@"com.apple.WebKit"];
//        if (webKit.loaded) {
//            [webKit unload];
//        }
//        if (!webKit.loaded) {
//            [webKit load];
//        }

    // Swizzle NSWindow setLevel: Method
    [NSWindow setupChangingWindowLevels];
            [WebView setupOverridePlugins];

    int result = NSApplicationMain(argc,  (const char **) argv);
    [RoundlaneBootstrap cleanup];
    return result;
    }
}
