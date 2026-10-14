# Platform hardening: verified development candidates

These changes are in the source and tested candidates. The public Roundlane.zip and installed applications have not been updated. This is progress toward the protection design, not a completed release.

## Windows

`RoundlaneProcessPolicy` enables PROCESS_MITIGATION_IMAGE_LOAD_POLICY using SetProcessMitigationPolicy, then reads it back with GetProcessMitigationPolicy. Required bits: NoRemoteImages, NoLowMandatoryLabelImages, PreferSystem32Images (7). Existing unrelated bits are preserved. Native guard initialization requires the policy; each memory check confirms it remains enforced. Failure is a verification error, not a silently accepted compatibility fallback. It applies to Runtime/Client after managed startup and signed-release verification; it is not proof of coverage before the CLR loads or in Chromium subprocesses.

VM test: the same self-authored low-integrity DLL loads in the control process (flags 0), and fails with Win32 error 5 after enforcement (flags 7). The normal DLL, JIT and repeat application/check continue to work. A network-share load was not exercised; NoRemoteImages and PreferSystem32 were confirmed by OS readback, not separate behavioral tests.

Full Client MSBuild passed at 2026-10-10T20:48:59Z. Latest signed native Runtime safe CLI accepted valid release, rejected one-byte signature mutation with exit 1, and accepted restored signature. The signature was restored byte-for-byte. No exam was entered by these tests.

Actual Chromium 152.0.7977.140 / CefSharp 152.0.100.0 loaded about:blank and passed five memory checks. First check 7686 ms, subsequent 4101–4399 ms under ARM64 emulation: performance still requires improvement/real x64 measurement.

Eight latest guard regression cases passed: signed release; healthy relocated code; reject writable executable code; reject changed read-only code; accept restored code; JIT/repeat; reject foreign loaded DLL; accept after unload. Defender signature regressions and narrow D3D loader checks also passed. D3D generated-stub mutations remained blocked by the OS (487), so actual guard detection of a modified generated stub remains untested. The terminal quarantine log now correctly states that the lock screen remains active after organizer authentication.

Evidence in `setup/memory-guard/`: `process-policy-control.json`, `process-policy-enforced.json`, `process-policy-low-label.txt`, `policy-client-build.json`, `policy-browser-results.json`, `policy-browser-exit.json`, `policy-memory-results.json`, `policy-signature-results.json`, `policy-signature-exit.json`, `policy-loader-results.json`, `policy-loader-exit.json`, `native-policy-results.json`. Previous protected-session event-to-quarantine/restoration test remains separately documented; this new policy has only been exercised in safe native/browser checks, not another live kiosk session.

## macOS

Universal arm64+x86_64 candidate builds with ENABLE_DEBUG_DYLIB=NO. Code resides in the main executable; Xcode's separate Roundlane.debug.dylib is not packaged. Hardened runtime signing uses `codesign --options runtime` with no exception entitlements. Nested libraries/helper are signed before the enclosing application; strict verification includes all architectures. Normal build script now uses this signing path.

An initial separately linked debug-library candidate failed library validation due to absent Team IDs. The monolithic executable fixed that tested failure without disabling library validation. Signature reports flags 0x10002 (adhoc,runtime). Ad hoc signing is not publisher authentication, Developer ID or notarization. Compatibility on older/Intel Macs and bundled Swift fallback loading has not been proven by the current arm64 host test.

Hardened candidate passed resource/contest self-test (17 cases), runtime-settings initialization and creation of the actual built-in WKWebView. All report exam_started=false. The settings diagnostic now uses an in-memory private store and ephemeral AES key; it never retrieves/stores/rotates the user's keychain key. The actual exam's keychain path is unchanged. A previously waiting diagnostic was sampled in SecItemCopyMatching, then terminated; no keychain permission was accepted.

DYLD_INSERT_LIBRARIES test uses only our marker-writing fixture: ordinary control loaded it; actual hardened Roundlane --self-test ignored it and completed successfully without a marker. This establishes this injection path's prevention, not full memory protection. Script: `python3 scripts/test-mac-hardened-runtime.py setup/Roundlane-hardened-candidate.app`. Evidence: `setup/mac-hardened-tests/dyld-results.json`, stdout/stderr; `setup/roundlane-hardened-{self-test,settings-check,webview-check}.json`; `setup/roundlane-hardened-build.log`.

### Own Mac guard added and verified

`OtherSources/RoundlaneMacGuard.m` is linked into the macOS target. Before the organizer starts and again after confirmation, `RoundlaneBootstrap.prepare` verifies protection; a failure returns to the organizer with an error before creating a session or entering kiosk. This is source/build verified; the organizer gate itself has not been exercised through live UI after these changes.

Guard checks actual dynamic signing status using `kSecCSDynamicInformation`, requires hardened runtime, rejects a previously/debugged or currently traced process, and rejects JIT, unsigned executable memory, disabled executable protection/library validation, DYLD environment and get-task-allow exception entitlements. Strict bundle signature/resource validation covers both architecture slices. Main loaded image must match the bundle's executable path. Foreign loaded image paths outside the application and trusted OS `/System/Library/` and `/usr/lib/` are rejected; this is a path-based OS trust boundary, not validation of every system-image signer.

Own 64-bit Mach-O instruction sections are compared against file bytes after selecting the exact FAT/FAT64 architecture and applying its VM slide. Current readable/executable/nonwritable page permissions and successful Mach reads are required. Unsupported per-section text relocations, malformed ranges/tables and images without verified code fail. A successful immutable file baseline is retained for each owned image; later file changes in that process fail. Neither current executable memory nor writable snapshots are used as the expected code baseline. This baseline is authenticated by the bundle's current signature, which is **ad hoc and does not authenticate the release publisher**; independent release-key binding is now added; see mac-release-binding-2026-10-11.md.

Latest universal source build succeeded. `--roundlane-integrity-check` passed three complete checks, 45.6/43.1/41.9 ms on the arm64 host. Both safe settings and real WKWebView checks now also run the guard after their initialization and passed. Six disposable-candidate cases passed: healthy, changed resource rejected (-67054), restored resource accepted, missing runtime rejected, unsafe library-validation exception rejected, final restored healthy state. Candidate resources/protection were restored and strict all-architecture verification passed. Evidence `setup/roundlane-mac-guard-results.json`, `setup/roundlane-mac-guard-build.log`, `setup/mac-hardened-tests/integrity-results.json`; test script `scripts/test-mac-integrity.py`. DYLD test was repeated against this latest guard build and passed.

No host Mac exam/kiosk, installed-app replacement, login item or autostart was performed. Isolated arm64 instruction-mutation detection and independent release-key binding are now verified; actual production-app memory mutation, full native quarantine UI and OS recovery checks remain incomplete. Windows renderer/JIT coverage, service-required rehearsal, shutdown-IPC failure recovery, final source/license packaging and one updated download remain incomplete.

## References consulted

- Microsoft Image Load Policy: https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-process_mitigation_image_load_policy
- Microsoft SetProcessMitigationPolicy: https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-setprocessmitigationpolicy
- Official WinSDK enum/flags in microsoft/win32metadata winnt.h (ProcessImageLoadPolicy = 10).
- Apple Hardened Runtime: https://developer.apple.com/documentation/security/hardened-runtime

### Continuous Mac protection and terminal quarantine

RoundlaneIntegritySession runs a real startup check and repeats it every five seconds, with a separate three-second watchdog. A failure is sticky: late success cannot resume the session. The controller opens the terminal overlay before removing browser content. Retry/override paths are unavailable; the captured organizer digest permits exit only. Missing credentials, verifier exceptions and timeouts fail closed.

Safe diagnostics exercise the shared password controller with a fake exit delegate, not a protected desktop: wrong code rejected, forced close rejected, correct code authorizes exit without clearing quarantine; watchdog late-success, stop cancellation, missing-code and exception cases pass in the earlier candidate. A controlled live resource change was detected by the real signature guard and restored afterwards. Evidence: setup/roundlane-mac-session-results.json and setup/mac-hardened-tests/live-monitor-results.json.

Latest source changes schedule the ten-second authorized exit fallback in common run-loop modes, rather than a default-mode delayed selector, and invalidate it during termination. This prevents modal/event-tracking modes from suppressing the timer; the fallback still requires verified organizer authorization and classic mode. Target minimum deployment is now 12.1, matching the documented requirement. Live native exit/desktop restoration is still untested; the updated universal candidate build and safe checks passed. The live mutation diagnostic now uses the production five-second interval. Fresh session diagnostics passed all five cases; the real resource mutation was detected, restored, and followed by a successful guard check; the real WKWebView diagnostic passed without starting kiosk.

Roundlane builds also redact encryption-key values from five upstream SEBCryptor debug/verbose log paths; ordinary upstream builds keep their existing logging. Rebuilt universal candidate passed after the change. Logs: setup/roundlane-mac-exit-timer-build.log and setup/roundlane-mac-redacted-build.log. Candidate was recreated cleanly to avoid stale NIB resource layouts. Public Roundlane.zip and installed app remain previous releases.

### Additional Windows terminal-exit corrections

A linked production-source regression reproduced canceled-password-wait and thrown-shutdown-IPC failures. Shared sticky quarantine, reauthentication at first violation, cancellation rejection and fail-closed IPC handling now pass nine fake-UI/IPC cases. WPF cancellation is consumed for the next result. See windows-terminal-exit-2026-10-11.md; native Windows assemblies/signatures are not rebuilt for these latest changes yet, and actual desktop/service recovery remains pending.
