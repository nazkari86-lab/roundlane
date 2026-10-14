#!/usr/bin/env python3
"""Reconstruct the exact Release4 runtime from verified Release3 plus its delta."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path, PurePosixPath

parser = argparse.ArgumentParser()
parser.add_argument('archive', type=Path)
parser.add_argument('delta', type=Path)
parser.add_argument('destination', type=Path)
args = parser.parse_args()
expected_archive = 'ec7c92a93ce533b9e3804926bee9358b187d8fc701d0266ca23c6f53adbfce3a'
expected_manifest = '5a5313393d87d85ddf72551b2406c0afbb764543c8376c3eea9f5881815761cb'
expected_signature = 'bffcaf4c944ea3f421c12bb359b4ab89f239257bcc2518ec8a7bc9a04f999bfc'

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

if args.destination.exists():
    raise SystemExit('Preserve existing destination; choose a new empty stage.')
if digest(args.archive) != expected_archive:
    raise SystemExit('Source archive incomplete or different from guest export.')
if digest(args.delta / 'manifest.json') != expected_manifest or digest(args.delta / 'manifest.sig') != expected_signature:
    raise SystemExit('Release4 signing artifacts differ from reviewed native checks.')
manifest = json.loads((args.delta / 'manifest.json').read_text(encoding='utf-8-sig'))
expected = {item['path']: item['sha256'] for item in manifest['files']}
if len(expected) != len(manifest['files']):
    raise SystemExit('Duplicate manifest entry.')
with zipfile.ZipFile(args.archive) as archive:
    names = []
    for item in archive.infolist():
        # .NET Framework on Windows emits backslashes in ZIP member names.
        name = item.filename.replace('\\', '/')
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or ':' in name or item.is_dir():
            raise SystemExit('Unexpected ZIP entry: ' + item.filename)
        names.append(name)
    if len(set(names)) != len(names) or set(names) != set(expected) | {'manifest.json', 'manifest.sig'}:
        raise SystemExit('ZIP inventory differs from signed runtime inventory.')
    if archive.testzip() is not None:
        raise SystemExit('ZIP CRC check failed.')
    previous = json.loads(archive.read('manifest.json').decode('utf-8-sig'))
    before = {item['path']: item['sha256'] for item in previous['files']}
    if set(before) != set(expected) or [name for name in expected if expected[name] != before[name]] != ['Roundlane.Client.exe']:
        raise SystemExit('Unexpected delta between reviewed Release3 and Release4.')
    for item in archive.infolist():
        destination = args.destination / item.filename.replace('\\', '/')
        destination.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(item) as source, destination.open('wb') as output:
            shutil.copyfileobj(source, output)
for name in ('Roundlane.Client.exe', 'manifest.json', 'manifest.sig'):
    shutil.copyfile(args.delta / name, args.destination / name)
for name, sha in expected.items():
    if digest(args.destination / name) != sha:
        raise SystemExit('Materialized file hash mismatch: ' + name)
actual = {path.relative_to(args.destination).as_posix() for path in args.destination.rglob('*') if path.is_file()}
if actual != set(expected) | {'manifest.json', 'manifest.sig'}:
    raise SystemExit('Unexpected output files.')
print(json.dumps({'passed': True, 'files': len(expected), 'manifestSha256': expected_manifest,
                  'destination': str(args.destination.resolve()), 'examStarted': False}))
