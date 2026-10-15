#!/bin/bash
set -euo pipefail
app_path="${1:?usage: build-participant-launcher.sh APP_PATH}"
kit_dir="$(cd "$(dirname "$0")/.." && pwd)"
cp "${ROUNDLANE_PARTICIPANT_SETTINGS:-$kit_dir/competition.roundlane}" "$app_path/Contents/Resources/Roundlane/competition.roundlane"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
work_dir="$kit_dir/setup/participant-launcher-build"
mkdir -p "$work_dir"
for arch in arm64 x86_64; do
 xcrun swiftc -O -target "${arch}-apple-macosx12.1" -framework AppKit "$kit_dir/native-mac/Sources/ParticipantLauncher.swift" -o "$work_dir/launcher-$arch"
done
lipo -create "$work_dir/launcher-arm64" "$work_dir/launcher-x86_64" -output "$app_path/Contents/MacOS/RoundlaneLauncher"
python3 - "$app_path/Contents/Info.plist" <<'PY'
import sys,plistlib
from pathlib import Path
p=Path(sys.argv[1]);d=plistlib.loads(p.read_bytes());d['CFBundleExecutable']='RoundlaneLauncher'
d['CFBundleShortVersionString']='3.9.5'
d['CFBundleVersion']='20261016.1'
d['CFBundleDocumentTypes']=[t for t in d.get('CFBundleDocumentTypes',[]) if t.get('CFBundleTypeName')!='Roundlane Competition']+[{'CFBundleTypeName':'Roundlane Competition','CFBundleTypeRole':'Viewer','LSHandlerRank':'Owner','LSItemContentTypes':['local.roundlane.competition'],'CFBundleTypeExtensions':['roundlane']}]
d['UTExportedTypeDeclarations']=[{'UTTypeIdentifier':'local.roundlane.competition','UTTypeDescription':'Roundlane Competition','UTTypeConformsTo':['public.json'],'UTTypeTagSpecification':{'public.filename-extension':['roundlane']}}]
p.write_bytes(plistlib.dumps(d))
PY
