# Organizer exit after a faulted Runtime channel

Release4 retained terminal quarantine and observers after WCF timed out during controlled Runtime suspension. Organizer authentication succeeded, but resuming Runtime did not repair the channel. Administrative lab recovery restored the desktop; normal recovery remains unproven.

## Implemented candidate

Use a disposable named-pipe transport solely for RequestShutdown when the original channel is not Opened. It carries the existing session token. Do not repeat Connect, change RuntimeHost.AllowConnection, request configuration, resume activators, close quarantine or stop observers before acknowledgement. Recovery Open and operation timeouts are five seconds; dispose the transport with Abort. Denial or timeout remains failure.

After failed terminal shutdown, retain the same overlay, clear organizer authorization and require another valid code using the overlay's AutoResetEvent. No automatic exit is added.

Microsoft says a non-Opened WCF client must be aborted and references released: https://learn.microsoft.com/en-us/dotnet/framework/wcf/samples/expected-exceptions (read 2026-10-11). BaseHost independently authorizes Send using the token list. RuntimeHost permits only one authenticated Connect; recovery does not reopen that handshake.

## Evidence and remaining gates

- Fourteen linked production responsibility tests passed with fake UI/IPC, including repeated authorization and preparation after acknowledgement: setup/windows-recovery-flow-after.txt.
- NativeRecoveryProxyProbe loads the real .NET Framework communication assembly with fake WCF objects. Release4 failed recovery cases, passing healthy/no-session controls: setup/hardened-windows/recovery-proxy-before.json.
- Four reviewed files dispatched for deterministic native rebuild. Exact hashes: setup/hardened-windows/recovery-source.json.

## Release5 native evidence

The guest's original build orchestrator disappeared after producing Runtime/Client outputs without publishing its final report. A fresh Windows process inventory confirmed no MSBuild/PowerShell remained. A guarded finish attempt then identified a file-sharing error on the old report. `finish-recovery-native.ps1` checks all four patched source hashes, rejects any active build/exam and writes separate immutable progress records plus a new final report. All four project builds finished successfully at 2026-10-11T00:15:09Z; this final pass used `/t:Build`, not another clean rebuild.

Release5 stages 344 runtime files. Only Roundlane.Client.exe and SafeExamBrowser.Communication.dll differ from Release4. Duplicate outputs must agree byte-for-byte and already-created hard links are never overwritten. Manifest SHA-256: `cb7abd35701bcfa125a2bbf693ee666986f6afadc241ae83fb1850fe86f66d90`.

The real .NET Framework assembly passed eight mocked-transport checks, including IContextChannel operation timeout before Open, Open/Send timeouts, timeout-setter failure, authorization denial and no session. Four native mocked UI/IPC monitor checks also passed. Healthy Runtime/Client diagnostics accepted the signed release; a changed signature was rejected and the exact original signature restored. These tests started no exam.

Evidence: `setup/hardened-windows/recovery-native-completed.json`, `recovery-proxy-after.json`, `recovery-monitor-after.json`, `recovery-release-checks.json`, `recovery-host-stage-verification.json`.

The real Chromium browser rendered a page and passed five integrity checks without an exam. The Release5 installer passed a streamed inventory/hash check for all 344 runtime files and its exact bundled source ZIP. Neither result proves organizer recovery.

## Live Release5 failure and next candidate

The protected VM session connected to the mandatory service and rendered cpp.sh. A controlled integrity signal caused terminal quarantine. During a 180-second controlled Runtime suspension the original WCF channel faulted. A wrong organizer code was rejected; a correct code while paused failed within five seconds and the quarantine remained active. Runtime resumed automatically with a successful native resume status.

The disposable transport opened after resume, but `Send` failed with `ActionNotSupportedException` / `ContractFilter mismatch`. The cause is the actual contract: `SessionMode.Required` and `Send.IsInitiating = false`. The mocked transport probe did not model WCF's initiating-operation rules. **Release5 is not approved for contest use.**

The lab client was administratively terminated after confirming the exact session/process and failure. The desktop returned and the original installed service was restored. This is not normal organizer recovery; `recovery-lab-administrative-exit.json` explicitly records that distinction.

The next source candidate adds `RecoverShutdown(Guid)` as an initiating, terminating operation. Only Runtime opts in. BaseHost checks its existing communication-token list and otherwise returns Unauthorized; it dispatches only RequestShutdown, creates no token and does not reopen Connect. Ordinary Send remains non-initiating. The client uses this operation only on its disposable recovery transport. A new probe uses the production RuntimeHost with real named pipes to test the contract rather than substituting transport objects.

Build/probe success, another signed live rehearsal, new installer and combined packaging remain required. Full memory protection, kernel-level resistance and equivalence to SEB's closed module are not demonstrated.

## Release6 verified protocol and signed files

The seven reviewed source files built successfully in all four native projects. The real named-pipe probe using production RuntimeHost passed eight checks: initial authentication, ordinary Send cannot initiate, wrong token denied, Connect remains closed, replacement shutdown acknowledged, original token preserved, revoked token denied, and recovery restricted to shutdown. This probe started no exam and did not change OS restrictions.

Release6 contains 344 runtime files. Manifest SHA-256 is `e09249070ec461b0ab645f875487dc8a82033f77f12d5f5620abfcbaa7002ba0`. Runtime and Client accepted the healthy signed release; altered signature was rejected and the exact signature restored. The real Chromium 152 browser loaded its diagnostic page and passed five integrity checks. The host staging directory was checked against every manifest hash.

Evidence: `initiating-recovery-native-completed.json`, `initiating-recovery-wcf.json`, `initiating-release-checks.json`, `initiating-browser-results.json`. The downloadable kit contains a separate release verification report for installation, live recovery and platform limits. The full Mac protected session and physical x64 Windows rehearsal still require target machines.

## Release6 organizer recovery through the real GUI, 13 October

After the host Mac was manually unlocked, a fresh VM session at 16:43:48Z connected to the mandatory Release6 service. A controlled integrity signal caused terminal quarantine. Runtime PID 4872 was suspended at 16:54:47Z and resumed automatically at 16:57:47Z with native status 0. A wrong code was rejected at 16:56:09Z; the original named-pipe channel faulted at 16:56:26Z and quarantine remained active.

The organizer entered the existing test code through UTM's actual keyboard input at 17:00:21Z. The client logged authenticated shutdown through the replacement transport and acknowledgement at 17:00:21.928Z. Only after acknowledgement were the observers stopped. Runtime then restored the Default desktop, stopped the service session, recorded Session Terminated and finalized successfully. Both native exam processes were absent in the subsequent inventory, and the Windows desktop was visually observed. No administrative termination or guest reboot was used for this successful exit.

The original installed service path was restored and the four owned test tasks removed. Evidence: `setup/hardened-windows/final-gui-session-state.json`, `final-gui-client.log`, `final-gui-runtime.log`, `final-gui-pause-resumed.json`, `final-gui-environment-restored.json`. This validates organizer exit after the original channel fault in Windows 11 ARM64 with x64 emulation; it does not establish physical x64 or Mac behavior.
