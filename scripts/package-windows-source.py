#!/usr/bin/env python3
from pathlib import Path
import zipfile

kit = Path(__file__).resolve().parents[1]
out = kit / 'win-app/dist/RoundlaneWindowsSource.zip'
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
    for directory in ['upstream/seb-win-refactoring', 'win-app', 'hub', 'assets']:
        for path in (kit / directory).rglob('*'):
            relative = path.relative_to(kit)
            if path.is_file() and not set(relative.parts).intersection({'.git','bin','obj','packages','dist','dependencies','__pycache__'}) and path.suffix not in {'.syso'}:
                archive.write(path,str(relative))
    for relative in ['scripts/prepare-native-windows.py','scripts/build-native-windows.ps1','scripts/package-windows-source.py',
                     'docs/standalone-roundlane-design.md','docs/independent-integrity-2026-10-11.md','starter.cpp','mac-codeforces-cppsh-demo.seb']:
        archive.write(kit / relative,relative)
print(out)
