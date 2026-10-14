#!/usr/bin/env python3
"""Prepare the Roundlane macOS target without changing upstream security checks."""
import json
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

kit = Path(__file__).resolve().parents[1]
source = kit / "upstream/seb-mac"
project = source / "SafeExamBrowser.xcodeproj/project.pbxproj"
text = project.read_text()
for identifier in ("69F7B62314F411FB00FD0761", "69F7B62414F411FB00FD0761"):
    pattern = rf"(\t\t{identifier} /\* (?:Debug|Release) \*/ = \{{)(.*?)(\n\t\t\}};)"
    match = re.search(pattern, text, re.S)
    if not match:
        raise RuntimeError(f"Missing macOS build configuration {identifier}")
    body = match[2]
    for key, value in {
        "PRODUCT_NAME": '"Roundlane"',
        "PRODUCT_BUNDLE_IDENTIFIER": "local.roundlane.exam",
        "INFOPLIST_FILE": '"Roundlane-Info.plist"',
        "MARKETING_VERSION": "3.9",
        "MACOSX_DEPLOYMENT_TARGET": "12.1",
        "DEVELOPMENT_TEAM": '""',
        "ASSETCATALOG_COMPILER_APPICON_NAME": "RoundlaneAppIcon",
    }.items():
        body, count = re.subn(rf"(?m)^(\s*{key} = ).*?;", lambda m: m[1] + value + ";", body)
        if count != 1:
            raise RuntimeError(f"Expected one {key} in {identifier}, got {count}")
    if "PRODUCT_MODULE_NAME =" not in body:
        body = body.replace('PRODUCT_NAME = "Roundlane";', 'PRODUCT_NAME = "Roundlane";\n\t\t\t\tPRODUCT_MODULE_NAME = Safe_Exam_Browser;')
    definition = 'GCC_PREPROCESSOR_DEFINITIONS = "$(inherited) ROUNDLANE_PUBLIC_RUNTIME=1";'
    if "GCC_PREPROCESSOR_DEFINITIONS =" in body:
        body = re.sub(r'GCC_PREPROCESSOR_DEFINITIONS = .*?;', definition, body)
    else:
        body = body.replace('PRODUCT_MODULE_NAME = Safe_Exam_Browser;', 'PRODUCT_MODULE_NAME = Safe_Exam_Browser;\n\t\t\t\t' + definition)
    text = text[:match.start()] + match[1] + body + match[3] + text[match.end():]
text = text.replace('path = "Safe Exam Browser.app"; sourceTree = BUILT_PRODUCTS_DIR;', 'path = "Roundlane.app"; sourceTree = BUILT_PRODUCTS_DIR;')
project.write_text(text)

info = plistlib.loads((source / "SafeExamBrowser-Info.plist").read_bytes())
info.update(CFBundleDisplayName="Roundlane", CFBundleName="Roundlane", LSMinimumSystemVersion="12.1")
# This development app must not take over the official SEB's file and URL associations.
info.pop("CFBundleURLTypes", None)
# NSDocumentController needs the internal window document to create a browser.
# Register no extensions/SEB URL schemes; this type is only used inside the app.
info["CFBundleDocumentTypes"] = [dict(
    CFBundleTypeName="DocumentType", CFBundleTypeRole="Editor",
    NSDocumentClass="SEBBrowserWindowDocument", LSHandlerRank="None",
)]
info["NSAppTransportSecurity"]["NSAllowsLocalNetworking"] = True
(source / "Roundlane-Info.plist").write_bytes(plistlib.dumps(info))

resources = source / "Roundlane"
(resources / "hub").mkdir(parents=True, exist_ok=True)
for name in ("index.html", "app.js", "editor-drafts.js"):
    shutil.copy2(kit / "hub" / name, resources / "hub" / name)
shutil.copy2(kit / "starter.cpp", resources / "starter.cpp")
settings = plistlib.loads((kit / "mac-codeforces-cppsh-demo.seb").read_bytes())
for key in ("allowFind", "enableZoomPage", "enableZoomText", "showTime", "browserWindowAllowReload", "newBrowserWindowAllowReload", "showReloadWarning", "newBrowserWindowShowReloadWarning", "enableBrowserWindowToolbar", "allowBrowsingBackForward", "showQuitButton"):
    settings[key] = True
settings.update(browserWindowWebView=3, lockdownModePolicy=1, downloadAndOpenSebConfig=False, allowSwitchToApplications=False,
                allowDownloads=False, allowUploads=False, browserWindowAllowAddressBar=False,
                newBrowserWindowAllowAddressBar=False, allowPreferencesWindow=False)
expressions = [r"^http://127\.0\.0\.1:18765/", r"^https://roundlane723396\.contest\.codeforces\.com/group/tqy1SBMbAa/contest/723396/", r"^https://roundlane723396\.contest\.codeforces\.com/group/tqy1SBMbAa/contest/723396/?([?#].*)?$", r"^https://assets\.codeforces\.com/", r"^https://challenges\.cloudflare\.com/", r"^https://cpp\.sh/"]
settings["URLFilterRules"] = [dict(action=1, active=True, expression=expression, regex=True) for expression in expressions]
(resources / "contest.seb").write_bytes(plistlib.dumps(settings))
(resources / "NOTICE.txt").write_text("Roundlane 3.9 development build contains the public SEB macOS 3.7.1 runtime.\nSEB source revision: a1e3f786aac4aa2e827998dcf8ca139f2c5205a9.\nOriginal notices and MPL 2.0 terms are retained in the sources and bundled LICENCE.\nThe proprietary libSEBSupport.a is not included. ROUNDLANE_PUBLIC_RUNTIME excludes its private startup marker requirement. This is not equivalent to the official private protections. Exam operation has not been verified.\nThis build uses SEB classic kiosk mode (policy 1), which does not use Apple AAC. It is ad hoc signed.\n")

icon_dir = source / "Safe Exam Browser/Images.xcassets/RoundlaneAppIcon.appiconset"
icon_dir.mkdir(exist_ok=True)
large = icon_dir / "Roundlane-1024.png"
subprocess.run(["inkscape", str(kit / "assets/roundlane.svg"), f"--export-filename={large}", "--export-width=1024", "--export-height=1024"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
images = []
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        pixels = size * scale
        name = f"Roundlane-{size}@{scale}x.png"
        subprocess.run(["sips", "-z", str(pixels), str(pixels), str(large), "--out", str(icon_dir / name)], check=True, stdout=subprocess.DEVNULL)
        images.append(dict(idiom="mac", size=f"{size}x{size}", scale=f"{scale}x", filename=name))
(icon_dir / "Contents.json").write_text(json.dumps(dict(images=images, info=dict(version=1, author="xcode")), indent=2) + "\n")
print("Prepared Roundlane native macOS target and resources")
