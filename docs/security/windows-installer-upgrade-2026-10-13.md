# Windows installer upgrade verification

Installing the first Release6 package over the old VM installation left 59 obsolete files, including Chromium 147 libraries and debug/documentation files. The new manifest correctly rejected the mixed directory: 405 actual runtime files, 346 expected (344 components plus manifest and signature).

The installer now runs `win-app/prepare-update.ps1` before copying the runtime. It refuses active Runtime/Client processes, waits for the existing service to stop, rejects a reparse-point runtime and moves the previous runtime to a uniquely named sibling backup. The installer writes its complete runtime into the new directory. Previous files are preserved outside the active runtime; the signature and strict inventory checks remain unchanged.

The rebuilt installer was installed through its actual `/S` path in the Windows VM. All 344 component hashes, manifest/signature bytes, exact inventory, bundled source ZIP and running installed service path passed. Its backup contains all 405 old files. A second installation passed the same checks and preserved a different backup containing the prior 346-file signed runtime. No exam was launched by either installation.

Evidence: `setup/final-release-20261013/windows-upgrade-first-verification.json`, `windows-installation-verification.json`, `windows-installer-verification.json`. The installer also contains the exact reviewed update helper and all seven native recovery sources match the bundled source ZIP.

Installer SHA-256: `369f4718f1aaad45d9ac1ec5bb633d17a7155d6b4779d6031df26378cafa8f08`. Source ZIP SHA-256: `7e4c253b16a08d83e06a8b941a2958127441a64ba454160262642ee6c9578de2`.

This is Windows 11 ARM64 with x64 emulation. Physical x64 and protected Mac rehearsal remain required. Backups are preserved for the organizer and are never executed automatically.
