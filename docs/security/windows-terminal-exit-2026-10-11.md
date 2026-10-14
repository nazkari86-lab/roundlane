# Windows terminal exit regression

Source review reproduced two failures in the real ClientResponsibility: a canceled lock-screen result ended the terminal password wait; a thrown shutdown IPC exception escaped the protected path. Baseline harness linked the production source and failed both cases in setup/windows-client-flow-before.json.

Changes:

- ClientContext publishes a volatile, sticky IntegrityQuarantined flag before requesting the session lock. The first violation invalidates any earlier quit-password authorization; later healthy checks cannot clear quarantine.
- The shared lock-screen controller checks this state even for existing ordinary lock screens. Quarantine never closes the overlay or resumes activators, and cancellation cannot authorize exit.
- All client shutdown requests enforce organizer authentication while quarantined. A terminal shutdown exception becomes a failed request, with the overlay retained. Ordinary unrelated exit exceptions retain their previous behavior.
- WPF LockScreen consumes its cancellation notification so the next password result is not permanently marked canceled.

Fresh .NET 8 harness links both real ClientResponsibility and IntegrityResponsibility, using explicitly fake UI and runtime IPC. Nine cases passed: ordinary lock still resumes; terminal wrong/correct password authorizes exit only; cancellation cannot authorize; missing code keeps waiting; failed IPC stays locked; thrown IPC stays locked; shared quarantine blocks another exit route; shared quarantine prevents ordinary resume; real integrity handler publishes sticky state and rejects reuse of earlier authentication. Build/run: `dotnet build tests/windows-client-flow/ClientFlow.csproj`, then `dotnet run --no-build --project tests/windows-client-flow/ClientFlow.csproj`. Evidence setup/windows-client-flow-build.txt and setup/windows-client-flow-after.json.

This proves the linked controller branches with mocks, not Windows framework/WPF execution, service restoration, process termination or native desktop recovery. The full Windows Client assembly and signed runtime must still be rebuilt in the VM before protected rehearsal; previous native build/signature reports refer to the earlier source. Actual WPF cancellation consumption is source reviewed only. The host Mac is now unlocked. UTM was restarted after its SPICE audio callback blocked; the test-only virtual audio device was removed. The exact four-file patch rebuild was requested through the interactive Windows console; full native build results remain pending. Guest CLI process execution has not produced fresh completion evidence. No exam was launched during these checks.

## Fresh full native build

The pinned four-file patch built Client, Runtime, Service and ResetUtility with MSBuild Release/x64 at 2026-10-10T22:18:08Z. Each retrieved project log contains its native output and no build errors. Known missing MinimumRecommendedRules.ruleset warnings remain. Evidence: setup/hardened-windows/terminal-native-build.json and terminal-build-*.txt. This supersedes the pending native compilation statement above. Signing the exact output and mandatory-service/OS recovery rehearsal remain incomplete; the public combined archive is unchanged.

## Consistent signed candidate

Initial package staging rejected three differing Core DLL hashes with the same assembly identity. The shared Core project did not enable deterministic compilation and successive project builds produced different bytes. Rebuilt all four native projects using the same Release/x64 parameters with Deterministic=true; the duplicate assembly comparison passed. The standard build helper now rebuilds consistently, rejects conflicting shared DLLs, stages in a fresh directory and preserves previous output.

The clean C:\RoundlaneHardenedRelease2\runtime contains 344 signed files (433402380 bytes including manifest before signature). Host-only Ed25519 signature binds manifest SHA256 f4661d4216ff6e9767f03324d6065e4083e40d32eeb3a4d41ccdbe6468040941. Latest native Runtime and Client integrity checks passed; one-byte signature mutation failed with exit 1 and invalid-signature reason; original signature was restored byte-for-byte and Runtime passed again. Evidence: setup/hardened-windows/consistent-native-build.json, terminal-release-stage.json and terminal-release-checks-summary.json. These safe checks did not start an exam or change the installed service. Protected mandatory-service and recovery rehearsal remain pending.

## Protected mandatory-service rehearsal verified

Fresh signed Release2 session started 2026-10-10T22:38:14Z, confirmed mandatory service connection and service session creation. Actual Chromium displayed cpp.sh on the protected desktop. The apparent stale Windows desktop was UTM's hidden window: showing the exact VM via Window > Roundlane Windows Test refreshed the display; no VM restart was necessary.

Our same-user SignalHarness set the real Runtime integrity-violation event. Actual WPF terminal quarantine blocked the browser. Two incorrect password submissions were logged and the overlay stayed active; organizer test code then authorized shutdown, with Runtime IPC acknowledged. Desktop restoration was visibly observed. Fresh terminal-session-state.json at 22:48:08Z confirms quarantine, wrong-code rejection, correct-code acceptance, session termination, original desktop restoration and no remaining Runtime/Client. Original installed service path was restored Running at 22:48:37Z.

Evidence: setup/hardened-windows/terminal-session-state.json, terminal-session-client-evidence.txt and terminal-service-restored.json. This tests the real event-to-quarantine-to-exit path with an injected event, not an actual memory write attack. Shutdown IPC failure/organizer recovery remains untested at OS level. Mac native kiosk recovery and exhaustive renderer/JIT coverage remain unverified; the public archive is unchanged.

## Additional communication-path regression

NativeCommunicationProbe.cs loads the actual .NET Framework Client assembly, using a fake message box and shutdown delegate. The signed Release2 baseline fails three of five cases: connection loss before/after organizer authentication closes Client, and an unsolicited Runtime shutdown bypasses quarantine authentication. CommunicationResponsibility now keeps quarantine active on connection loss and rejects Runtime shutdown until organizer authentication. Ordinary disconnect and authenticated Runtime shutdown retain their paths. Existing upstream unit tests were extended; the native assembly probe is the executable verification, without WPF/OS recovery. Fresh four-project deterministic rebuild passed at 22:56:50Z; release staging, post-fix native probe and protected IPC-failure rehearsal remain pending.

WCF SendTimeout covers both sending and receiving the reply, per https://learn.microsoft.com/en-us/dotnet/framework/wcf/feature-details/configuring-timeout-values-on-a-binding . The isolated RuntimePauseProbe temporarily suspends only the reviewed VM Runtime and automatically resumes it after 180 seconds; it is not shipped in the runtime and introduces no production bypass flag.

## Release3 native checks and real connection timeout

The rebuilt production Client passed all five native communication probe cases. The Release3 manifest hash is be72c04be10bbf9c0c69050ca539cb30dc96a5fdbc018cfba96ce914b5c12a8a. Runtime and Client passed signature checks, a mutated signature was rejected, and the original signature was restored and verified. Actual CEF loaded about:blank with five healthy checks. Evidence: communication-after.json, ipc-release-checks.json and ipc-browser-exit.json in setup/hardened-windows.

The mandatory-service protected session began at 23:02:41Z. Runtime PID 6516 and Client PID 6396 entered real WPF quarantine after the integrity event. RuntimePauseProbe recorded suspension of Runtime at 23:08:51Z. The actual WCF ping timed out at 23:10:03Z; CommunicationResponsibility logged that quarantine remained active, twice, and the red lock screen remained visible. This verifies actual connection-loss containment, rather than only a fake shutdown delegate.

The later complete Client log confirms two wrong-code rejections followed by correct-code acceptance at 23:10:23Z. RequestShutdown then failed on the already faulted WCF channel, and at 23:10:24Z the real IntegrityResponsibility logged that quarantine remained active. Thus real connection timeout and a subsequent authenticated shutdown-IPC failure both retain quarantine. This is not a successful exit or recovery test. The complete log is setup/hardened-windows/ipc-client-final.log.

UTM subsequently reported the VM stopped unexpectedly, before automatic process resume could be verified. After an explicit start, the Windows desktop was visible. A fresh process report at 23:13:17Z lists only Service PID 3188 and no Runtime/Client. Old log flags in that report do not mean the old session is still running. The original service ImagePath was restored Running at 23:13:49Z. This demonstrates return to a usable desktop after VM restart, not organizer recovery from a permanently faulted channel within the same session. Cleanup and final packaging remain required. The public archive remains unchanged.

Cleanup was confirmed at 23:14:51Z: all three rehearsal tasks were removed, no native exam processes remained, and the original service was restored. Release3 export verifies all 344 manifest file hashes; its ZIP is 188110811 bytes, SHA256 ec7c92a93ce533b9e3804926bee9358b187d8fc701d0266ca23c6f53adbfce3a. Host transfer is a separate pending operation.

## System monitoring preparation regression

The actual failure log shows SystemSentinel stopping before RequestShutdown failed. Although quarantine remained visible, preparation had already disabled system observers. Added four linked-source cases: failed and thrown terminal IPC must not dispatch preparation, terminal preparation follows a successful reply, and ordinary preparation retains its original order. The old source failed the three terminal cases; the changed source passed all 13 linked cases. TryRequestShutdown now defers terminal preparation until communication.Success, while ordinary preparation remains before the request. Evidence: setup/windows-monitor-flow-before.txt and setup/windows-monitor-flow-after.txt. These are fake UI/IPC tests, not native WPF/OS tests. Release3 predates this fix; a new native rebuild/signature/rehearsal is required and the exported ZIP is not the final release.

## Signed Release4 and native monitoring regression

All four native projects rebuilt deterministically at 23:21:14Z, with consistent shared assemblies. The fresh C:\RoundlaneHardenedRelease4\runtime stage contains 344 manifest entries. Its signed manifest SHA256 is 5a5313393d87d85ddf72551b2406c0afbb764543c8376c3eea9f5881815761cb. Comparing manifests proves that only Roundlane.Client.exe changed from Release3; its host-transferred SHA256 is 7deb110626d88976a5043a3319fc831ccd7666f5b9b14467091988d1c7e4dc61, matching the signed entry.

NativeMonitorProbe loads the actual .NET Framework Client and invokes production TryRequestShutdown with mocked IPC, message box and responsibility collection. Release3 fails the three terminal monitoring-order cases, while Release4 passes all four, including unchanged ordinary exit order. Evidence: setup/hardened-windows/monitor-probe-before.json and monitor-probe-after.json. Runtime and Client safe integrity diagnostics also passed; altered signature was rejected and restored original signature verified at 23:24:36Z. This confirms the native assembly branch and signature binding, not the complete protected desktop or recovery flow. Release4 protected rehearsal, organizer recovery, source refresh and final combined packaging remain required.

Actual Release4 Chromium 152.0.7977.140 loaded the diagnostic page and passed five checks (9535, 6731, 4277, 4258, 4276 ms), exiting with code 0 at 23:26:08Z. No exam started. These timings come from Windows ARM64 x64 emulation and do not establish performance on a physical x64 competition laptop. Evidence: setup/hardened-windows/monitor-browser-results.json and monitor-browser-exit.json.
# Release4 live failure rehearsal and installer verification

At 2026-10-10T23:42Z, signed Release4 ran in the Windows ARM64 VM with the mandatory service. The previous interrupted-session lock was cleared with the lab organizer code, and actual cpp.sh was visible. The integrity signal then displayed terminal quarantine. This was event injection, not an actual memory modification attack.

The exact Runtime PID 6984 was suspended at 23:48:25Z. The real WCF channel faulted; the lock remained. Organizer authentication was accepted at 23:50:29Z, but RequestShutdown failed on the faulted channel. ApplicationMonitor events continued and system observers were not prepared for shutdown. Runtime resumed successfully at 23:50:48Z. **Organizer recovery through the faulted channel remains defective.**

To end this lab session, an administrative helper terminated only the verified Release4 Client PID 8788 after checking authenticated failure evidence. Runtime restored the original desktop and stopped its service session at 23:52:06Z, then finalized at 23:52:42Z. The original installed service was restored Running at 23:53:11Z. This is administrative lab recovery, not proof of the normal organizer recovery path.

The assembled Windows installer passed streaming verification of all 344 signed runtime files, manifest/signature bytes, and embedded source ZIP. SHA-256 c49c828e9c7cda087ee06c8c072c4c43a8e8b3797509a525965b5347cacb3215, 294639082 bytes. The verifier initially used the wrong source member path; the observed NSIS path is sources/RoundlaneWindowsSource.zip. No installer rebuild was needed for this verifier correction. The installer is a candidate and has not been installed or published by this check.

Evidence: setup/hardened-windows/monitor-client-final.log, monitor-runtime-final.log, monitor-ipc-resume-state.json, monitor-service-restored.json, protected-installer-verification.json. Mac host kiosk was not started. Full memory protection, exhaustive renderer/JIT coverage and admin/kernel resistance are not established.

