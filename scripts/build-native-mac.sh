#!/bin/bash
set -euo pipefail
kit_dir="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$kit_dir/upstream/seb-mac"
build_dir="$kit_dir/setup/seb-mac-build"
dist_dir="$kit_dir/native-mac/dist"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

"$DEVELOPER_DIR/usr/bin/xcodebuild" -checkFirstLaunchStatus
python3 "$kit_dir/scripts/prepare-native-mac.py"
"$DEVELOPER_DIR/usr/bin/xcodebuild" -workspace "$source_dir/SafeExamBrowser.xcworkspace" \
    -scheme 'Safe Exam Browser' -configuration Debug -destination 'generic/platform=macOS' \
    -derivedDataPath "$build_dir" -disableAutomaticPackageResolution -jobs 4 \
    CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build > "$kit_dir/setup/roundlane-native-build.log" 2>&1

mkdir -p "$dist_dir"
app_path="$dist_dir/Roundlane.app"
if test -e "$app_path"; then
    mv "$app_path" "$dist_dir/Roundlane.previous-$(date +%s).app"
fi
ditto "$build_dir/Build/Products/Debug/Roundlane.app" "$app_path"
mkdir -p "$app_path/Contents/Helpers"
helper_dir="$(mktemp -d "$build_dir/roundlane-helper.XXXXXX")"
trap 'rm -rf "$helper_dir"' EXIT
for arch in arm64 x86_64; do
    swiftc -O -target "${arch}-apple-macosx12.1" -framework Network \
        "$kit_dir/mac-app/Sources/HubServer.swift" -o "$helper_dir/server-$arch"
done
lipo -create "$helper_dir/server-arm64" "$helper_dir/server-x86_64" \
    -output "$app_path/Contents/Helpers/contest-hub-server"
"$kit_dir/scripts/build-participant-launcher.sh" "$app_path"
"$kit_dir/scripts/sign-native-mac.sh" "$app_path"
"$app_path/Contents/MacOS/Roundlane" --self-test > "$kit_dir/setup/roundlane-native-self-test.json"
"$app_path/Contents/MacOS/Roundlane" --roundlane-integrity-check > "$kit_dir/setup/roundlane-mac-guard-results.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["passed"] is True and r["exam_started"] is False and len(r["checks"]) == 3' "$kit_dir/setup/roundlane-mac-guard-results.json"
"$app_path/Contents/MacOS/Roundlane" --roundlane-session-check > "$kit_dir/setup/roundlane-mac-session-results.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["passed"] is True and r["exam_started"] is False and r["kiosk_started"] is False and r["keychain_used"] is False' "$kit_dir/setup/roundlane-mac-session-results.json"
"$app_path/Contents/MacOS/Roundlane" --runtime-settings-check > "$kit_dir/setup/roundlane-runtime-settings-check.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["runtime_settings_check"] == "passed" and r["exam_started"] is False' "$kit_dir/setup/roundlane-runtime-settings-check.json"
"$app_path/Contents/MacOS/Roundlane" --runtime-webview-check > "$kit_dir/setup/roundlane-runtime-webview-check.json"
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["runtime_webview_check"] == "passed" and r["exam_started"] is False' "$kit_dir/setup/roundlane-runtime-webview-check.json"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$dist_dir/Roundlane 3.9 Development.zip"
shasum -a 256 "$dist_dir/Roundlane 3.9 Development.zip"
