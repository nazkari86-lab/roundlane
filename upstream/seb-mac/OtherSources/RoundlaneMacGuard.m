// Roundlane additions, MPL-2.0. Exam protection checks this process only.
#import "RoundlaneMacGuard.h"
#import "SafeExamBrowser-Swift.h"
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

static NSMutableDictionary<NSString *, NSData *> *imageBaselines;

static BOOL fail(NSString **reason, NSString *message) {
    if (reason) *reason = message;
    return NO;
}

static BOOL signedBundle(NSString **reason) {
    SecStaticCodeRef code = NULL;
    OSStatus status = SecStaticCodeCreateWithPath((__bridge CFURLRef)NSBundle.mainBundle.bundleURL, kSecCSDefaultFlags, &code);
    if (status == errSecSuccess)
        status = SecStaticCodeCheckValidity(code, kSecCSStrictValidate | kSecCSCheckAllArchitectures, NULL);
    if (code) CFRelease(code);
    return status == errSecSuccess || fail(reason, [NSString stringWithFormat:@"Invalid application signature/resources (%d)", (int)status]);
}

static BOOL processStatus(NSString **reason) {
    SecCodeRef code = NULL;
    CFDictionaryRef information = NULL;
    OSStatus status = SecCodeCopySelf(kSecCSDefaultFlags, &code);
    if (status == errSecSuccess) status = SecCodeCopySigningInformation(code, kSecCSSigningInformation | kSecCSDynamicInformation, &information);
    if (code) CFRelease(code);
    if (status != errSecSuccess || !information) return fail(reason, @"Cannot read process signing status");
    NSNumber *flags = ((__bridge NSDictionary *)information)[(__bridge NSString *)kSecCodeInfoStatus];
    if (![flags isKindOfClass:NSNumber.class]) { CFRelease(information); return fail(reason, @"Cannot read dynamic signing status"); }
    BOOL hardened = [flags isKindOfClass:NSNumber.class] && (flags.unsignedIntValue & kSecCodeSignatureRuntime);
    BOOL debugged = flags.unsignedIntValue & kSecCodeStatusDebugged;
    NSDictionary *entitlements = ((__bridge NSDictionary *)information)[(__bridge NSString *)kSecCodeInfoEntitlementsDict];
    if (entitlements && ![entitlements isKindOfClass:NSDictionary.class]) {
        CFRelease(information); return fail(reason, @"Cannot inspect hardened-runtime entitlements");
    }
    for (NSString *key in @[@"com.apple.security.cs.allow-jit", @"com.apple.security.cs.allow-unsigned-executable-memory", @"com.apple.security.cs.disable-executable-page-protection", @"com.apple.security.cs.disable-library-validation", @"com.apple.security.cs.allow-dyld-environment-variables", @"com.apple.security.get-task-allow"]) {
        if (entitlements[key] && ![entitlements[key] isEqual:@NO]) {
            CFRelease(information); return fail(reason, @"Unsafe hardened-runtime entitlement");
        }
    }
    CFRelease(information);
    if (!hardened) return fail(reason, @"Hardened runtime is not enforced");
    if (debugged) return fail(reason, @"Process has been debugged");
    int query[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc process = {0};
    size_t size = sizeof(process);
    if (sysctl(query, 4, &process, &size, NULL, 0) != 0 || size != sizeof(process))
        return fail(reason, @"Cannot check debugger state");
    if (process.kp_proc.p_flag & P_TRACED) return fail(reason, @"A debugger is attached");
    return YES;
}

static BOOL rangeValid(uint64_t offset, uint64_t length, uint64_t total) {
    return offset <= total && length <= total - offset;
}

// Locate the exact loaded architecture without using a snapshot of its code.
static BOOL slice(NSData *data, cpu_type_t cpu, cpu_subtype_t subtype, uint64_t *offset, uint64_t *length) {
    if (data.length < sizeof(uint32_t)) return NO;
    uint32_t magic;
    memcpy(&magic, data.bytes, sizeof(magic));
    if (magic == MH_MAGIC_64) { *offset = 0; *length = data.length; return YES; }
    if (magic != FAT_CIGAM && magic != FAT_CIGAM_64) return NO;
    if (data.length < sizeof(struct fat_header)) return NO;
    struct fat_header header;
    memcpy(&header, data.bytes, sizeof(header));
    uint32_t count = OSSwapBigToHostInt32(header.nfat_arch);
    BOOL wide = magic == FAT_CIGAM_64;
    size_t entrySize = wide ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
    if (!count || count > 64 || !rangeValid(sizeof(header), (uint64_t)count * entrySize, data.length)) return NO;
    for (uint32_t i = 0; i < count; i++) {
        const uint8_t *entry = (const uint8_t *)data.bytes + sizeof(header) + i * entrySize;
        uint32_t fileCPU, fileSubtype;
        uint64_t start, size;
        if (wide) {
            struct fat_arch_64 arch; memcpy(&arch, entry, sizeof(arch));
            fileCPU = OSSwapBigToHostInt32(arch.cputype); fileSubtype = OSSwapBigToHostInt32(arch.cpusubtype);
            start = OSSwapBigToHostInt64(arch.offset); size = OSSwapBigToHostInt64(arch.size);
        } else {
            struct fat_arch arch; memcpy(&arch, entry, sizeof(arch));
            fileCPU = OSSwapBigToHostInt32(arch.cputype); fileSubtype = OSSwapBigToHostInt32(arch.cpusubtype);
            start = OSSwapBigToHostInt32(arch.offset); size = OSSwapBigToHostInt32(arch.size);
        }
        if (fileCPU == (uint32_t)cpu && fileSubtype == (uint32_t)subtype && rangeValid(start, size, data.length)) {
            *offset = start; *length = size; return YES;
        }
    }
    return NO;
}

static BOOL codePages(mach_vm_address_t address, uint64_t size, NSString **reason) {
    if (size > UINT64_MAX - address) return fail(reason, @"Executable range overflow");
    mach_vm_address_t end = address + size;
    while (address < end) {
        mach_vm_address_t region = address;
        mach_vm_size_t length = 0;
        vm_region_basic_info_data_64_t info = {0};
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        kern_return_t status = mach_vm_region(mach_task_self(), &region, &length, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
        if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
        if (status != KERN_SUCCESS || region > address || !length || length > UINT64_MAX - region || region + length <= address)
            return fail(reason, @"Cannot inspect executable page");
        if ((info.protection & (VM_PROT_READ | VM_PROT_EXECUTE)) != (VM_PROT_READ | VM_PROT_EXECUTE) || (info.protection & VM_PROT_WRITE))
            return fail(reason, @"Unsafe executable page permissions");
        address = MIN(end, region + length);
    }
    return YES;
}

static BOOL imageMatches(NSString *path, const struct mach_header *loaded, intptr_t slideValue, NSUInteger *sections, NSString **reason) {
    NSError *error = nil;
    // Unmapped immutable bytes: later on-disk writes cannot change the baseline.
    NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:[NSURL fileURLWithPath:path] error:&error];
    NSData *data = nil;
    @try {
        data = [file readDataUpToLength:256 * 1024 * 1024 + 1 error:&error];
        [file closeAndReturnError:nil];
    } @catch (NSException *exception) {
        return fail(reason, @"Cannot safely read owned Mach-O image");
    }
    if (!data || data.length > 256 * 1024 * 1024) return fail(reason, @"Cannot read owned Mach-O image");
    NSString *root = [NSBundle.mainBundle.bundlePath.stringByResolvingSymlinksInPath stringByAppendingString:@"/"];
    if (![path hasPrefix:root]) return fail(reason, @"Owned image escaped bundle");
    NSString *releaseViolation = [RoundlaneReleaseBinding imageViolation:data path:[path substringFromIndex:root.length]];
    if (releaseViolation) return fail(reason, releaseViolation);
    NSData *baseline = imageBaselines[path];
    if (baseline && ![baseline isEqualToData:data]) return fail(reason, @"Owned image changed on disk during this process");
    if (baseline) data = baseline;
    if (loaded->magic != MH_MAGIC_64) return fail(reason, @"Unsupported loaded Mach-O format");
    uint64_t base = 0, size = 0;
    if (!slice(data, loaded->cputype, loaded->cpusubtype, &base, &size) || size < sizeof(struct mach_header_64))
        return fail(reason, @"Cannot locate loaded Mach-O architecture");
    const uint8_t *bytes = (const uint8_t *)data.bytes + base;
    struct mach_header_64 header;
    memcpy(&header, bytes, sizeof(header));
    if (header.magic != MH_MAGIC_64 || header.cputype != loaded->cputype || header.cpusubtype != loaded->cpusubtype ||
        !header.ncmds || header.ncmds > 1024 || !rangeValid(sizeof(header), header.sizeofcmds, size))
        return fail(reason, @"Invalid Mach-O command table");
    uint64_t position = sizeof(header), commandsEnd = position + header.sizeofcmds;
    NSUInteger checked = 0;
    for (uint32_t i = 0; i < header.ncmds; i++) {
        if (!rangeValid(position, sizeof(struct load_command), commandsEnd)) return fail(reason, @"Truncated Mach-O command");
        struct load_command command; memcpy(&command, bytes + position, sizeof(command));
        if (command.cmdsize < sizeof(command) || !rangeValid(position, command.cmdsize, commandsEnd)) return fail(reason, @"Invalid Mach-O command size");
        if (command.cmd == LC_SEGMENT_64) {
            if (command.cmdsize < sizeof(struct segment_command_64)) return fail(reason, @"Truncated Mach-O segment");
            struct segment_command_64 segment; memcpy(&segment, bytes + position, sizeof(segment));
            if (segment.vmsize > UINT64_MAX - segment.vmaddr || !rangeValid(segment.fileoff, segment.filesize, size))
                return fail(reason, @"Invalid Mach-O segment range");
            if (!rangeValid(sizeof(segment), (uint64_t)segment.nsects * sizeof(struct section_64), command.cmdsize)) return fail(reason, @"Invalid Mach-O section table");
            for (uint32_t j = 0; j < segment.nsects; j++) {
                struct section_64 section;
                memcpy(&section, bytes + position + sizeof(segment) + j * sizeof(section), sizeof(section));
                if (!(section.flags & (S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS)) || !section.size) continue;
                // Modern 64-bit code is PC-relative; unsupported text relocations
                // must fail rather than masking instruction bytes.
                if (section.nreloc || !rangeValid(section.offset, section.size, size) ||
                    !rangeValid(section.addr, section.size, segment.vmaddr + segment.vmsize) || section.addr < segment.vmaddr)
                    return fail(reason, @"Unsupported executable section/relocations");
                uint64_t address;
                if (slideValue >= 0) {
                    if ((uint64_t)slideValue > UINT64_MAX - section.addr) return fail(reason, @"Mach-O slide overflow");
                    address = section.addr + (uint64_t)slideValue;
                } else {
                    uint64_t delta = (uint64_t)(-(slideValue + 1)) + 1;
                    if (delta > section.addr) return fail(reason, @"Mach-O slide underflow");
                    address = section.addr - delta;
                }
                if (!codePages(address, section.size, reason)) return NO;
                uint8_t buffer[65536];
                for (uint64_t offset = 0; offset < section.size;) {
                    mach_vm_size_t count = MIN((uint64_t)sizeof(buffer), section.size - offset), read = 0;
                    kern_return_t status = mach_vm_read_overwrite(mach_task_self(), address + offset, count, (mach_vm_address_t)buffer, &read);
                    if (status != KERN_SUCCESS || read != count) return fail(reason, @"Cannot read owned executable memory");
                    if (memcmp(buffer, bytes + section.offset + offset, (size_t)count))
                        return fail(reason, [NSString stringWithFormat:@"Modified executable section in %@", path.lastPathComponent]);
                    offset += count;
                }
                checked++;
            }
        }
        position += command.cmdsize;
    }
    if (position != commandsEnd || !checked) return fail(reason, @"No verified executable sections");
    *sections += checked;
    if (!baseline) imageBaselines[path] = data;
    return YES;
}

@implementation RoundlaneMacGuard
+ (BOOL)verify:(NSString **)reason {
    @synchronized(self) {
        if (reason) *reason = nil;
        if (!processStatus(reason) || !signedBundle(reason)) return NO;
        NSString *releaseViolation = [RoundlaneReleaseBinding violation];
        if (releaseViolation) return fail(reason, releaseViolation);
        if (!imageBaselines) imageBaselines = [NSMutableDictionary new];
        NSString *root = [NSBundle.mainBundle.bundlePath.stringByResolvingSymlinksInPath stringByAppendingString:@"/"];
        NSUInteger owned = 0, sections = 0;
        uint32_t count = _dyld_image_count();
        // The Launch Services bridge is separately signed and covered by the release proof.
        // Its worker must be the exact bundled native runtime, never an arbitrary image.
        NSString *executable = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"] && [[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleExecutable"] isEqual:@"RoundlaneLauncher"]
            ? [[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS/Roundlane"] stringByResolvingSymlinksInPath]
            : NSBundle.mainBundle.executablePath.stringByResolvingSymlinksInPath;
        if (!count || ![executable hasPrefix:root]) return fail(reason, @"Main executable is outside the signed bundle");
        for (uint32_t i = 0; i < count; i++) {
            const char *name = _dyld_get_image_name(i);
            const struct mach_header *header = _dyld_get_image_header(i);
            if (!name || !header) return fail(reason, @"Loaded image disappeared during verification");
            NSString *path = [NSString stringWithUTF8String:name].stringByResolvingSymlinksInPath;
            if (!path) return fail(reason, @"Invalid loaded image path");
            if (i == 0 && ![path isEqualToString:executable]) return fail(reason, @"Main loaded image does not match the signed bundle");
            if ([path hasPrefix:root]) {
                if (!imageMatches(path, header, _dyld_get_image_vmaddr_slide(i), &sections, reason)) return NO;
                owned++;
            } else if (![path hasPrefix:@"/System/Library/"] && ![path hasPrefix:@"/usr/lib/"]) {
                return fail(reason, [NSString stringWithFormat:@"Foreign loaded image: %@", path.lastPathComponent]);
            }
        }
        if (!owned || !sections) return fail(reason, @"Owned executable image not verified");
        return YES;
    }
}
+ (int)diagnostic {
    NSMutableArray *results = [NSMutableArray new];
    BOOL passed = YES;
    for (NSUInteger i = 0; i < 3; i++) {
        NSString *reason = nil;
        NSDate *start = NSDate.date;
        BOOL valid = [self verify:&reason];
        passed &= valid;
        [results addObject:@{@"valid":@(valid), @"reason":reason ?: NSNull.null, @"milliseconds":@(-start.timeIntervalSinceNow * 1000)}];
    }
    NSData *report = [NSJSONSerialization dataWithJSONObject:@{@"passed":@(passed), @"exam_started":@NO, @"checks":results} options:NSJSONWritingPrettyPrinted error:nil];
    fwrite(report.bytes, 1, report.length, stdout);
    fputc('\n', stdout);
    return passed ? 0 : 1;
}
@end
