#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
kit_dir="$(cd "$project_dir/.." && pwd)"
dist_dir="$project_dir/dist"
app_path="$dist_dir/Roundlane.app"
dmg_path="$dist_dir/Roundlane 2.2.dmg"
zip_path="$dist_dir/Roundlane 2.2.zip"
build_dir="$dist_dir/.build"

mkdir -p "$dist_dir"
rm -rf "$app_path" "$build_dir"
mkdir -p "$build_dir" "$app_path/Contents/MacOS" "$app_path/Contents/Helpers" "$app_path/Contents/Resources/hub"

for arch in arm64 x86_64; do
    swiftc -O -target "${arch}-apple-macosx12.1" -framework AppKit -framework CryptoKit \
        "$project_dir/Sources/ContestCore.swift" "$project_dir/Sources/RoundlaneApp.swift" -o "$build_dir/app-$arch"
    swiftc -O -target "${arch}-apple-macosx12.1" -framework Network \
        "$project_dir/Sources/HubServer.swift" -o "$build_dir/server-$arch"
done

lipo -create "$build_dir/app-arm64" "$build_dir/app-x86_64" -output "$app_path/Contents/MacOS/Roundlane"
lipo -create "$build_dir/server-arm64" "$build_dir/server-x86_64" -output "$app_path/Contents/Helpers/contest-hub-server"
chmod 755 "$app_path/Contents/MacOS/Roundlane" "$app_path/Contents/Helpers/contest-hub-server"

inkscape "$kit_dir/assets/roundlane.svg" --export-filename="$build_dir/AppIcon.png" --export-width=1024 --export-height=1024 >/dev/null 2>&1
mkdir -p "$build_dir/AppIcon.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$build_dir/AppIcon.png" --out "$build_dir/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$build_dir/AppIcon.png" --out "$build_dir/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$build_dir/AppIcon.iconset" -o "$app_path/Contents/Resources/AppIcon.icns"

cp "$kit_dir/hub/index.html" "$kit_dir/hub/app.js" "$app_path/Contents/Resources/hub/"
cp "$kit_dir/mac-codeforces-cppsh-demo.seb" "$app_path/Contents/Resources/contest.seb"
cp "$kit_dir/starter.cpp" "$app_path/Contents/Resources/starter.cpp"

cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>ru</string>
    <key>CFBundleDisplayName</key><string>Roundlane</string>
    <key>CFBundleExecutable</key><string>Roundlane</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>local.roundlane.app</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Roundlane</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.2</string>
    <key>CFBundleVersion</key><string>6</string>
    <key>LSMinimumSystemVersion</key><string>12.1</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST

plutil -lint "$app_path/Contents/Info.plist" "$app_path/Contents/Resources/contest.seb"
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
"$app_path/Contents/MacOS/Roundlane" --self-test

stage_dir="$(mktemp -d "$dist_dir/.stage.XXXXXX")"
trap 'rm -rf "$stage_dir" "$build_dir"' EXIT
ditto "$app_path" "$stage_dir/Roundlane.app"
ln -s /Applications "$stage_dir/Applications"
hdiutil create -quiet -volname "Roundlane 2.2" -srcfolder "$stage_dir" -ov -format UDZO "$dmg_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"
hdiutil verify "$dmg_path"
shasum -a 256 "$dmg_path" "$zip_path"
echo "Built: $dmg_path"
echo "Built: $zip_path"
