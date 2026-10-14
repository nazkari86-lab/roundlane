#!/usr/bin/env python3
"""Mutate one disposable resource while the real signed app monitors it; no kiosk."""
import json
from pathlib import Path
import subprocess
import sys
import time

kit = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve()
if app != kit / 'setup' / 'Roundlane-hardened-candidate.app':
    raise SystemExit('Only the named disposable development candidate may be tested')
out = kit / 'setup' / 'mac-hardened-tests'
out.mkdir(exist_ok=True)
report = out / 'live-monitor-results.json'
ready = Path(str(report) + '.ready')
for marker in (report, ready):
    marker.unlink(missing_ok=True)
resource = app / 'Contents/Resources/Roundlane/starter.cpp'
original = resource.read_bytes()
process = subprocess.Popen([str(app / 'Contents/MacOS/Roundlane'), '--roundlane-monitor-check', str(report)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
try:
    deadline = time.monotonic() + 15
    while not ready.exists():
        if process.poll() is not None:
            raise RuntimeError('Real guard did not reach healthy monitoring state')
        if time.monotonic() >= deadline:
            raise TimeoutError(f'Monitor readiness timeout; live child PID {process.pid}')
        time.sleep(0.02)
    if ready.read_text() != 'monitor-ready':
        raise RuntimeError('Unexpected readiness marker')
    resource.write_bytes(original + b'\n// controlled live-monitor resource mutation\n')
    stdout, stderr = process.communicate(timeout=15)
    (out / 'live-monitor-stdout.txt').write_text(stdout)
    (out / 'live-monitor-stderr.txt').write_text(stderr)
    result = json.loads(report.read_text())
    if process.returncode != 0 or result['passed'] is not True or result['exam_started'] is not False or result['kiosk_started'] is not False:
        raise RuntimeError('Live guard/quarantine/password diagnostic failed')
    if 'Invalid application signature/resources' not in result['reason']:
        raise RuntimeError('Mutation was not rejected by the real resource-signature verifier')
finally:
    resource.write_bytes(original)
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=5)
restored = resource.read_bytes() == original
subprocess.run(['codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app)], check=True)
healthy = subprocess.run([str(app / 'Contents/MacOS/Roundlane'), '--roundlane-integrity-check'], capture_output=True, text=True, timeout=15, check=True)
health = json.loads(healthy.stdout)
assert restored and health['passed'] is True and health['exam_started'] is False
(out / 'live-monitor-restored.json').write_text(json.dumps({'passed': True, 'resource_restored': restored, 'healthy_guard': health, 'child_exit': process.returncode, 'exam_started': False}, indent=2) + '\n')
print(json.dumps({'passed': True, 'real_resource_mutation_detected': True, 'resource_restored': restored, 'kiosk_started': False}, indent=2))
