#!/usr/bin/env python3
"""Own release-key negative tests on exact disposable candidate; no kiosk."""
import json
from pathlib import Path
import subprocess
import sys

kit = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
assert app == kit / 'setup/Roundlane-hardened-candidate.app'
out = kit / 'setup/mac-hardened-tests'
out.mkdir(exist_ok=True)
exe = app / 'Contents/MacOS/Roundlane'
seal = app / 'Contents/_CodeSignature/CodeResources'
resource = app / 'Contents/Resources/Roundlane/starter.cpp'
manifest = app / 'Contents/Resources/Roundlane/release.json'
signature = app / 'Contents/Resources/Roundlane/release.sig'
extra = app / 'Contents/Resources/Roundlane/test-only-foreign.txt'
assert not extra.exists()
original = {p: p.read_bytes() for p in [exe, seal, resource, manifest, signature]}
results = []

def restore():
    extra.unlink(missing_ok=True)
    for p, data in original.items():
        p.write_bytes(data)

def resign():
    subprocess.run(['codesign', '--force', '--options', 'runtime', '--entitlements', str(kit / 'native-mac/Roundlane.entitlements'), '--sign', '-', str(app)], check=True, capture_output=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app)], check=True, capture_output=True)

def check(name, expected, reason=None):
    run = subprocess.run([str(exe), '--roundlane-integrity-check'], capture_output=True, text=True, timeout=30)
    report = json.loads(run.stdout)
    passed = report['passed'] is expected and report['exam_started'] is False and run.returncode == (0 if expected else 1)
    if reason:
        passed = passed and all(reason in c['reason'] for c in report['checks'])
    results.append(dict(name=name, passed=passed, exit=run.returncode, checks=report['checks']))
    (out / f'release-{name}.json').write_text(run.stdout)
    assert passed, name

try:
    check('healthy', True)
    resource.write_bytes(original[resource] + b'\n// controlled release-proof test\n')
    resign()
    check('resigned-resource', False, 'differs from authenticated release')
    restore()
    record = json.loads(original[manifest])
    record['files'][0]['sha256'] = '0' * 64
    manifest.write_text(json.dumps(record, separators=(',', ':')))
    resign()
    check('resigned-manifest', False, 'Invalid independent release signature')
    restore()
    corrupt = bytearray(original[signature]); corrupt[0] ^= 1
    signature.write_bytes(corrupt)
    resign()
    check('resigned-signature', False, 'Invalid independent release signature')
    restore()
    manifest.unlink()
    resign()
    check('missing-proof', False, 'Cannot verify independent release proof')
    restore()
    signature.write_bytes(original[signature] + b'\0')
    resign()
    check('oversized-signature', False, 'Application file size limit exceeded')
    restore()
    manifest.write_bytes(b'x' * (4*1024*1024+1))
    resign()
    check('oversized-manifest', False, 'Application file size limit exceeded')
    restore()
    extra.write_text('Controlled unknown file; never executed')
    resign()
    check('resigned-extra-file', False, 'differs from authenticated release')
    restore()
    marker = b'Cannot verify independent release proof'
    assert original[exe].count(marker) >= 1
    exe.write_bytes(original[exe].replace(marker, b'Xannot verify independent release proof'))
    resign()
    check('resigned-owned-executable', False, 'differs from authenticated release')
finally:
    restore()
    subprocess.run(['codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app)], check=True)
    check('final-restored', True)
    report = dict(passed=len(results)==10 and all(r['passed'] for r in results), candidate_restored=all(p.read_bytes()==v for p,v in original.items()), exam_started=False, kiosk_started=False, results=results)
    (out / 'release-binding-results.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k != 'results'}, indent=2))
assert report['passed'] and report['candidate_restored']
