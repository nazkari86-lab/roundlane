#!/bin/bash
set -euo pipefail
app_path="${1:?usage: sign-native-mac.sh PATH_TO_ROUNDLANE_APP}"
kit_dir="$(cd "$(dirname "$0")/.." && pwd)"
entitlements="$kit_dir/native-mac/Roundlane.entitlements"
test -f "$app_path/Contents/MacOS/Roundlane"
if test -f "$app_path/Contents/MacOS/Roundlane.debug.dylib"; then
    echo 'Rebuild with ENABLE_DEBUG_DYLIB=NO before hardened ad hoc signing.' >&2
    exit 1
fi

# Sign nested code first. No hardened-runtime exceptions: our executable does
# not generate JIT code; WebKit uses Apple's separate, signed web processes.
# This is local ad hoc signing, not Developer ID or notarization.
if test -d "$app_path/Contents/Frameworks"; then
    while IFS= read -r -d '' library; do
        codesign --force --options runtime --sign - "$library"
    done < <(find "$app_path/Contents/Frameworks" -type f -name '*.dylib' -print0)
fi
if test -f "$app_path/Contents/Helpers/contest-hub-server"; then
    codesign --force --options runtime --entitlements "$entitlements" --sign - "$app_path/Contents/Helpers/contest-hub-server"
fi
# The native runtime remains a separate exact, authenticated worker when a
# Launch Services bridge is used as the bundle entry point.
if test -f "$app_path/Contents/MacOS/RoundlaneLauncher"; then
    codesign --force --options runtime --entitlements "$entitlements" --sign - "$app_path/Contents/MacOS/Roundlane"
fi
codesign --force --options runtime --entitlements "$entitlements" --sign - "$app_path"
# Initial signing establishes each Mach-O signature region. The independent
# proof covers all other code/data bytes and resources; final signing seals it.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
release_tool="$kit_dir/setup/roundlane-release-tool"
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" -target "$(uname -m)-apple-macosx12.1" \
    -parse-as-library -D ROUNDLANE_RELEASE_TOOL \
    "$kit_dir/upstream/seb-mac/OtherSources/RoundlaneReleaseBinding.swift" -o "$release_tool"
"$release_tool" "$kit_dir/organizer-private/runtime-signing.seed" "$app_path" >&2
codesign --force --options runtime --entitlements "$entitlements" --sign - "$app_path"
codesign --verify --deep --strict --all-architectures "$app_path"
