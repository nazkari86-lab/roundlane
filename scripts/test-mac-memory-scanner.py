#!/usr/bin/env python3
"""Real own-page mutation in an isolated fixture using production scanner code.
Fixture deliberately allows unsigned executable memory; production app does not.
No app/kiosk is started. Release-signature hook is fake and reported as such.
"""
import json
from pathlib import Path
import plistlib
import subprocess

kit = Path(__file__).resolve().parent.parent
out = kit / 'setup/mac-hardened-tests/memory-fixture'
out.mkdir(parents=True, exist_ok=True)
production = (kit / 'upstream/seb-mac/OtherSources/RoundlaneMacGuard.m').read_text()
shared = production[production.index('static NSMutableDictionary'):production.index('@implementation RoundlaneMacGuard')]
headers = '''#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach-o/dyld.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <libkern/OSByteOrder.h>
#include <sys/sysctl.h>
#include <sys/proc.h>
#include <unistd.h>
@interface RoundlaneReleaseBinding : NSObject
+ (NSString *)imageViolation:(NSData *)bytes path:(NSString *)path;
@end
@implementation RoundlaneReleaseBinding
+ (NSString *)imageViolation:(NSData *)bytes path:(NSString *)path { return nil; }
@end
'''
main = r'''
#if !defined(__aarch64__)
#error This controlled page fixture currently covers arm64 only.
#endif
__attribute__((naked, noinline, aligned(16384), section("__TEXT,__probe,regular,pure_instructions"), used)) static int controlledMarker(int value) {
    __asm__("add w0, w0, #17\nret\n.space 16384-8");
}
static BOOL scan(NSString *path, NSString **reason) {
    NSUInteger sections = 0;
    return imageMatches(path, _dyld_get_image_header(0), _dyld_get_image_vmaddr_slide(0), &sections, reason);
}
int main(void) { @autoreleasepool {
    NSString *path = [NSString stringWithUTF8String:_dyld_get_image_name(0)].stringByResolvingSymlinksInPath;
    imageBaselines = [NSMutableDictionary new];
    NSString *reason = nil;
    BOOL healthy = scan(path, &reason); fprintf(stderr,"healthy=%d\n",healthy);
    mach_vm_address_t target = (mach_vm_address_t)(uintptr_t)&controlledMarker;
    vm_size_t pageSize = 0; host_page_size(mach_host_self(), &pageSize);
    mach_vm_address_t page = target & ~((mach_vm_address_t)pageSize - 1);
    uint8_t saved = *(const uint8_t *)(uintptr_t)target;
    kern_return_t writable = mach_vm_protect(mach_task_self(), page, pageSize, NO, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    BOOL rightsRejected = NO, mutationRejected = NO, restored = NO;
    NSString *rightsReason = nil, *mutationReason = nil;
    kern_return_t rx = -1, restoration = -1;
    fprintf(stderr,"writable=%d\n",writable);
    if (writable == KERN_SUCCESS) {
        rightsRejected = !scan(path, &rightsReason) && [rightsReason containsString:@"Unsafe executable page permissions"];
        fprintf(stderr,"rights=%d\n",rightsRejected);
        *(uint8_t *)(uintptr_t)target = saved ^ 1; fprintf(stderr,"mutation-written\n");
        rx = mach_vm_protect(mach_task_self(), page, pageSize, NO, VM_PROT_READ | VM_PROT_EXECUTE);
        fprintf(stderr,"rx=%d\n",rx);
        if (rx == KERN_SUCCESS) mutationRejected = !scan(path, &mutationReason) && [mutationReason containsString:@"Modified executable section"];
        fprintf(stderr,"mutation-rejected=%d\n",mutationRejected);
        restoration = mach_vm_protect(mach_task_self(), page, pageSize, NO, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
        if (restoration == KERN_SUCCESS) {
            *(uint8_t *)(uintptr_t)target = saved;
            restoration = mach_vm_protect(mach_task_self(), page, pageSize, NO, VM_PROT_READ | VM_PROT_EXECUTE);
            if (restoration == KERN_SUCCESS) restored = scan(path, &reason);
        }
    }
    BOOL passed = healthy && rightsRejected && mutationRejected && restored;
    NSDictionary *report = @{@"passed":@(passed), @"healthy":@(healthy), @"unsafe_rights_rejected":@(rightsRejected), @"instruction_mutation_rejected":@(mutationRejected), @"restored":@(restored), @"write_status":@(writable), @"rx_status":@(rx), @"restore_status":@(restoration), @"rights_reason":rightsReason ?: NSNull.null, @"mutation_reason":mutationReason ?: NSNull.null, @"last_reason":reason ?: NSNull.null, @"fake_release_hook":@YES, @"weakened_test_entitlements":@YES, @"production_hardened_app_test":@NO, @"exam_started":@NO, @"kiosk_started":@NO};
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(json.bytes,1,json.length,stdout); fputc('\n',stdout);
    return passed ? 0 : 1;
} }
'''
source = out / 'memory-fixture.m'
source.write_text(headers + shared + main)
app = out / 'MemoryFixture.app'
exe = app / 'Contents/MacOS/MemoryFixture'
exe.parent.mkdir(parents=True, exist_ok=True)
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleExecutable='MemoryFixture', CFBundleIdentifier='local.roundlane.scanner-test', CFBundlePackageType='APPL')))
clang = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang'
sdk = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
subprocess.run([clang,'-fobjc-arc','-O0','-isysroot',sdk,'-mmacosx-version-min=12.1','-framework','Foundation','-framework','Security',str(source),'-o',str(exe)],check=True)
entitlements = out / 'test-only-entitlements.plist'
entitlements.write_bytes(plistlib.dumps({'com.apple.security.cs.allow-unsigned-executable-memory': True}))
subprocess.run(['codesign','--force','--options','runtime','--entitlements',str(entitlements),'--sign','-',str(app)],check=True)
run = subprocess.run([str(exe)],capture_output=True,text=True,timeout=15)
(out / 'stderr.txt').write_text(run.stderr)
(out / 'stdout.txt').write_text(run.stdout)
if not run.stdout:
    raise RuntimeError(f"Fixture terminated without JSON: exit {run.returncode}; stderr {run.stderr!r}")
report = json.loads(run.stdout)
(out.parent / 'memory-scanner-results.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
assert run.returncode == 0 and report['passed'] is True
