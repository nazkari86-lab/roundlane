# Required Windows service

A source audit found that the organizer's generated profile used sebServicePolicy=0 (optional) and did not explicitly clear sebServiceIgnore. Upstream defaults have IgnoreService=true, so the existing launcher preflight did not prove service enforcement within the native session.

The Windows profile generator now sets sebServicePolicy=2 (mandatory) and sebServiceIgnore=false. Profile validation requires both values. A regression test tampers each setting independently and requires rejection; fresh `go test -count=1 ./core` passed. The updated x64 organizer executable compiled to setup/hardened-windows/Roundlane.exe; it is a candidate, not an installed/public update.

A separate VM-only profile service-required-vm.seb and startup script are prepared. The original test profile and previous evidence remain available. Neither the production template nor Mac profile receives VM/display exceptions.

Live service-required rehearsal is not yet verified. UTM guest command dispatch returned success without fresh result files; pulled preflight/live reports remained older and are not accepted as current evidence. The guest desktop and Run dialog were visible through CUA, but automatic text input garbled the command, so it was not submitted. The host Mac then locked; a request to unlock is pending. No protected session was started in this turn. The old installed organizer seen in the VM is not the newly compiled candidate.

Required observations still pending: latest signed Runtime/Client connect to the mandatory service, protected browser runs without false positives, integrity signal creates terminal quarantine, wrong code stays blocked, correct code exits and restores desktop with service policy restoration. A second rehearsal must inject failed shutdown IPC and verify quarantine/recovery. Old reports with service ignored cannot prove these results.
