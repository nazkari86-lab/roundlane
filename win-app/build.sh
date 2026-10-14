#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
kit_dir="$(cd "$project_dir/.." && pwd)"
dist_dir="${ROUNDLANE_DIST_DIR:-$project_dir/dist}"
mkdir -p "$dist_dir"
dist_dir="$(cd "$dist_dir" && pwd)"

mkdir -p "$dist_dir/hub"
cd "$project_dir"
go test ./core
signing_key="${ROUNDLANE_SIGNING_KEY:-$kit_dir/organizer-private/runtime-signing.seed}"
release_public_key="$(go run ./cmd/sign-runtime "$signing_key" "$dist_dir/runtime")"
if ! rg -q -F "$release_public_key" core/runtime_key.go; then
 echo 'Signing key differs from pinned runtime identity; update runtime_key.go for your own fork.' >&2
 exit 1
fi
magick -background none "$kit_dir/assets/roundlane.svg" -define icon:auto-resize=256,128,64,48,32,16 "$project_dir/app.ico"
go run github.com/akavel/rsrc@v0.10.2 -manifest app.manifest -ico app.ico -o cmd/app/rsrc.syso
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags='-s -w -H=windowsgui' -o "$dist_dir/Roundlane.exe" ./cmd/app
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags='-s -w -H=windowsgui' -o "$dist_dir/RoundlaneHub.exe" ./cmd/hub
cp "$kit_dir/mac-codeforces-cppsh-demo.seb" "$dist_dir/contest.seb"
cp "${ROUNDLANE_PARTICIPANT_SETTINGS:-$kit_dir/competition.roundlane}" "$dist_dir/competition.roundlane"
cp "$kit_dir/starter.cpp" "$dist_dir/starter.cpp"
cp "$kit_dir/hub/index.html" "$kit_dir/hub/app.js" "$dist_dir/hub/"
cp "$kit_dir/upstream/seb-win-refactoring/LICENSE.txt" "$dist_dir/LICENSE-SEB.txt"
if ! test -f "$dist_dir/runtime/manifest.json"; then
    echo 'Native Windows runtime missing: run scripts/build-native-windows.ps1 on Windows first.' >&2
    exit 1
fi
cp "$kit_dir/upstream/seb-win-refactoring/ROUNDLANE-NOTICE.txt" "$dist_dir/ROUNDLANE-NOTICE.txt"
source_output="${ROUNDLANE_SOURCE_OUTPUT:-$kit_dir/setup/hardened-source}"
python3 "$kit_dir/scripts/package-protected-sources.py" --platform windows --output "$source_output"
cp "$source_output/RoundlaneWindowsSource.zip" "$dist_dir/RoundlaneWindowsSource.zip"
python3 "$kit_dir/scripts/check-windows-vendor.py" --native
nsis_args=(-V2 "-DROUNDLANE_DIST=$dist_dir")
if [[ "${ROUNDLANE_NON_SOLID:-0}" == "1" ]]; then
 nsis_args+=(-DROUNDLANE_NON_SOLID=1)
fi
if [[ -n "${ROUNDLANE_INSTALLER_OUTPUT:-}" ]]; then
 nsis_args+=("-DROUNDLANE_INSTALLER_OUTPUT=$ROUNDLANE_INSTALLER_OUTPUT")
fi
makensis "${nsis_args[@]}" native-installer.nsi
shasum -a 256 "${ROUNDLANE_INSTALLER_OUTPUT:-$dist_dir/Roundlane 3.0 Setup.exe}"
