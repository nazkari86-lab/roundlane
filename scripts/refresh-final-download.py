#!/usr/bin/env python3
"""Refresh the final kit from verified installer/DMG and the current report."""
import hashlib
import json
import os
from pathlib import Path
import zipfile

kit = Path(__file__).resolve().parent.parent
release = kit / 'setup/final-release-20261013'
archive = kit.parent / 'Roundlane-2026-10-13.zip'
installer = kit / 'win-app/dist-initiating/Roundlane 3.0 Setup.exe'
dmg = release / 'Roundlane Mac Candidate.dmg'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

installed = json.loads((release / 'windows-installation-verification.json').read_text(encoding='utf-8-sig'))
assert installed['passed'] is True and installed['runtimeFiles'] == 344
package = json.loads((release / 'windows-installer-verification.json').read_text())
assert package['passed'] is True and digest(installer) == package['installerSha256']
assert installed['sourceSha256'] == package['sourceArchiveSha256']
mac = json.loads((release / 'mac-dmg-verification.json').read_text())
assert digest(dmg) == mac['sha256'] and mac['mounted_guard']['passed'] is True
report = json.loads((release / 'Проверки.json').read_text())
assert report['windows']['normal_organizer_exit_after_fault_verified'] is True
assert report['windows']['installer_installation_verified'] is True
assert report['olympiad_ready'] is False

files = {
    'Windows/Roundlane Windows.exe': installer,
    'Mac/Roundlane Mac.dmg': dmg,
    'Перед олимпиадой.txt': release / 'Перед олимпиадой.txt',
    'Проверки.json': release / 'Проверки.json',
    'LICENSE-SEB-Windows.txt': kit / 'win-app/dist-initiating/LICENSE-SEB.txt',
    'LICENSE-SEB-Mac.txt': release / 'mac-dmg-stage/LICENSE-SEB.txt',
    'NOTICE-Windows.txt': kit / 'win-app/dist-initiating/ROUNDLANE-NOTICE.txt',
    'NOTICE-Mac.txt': release / 'mac-dmg-stage/NOTICE.txt',
}
hashes = {name: digest(path) for name, path in files.items()}
checksums = ''.join(f'{sha}  {name}\n' for name, sha in hashes.items()).encode()
pending = archive.with_suffix('.zip.pending')
with zipfile.ZipFile(pending, 'w') as output:
    for name, path in files.items():
        output.write(path, 'Roundlane/' + name,
                     compress_type=zipfile.ZIP_STORED if path.suffix in {'.exe','.dmg'} else zipfile.ZIP_DEFLATED)
    output.writestr('Roundlane/SHA256SUMS.txt', checksums, compress_type=zipfile.ZIP_DEFLATED)
with zipfile.ZipFile(pending) as checked:
    assert checked.testzip() is None and len(checked.namelist()) == 9
    for name, expected in hashes.items():
        with checked.open('Roundlane/' + name) as stream:
            assert hashlib.file_digest(stream, 'sha256').hexdigest() == expected, name
    assert checked.read('Roundlane/SHA256SUMS.txt') == checksums
os.replace(pending, archive)
result = dict(archive=str(archive), sha256=digest(archive), bytes=archive.stat().st_size,
              members=9, crc_and_member_sha256_verified=True,
              windows_source_inside_installer_verified=True, mac_source_inside_dmg_verified=True,
              windows_installer_installation_verified=True, windows_gui_organizer_recovery_verified=True,
              licenses_included=True, old_public_archive_preserved=(kit.parent/'Roundlane.zip').exists(),
              olympiad_ready=False)
(release/'download-verification.json').write_text(json.dumps(result,indent=2)+'\n')
audit_path=kit/'setup/hardened-release/completion-audit.json'
audit=json.loads(audit_path.read_text())
audit['current_download']=result
audit['download_ready']=True
audit_path.write_text(json.dumps(audit,indent=2)+'\n')
print(json.dumps(result,indent=2))
