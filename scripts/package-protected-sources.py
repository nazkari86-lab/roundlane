#!/usr/bin/env python3
"""Package current covered source, build tooling and licenses; never private data."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import zipfile

kit = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--platform', choices=['all', 'mac', 'windows'], default='all')
parser.add_argument('--output', type=Path, default=kit / 'setup/hardened-source')
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
excluded = {'.git','bin','obj','packages','dist','dist-protected','dist-recovery','dist-initiating','dependencies','build','__pycache__'}
private = {'organizer-private','participant-cards','codeforces-domain-users.txt','runtime-signing.seed'}
seed = (kit / 'organizer-private/runtime-signing.seed').read_bytes()
organizer_instructions = kit / 'organizer-private/participant-launch-organizer.txt'
participant_code = organizer_instructions.read_text().split('Общий код выхода: ')[1].splitlines()[0].encode() if organizer_instructions.exists() else None

def walk(folder):
    for path in (kit / folder).rglob('*'):
        relative = path.relative_to(kit)
        if path.is_file() and not excluded.intersection(relative.parts) and path.suffix != '.syso':
            yield relative

def package(name, paths):
    path = out / name
    pending = out / (name + '.pending')
    members = sorted(set(paths))
    with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for relative in members:
            assert not private.intersection(relative.parts), relative
            data = (kit / relative).read_bytes()
            assert seed not in data and seed.hex().encode() not in data, relative
            assert not participant_code or participant_code not in data, relative
            archive.writestr(str(relative), data)
    with zipfile.ZipFile(pending) as archive:
        assert archive.testzip() is None
        assert len(archive.namelist()) == len(members)
    os.replace(pending, path)
    with path.open('rb') as file:
        digest = hashlib.file_digest(file,'sha256').hexdigest()
    return dict(file=name, sha256=digest, members=len(members), bytes=path.stat().st_size, crc='passed', private_seed_excluded=True)

shared = [Path(p) for p in ['README.md','starter.cpp','competition.roundlane','mac-codeforces-cppsh-demo.seb']]
shared += [Path('docs/participant-launch-2026-10-14.md'),Path('docs/white-screen-2026-10-14.md'),Path('docs/codeforces-run-2026-10-14.md'),Path('docs/filter-audit-2026-10-14.md'),Path('docs/reliability-2026-10-14.md')]
shared += list(walk('tests/tabs-workspace')) + [Path('docs/tabs-design-2026-10-13.md')]
shared += list(walk('docs/security')) + list(walk('assets')) + list(walk('hub'))
root = kit / 'upstream/seb-mac'
tracked = subprocess.check_output(['git','-C',str(root),'ls-files','-co','--exclude-standard','-z']).decode().split('\0')
mac = [Path('upstream/seb-mac') / p for p in tracked if p and (root / p).is_file()]
mac += list(walk('native-mac'))
mac += [Path(p) for p in ['mac-app/Sources/HubServer.swift','scripts/build-native-mac.sh','scripts/build-participant-launcher.sh','scripts/prepare-native-mac.py','scripts/sign-native-mac.sh','scripts/test-mac-integrity.py','scripts/test-mac-hardened-runtime.py','scripts/test-mac-live-monitor.py','scripts/test-mac-memory-scanner.py','scripts/test-mac-release-binding.py','scripts/package-protected-sources.py','scripts/package-hardened-mac.py']]
windows = list(walk('upstream/seb-win-refactoring')) + list(walk('win-app')) + list(walk('tests/windows-client-flow'))
windows += [Path('setup/hardened-windows') / p for p in [
    'check-native-communication.ps1', 'check-native-monitor.ps1', 'control-ipc-pause.ps1',
    'check-native-recovery-before.ps1', 'check-native-recovery-after.ps1',
    'rebuild-recovery-native.ps1', 'finish-recovery-native.ps1', 'poll-recovery-build.ps1',
    'stage-recovery-release.ps1', 'recovery-source.json',
    'build-initiating-recovery.ps1', 'stage-initiating-recovery-release.ps1',
    'check-initiating-recovery-wcf.ps1', 'initiating-recovery-source.json',
]]
windows += [Path(p) for p in ['scripts/prepare-native-windows.py','scripts/build-native-windows.ps1','scripts/package-windows-source.py','scripts/check-windows-vendor.py','scripts/package-protected-sources.py','scripts/package-hardened-mac.py']]
reports = []
if args.platform in ('all', 'mac'):
    reports.append(package('RoundlaneMacSource.zip', mac+shared))
if args.platform in ('all', 'windows'):
    reports.append(package('RoundlaneWindowsSource.zip', windows+shared))
(out / 'source-package-results.json').write_text(json.dumps(dict(packages=reports, private_data_excluded=True),indent=2)+'\n')
print(json.dumps(reports,indent=2))
