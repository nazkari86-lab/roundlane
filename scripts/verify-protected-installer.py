#!/usr/bin/env python3
"""Read an NSIS installer without installing it; verify its signed runtime bytes."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('installer', type=Path)
parser.add_argument('signed_artifacts', type=Path)
parser.add_argument('source_archive', type=Path)
args = parser.parse_args()

def read_member(name):
    return subprocess.check_output(['7z', 'x', '-so', str(args.installer), name], stderr=subprocess.PIPE)

def member_hash(name):
    process = subprocess.Popen(['7z', 'x', '-so', str(args.installer), name], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    digest = hashlib.sha256()
    count = 0
    for chunk in iter(lambda: process.stdout.read(1024 * 1024), b''):
        digest.update(chunk)
        count += len(chunk)
    error = process.stderr.read()
    if process.wait() != 0:
        raise SystemExit('Extraction failed: ' + name + ': ' + error.decode(errors='replace')[:200])
    return digest.hexdigest(), count

data = (args.signed_artifacts / 'manifest.json').read_bytes()
signature = (args.signed_artifacts / 'manifest.sig').read_bytes()
if read_member('runtime/manifest.json') != data or read_member('runtime/manifest.sig') != signature:
    raise SystemExit('Installer signature or manifest differs from verified native release.')
manifest = json.loads(data.decode('utf-8-sig'))
expected = {entry['path']: entry['sha256'] for entry in manifest['files']}
listing = subprocess.check_output(['7z', 'l', '-slt', str(args.installer)], text=True)
paths = [line[7:].replace('\\', '/') for line in listing.splitlines() if line.startswith('Path = ')]
runtime = [name.removeprefix('runtime/') for name in paths if name.startswith('runtime/')]
if len(runtime) != len(set(runtime)) or set(runtime) != set(expected) | {'manifest.json', 'manifest.sig'}:
    raise SystemExit('Installer runtime inventory differs from signed inventory.')
size = 0
for name, sha in expected.items():
    actual, count = member_hash('runtime/' + name)
    if actual != sha:
        raise SystemExit('Installer runtime file hash mismatch: ' + name)
    size += count
with args.source_archive.open('rb') as stream:
    source_hash = hashlib.file_digest(stream, 'sha256').hexdigest()
if member_hash('sources/RoundlaneWindowsSource.zip')[0] != source_hash:
    raise SystemExit('Bundled source ZIP differs from staged source ZIP.')
with args.installer.open('rb') as stream:
    installer_hash = hashlib.file_digest(stream, 'sha256').hexdigest()
print(json.dumps({'passed': True, 'examStarted': False, 'installed': False,
                  'runtimeFiles': len(expected), 'runtimeBytes': size,
                  'sourceArchiveSha256': source_hash,
                  'manifestSha256': hashlib.sha256(data).hexdigest(),
                  'installerSha256': installer_hash,
                  'installerBytes': args.installer.stat().st_size}))
