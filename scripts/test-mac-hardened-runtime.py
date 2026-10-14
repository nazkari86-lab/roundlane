#!/usr/bin/env python3
"""Exercise DYLD injection using only our own marker fixture; never starts kiosk."""
import json
import os
from pathlib import Path
import subprocess
import sys

kit = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
out = kit / 'setup' / 'mac-hardened-tests'
out.mkdir(exist_ok=True)
env = {**os.environ, 'DEVELOPER_DIR': '/Applications/Xcode.app/Contents/Developer'}
fixture = out / 'marker.dylib'
control = out / 'control'
sources = kit / 'setup' / 'memory-guard'
subprocess.run(['xcrun', 'clang', '-dynamiclib', str(sources / 'mac-dyld-fixture.c'), '-o', str(fixture)], env=env, check=True)
subprocess.run(['xcrun', 'clang', str(sources / 'mac-dyld-control.c'), '-o', str(control)], env=env, check=True)
for binary in (fixture, control):
    subprocess.run(['codesign', '--force', '--sign', '-', str(binary)], check=True)
results = []
for name, command, expected in (
    ('control', [str(control)], True),
    ('hardened_roundlane', [str(app / 'Contents/MacOS/Roundlane'), '--self-test'], False),
):
    marker = out / f'{name}-marker.txt'
    marker.unlink(missing_ok=True)  # Exact disposable test-only marker.
    test_env = {**env, 'DYLD_INSERT_LIBRARIES': str(fixture), 'ROUNDLANE_DYLD_TEST_MARKER': str(marker)}
    run = subprocess.run(command, env=test_env, capture_output=True, text=True, timeout=30)
    (out / f'{name}-stdout.txt').write_text(run.stdout)
    (out / f'{name}-stderr.txt').write_text(run.stderr)
    passed = run.returncode == 0 and marker.exists() == expected
    if name == 'hardened_roundlane':
        probe = json.loads(run.stdout)
        passed = passed and probe['self_test'] == 'passed' and probe['exam_started'] is False
    results.append({'name': name, 'exit': run.returncode, 'fixture_loaded': marker.exists(), 'expected_loaded': expected, 'passed': passed})
report = {'passed': all(r['passed'] for r in results), 'exam_started': False, 'results': results, 'architecture': os.uname().machine}
(out / 'dyld-results.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
sys.exit(0 if report['passed'] else 1)
