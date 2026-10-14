#!/usr/bin/env python3
"""Negative checks on the disposable candidate, never on installed apps or kiosk."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys

kit = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
if app != kit / 'setup' / 'Roundlane-hardened-candidate.app':
    raise SystemExit('Only the named disposable development candidate may be modified')
out = kit / 'setup' / 'mac-hardened-tests'
out.mkdir(exist_ok=True)
resource = app / 'Contents/Resources/Roundlane/starter.cpp'
original = resource.read_bytes()
signer = kit / 'scripts/sign-native-mac.sh'
results = []

def check(name, expected, reason_part=None):
    run = subprocess.run([str(app / 'Contents/MacOS/Roundlane'), '--roundlane-integrity-check'], capture_output=True, text=True, timeout=30)
    report = json.loads(run.stdout)
    (out / f'integrity-{name}.json').write_text(run.stdout)
    passed = report['passed'] == expected and report['exam_started'] is False and run.returncode == (0 if expected else 1)
    if reason_part:
        passed = passed and all(reason_part in r['reason'] for r in report['checks'])
    results.append({'name': name, 'passed': passed, 'expected_valid': expected, 'exit': run.returncode, 'checks': report['checks']})
    if not passed:
        raise RuntimeError(f'{name} did not produce the required rejection/result')

restored = False
try:
    check('healthy', True)
    resource.write_bytes(original + b'\n// controlled disposable resource mutation\n')
    check('changed-resource', False, 'Invalid application signature/resources')
    resource.write_bytes(original)
    check('restored-resource', True)
    subprocess.run(['codesign', '--force', '--options', '0', '--sign', '-', str(app)], check=True)
    check('missing-runtime', False, 'Hardened runtime is not enforced')
    exceptions = out / 'test-only-unsafe-entitlements.plist'
    exceptions.write_bytes(plistlib.dumps({'com.apple.security.cs.disable-library-validation': True}))
    subprocess.run(['codesign', '--force', '--options', 'runtime', '--entitlements', str(exceptions), '--sign', '-', str(app)], check=True)
    check('unsafe-exception', False, 'Unsafe hardened-runtime entitlement')
finally:
    resource.write_bytes(original)
    subprocess.run([str(signer), str(app)], check=True)
    restored = resource.read_bytes() == original
    check('final-restored', True)
    report = {'passed': restored and len(results) == 6 and all(r['passed'] for r in results), 'candidate_restored': restored, 'exam_started': False, 'results': results}
    (out / 'integrity-results.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'passed': report['passed'], 'cases': len(results), 'candidate_restored': restored, 'exam_started': False}, indent=2))
sys.exit(0 if report['passed'] else 1)
