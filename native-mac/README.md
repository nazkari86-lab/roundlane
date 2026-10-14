# Roundlane 3.9 Development for macOS

Roundlane contains the public SEB macOS 3.7.1 runtime. It does not launch or require a separately installed SEB. This local development package uses SEB's classic kiosk mode (`lockdownModePolicy=1`), which does not use Apple Automatic Assessment Configuration (AAC). Apple assessment approval is therefore not a startup requirement for this mode. The package is ad hoc signed and is not a verified competition release.

## Build

Run `scripts/build-native-mac.sh` from the kit directory. It uses Xcode 26.2, the pinned SEB checkout, the existing Roundlane icon, hub and C++ template. It builds a universal arm64 + x86_64 macOS application and helper. The competition package contains `Roundlane Mac.dmg`; `dist/Roundlane 3.5 Development.zip` is also retained. The build script does not launch an exam, install an application, or add login items.

The public checkout references the unavailable proprietary `libSEBSupport.a`. Its macOS link reference was removed, as contemplated by the upstream README. The public code links without unresolved symbols. This does not establish equivalence to the official SEB's proprietary protection modules. Original MPL notices and the bundled LICENCE are retained.

## Startup and exit

The compact native organizer form contains a Codeforces group and visible exit code (default **1234**), a four-digit code generator, Copy, Close and Start competition. Input validation is live; Start is disabled until the group/code and bundled profile are valid. A group without the `https://` prefix is normalized. The last confirmed group is remembered; the exit code is stored in the current user’s macOS Keychain on Close, Save settings and confirmed Start, then restored at the next launch. Imported participant settings do not write a plaintext code. Command-C/V/A and keyboard focus use native Edit menu commands.

Start opens a separate confirmation showing the exact group, code and Cmd+Q exit. Return in an editor does not start the competition. Back/Escape returns to the form without losing fields. There is no lengthy startup instruction panel. The embedded runtime suppresses the upstream About splash and removes About/Help/Settings menu commands; license files and source notices remain bundled.

The organizer UI runs in a temporary process of the same bundled executable, without loading the SEB nib/delegate or changing system presentation settings. Only after manual confirmation does the parent create a fresh private temporary profile, start its own local hub helper, and enter the normal SEB `NSApplicationMain` lifecycle. This preserves SEB's application subclass and avoids pre-launch AppKit initialization interfering with its delegate notifications. No separate SEB application is used.

The temporary profile forces classic kiosk mode, permits exit by Cmd+Q or the SEB quit button followed by the organizer's code, and keeps the approved URL filter. The local helper exits and removes temporary session files when its Roundlane parent exits. No login item, scheduled startup or automatic exam restoration is installed. Each launch starts with the organizer form and requires a fresh confirmation.

`--self-test` checks packaged resources and profile settings without loading SEB. `--preflight-check` allows the same organizer input and confirmation path, creates the temporary profile, verifies its hub token, then cleans up and exits **before SEB loads or lockdown begins**. `--preflight-only` keeps Start disabled for inspection.

## Installation on this Mac

`/Applications/Roundlane.app` is now version 3.9. The previous 3.2 application is preserved in SetupBackups. The Desktop link points to it. The old 2.1 launcher is preserved in `~/Library/Application Support/Roundlane/SetupBackups/`.

## Verified and unverified

The universal build, ad hoc signature, self-test, safe preflight and organizer form were checked for version 3.6. The preceding version 3.2 also verified the enabled organizer form, invalid-code correction, confirmation/Back/Escape behavior and safe preflight profile/helper/cleanup path were verified on this Mac. The installed application was checked through the actual exam confirmation, then cancelled. New form controls, live validation, code generation/copy/paste, group normalization and narrow/wide layouts were checked. Safe preflight with a custom generated code verified the matching quit hash, local helper token and cleanup. No exam session or OS lockdown was entered.

Codeforces login/submissions, cpp.sh, multiple windows, blocking of other applications/sites, and desktop restoration after an actual exam still require a controlled test on a separate Mac. Classic mode must not be claimed to provide AAC guarantees. Trusted distribution signing/notarization is a separate concern from AAC permission. Version 3.5 includes both Apple Silicon and Intel executable slices. Intel runtime has not been tested; Windows 3.0 builds its own Roundlane runtime from public SEB sources.

Shared competition settings: Save creates a `.roundlane` JSON with the group and SHA-256 quit hash; Open locks the fields and hides the code in confirmation. The same file loads on Windows 2.5. No automatic exam startup. `--check-settings <path>` validates a settings file and profile without a GUI or SEB session.

3.6 fixes Cloudflare local srcdoc iframe/blob-worker filtering. A real CAPTCHA checkbox appears in the installed safe browser check; The Codeforces login form subsequently opened in this session. The agent did not click CAPTCHA; its completion mechanism was not observed. Account login, submission and a protected exam remain unverified.

## Participant launch

`competition.roundlane` in bundled Roundlane resources provides signed participant defaults. Opening the app or a signed participant document starts its contest without the organizer form. `--organizer-tools` keeps organizer preparation available. A separately signed Launch Services bridge handles document events; the exact native runtime worker is authenticated by the same release proof. No OS login item is added. Organizer plaintext exit codes are not shipped. See `docs/participant-launch-2026-10-14.md`.
