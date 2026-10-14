#!/usr/bin/env python3
"""Bounded, VM-like safety guard for this exact disposable local rehearsal."""
import datetime
import json
import os
from pathlib import Path
import signal
import subprocess
import time

kit=Path(__file__).resolve().parent.parent
work=kit/'setup/mac-observer-rehearsal-20261013'
exe=str(work/'Roundlane Observer Rehearsal.app/Contents/MacOS/Roundlane')
def matching(pid=None):
    result=[]
    for line in subprocess.check_output(['ps','-axo','pid=,command='],text=True).splitlines():
        parts=line.strip().split(maxsplit=1)
        if len(parts)==2 and parts[1]==exe and (pid is None or int(parts[0])==pid):
            result.append(int(parts[0]))
    return result
targets=matching()
assert len(targets)==1,targets
pid=targets[0]
started=datetime.datetime.now(datetime.timezone.utc).isoformat()
report=work/'watchdog-state.json'
state=dict(pid=pid,executable=exe,started_utc=started,maximum_seconds=900,
           normal_exit=False,forced_timeout_exit=False,autostart_installed=False)
report.write_text(json.dumps(state,indent=2)+'\n')
deadline=time.monotonic()+900
while matching(pid) and time.monotonic()<deadline:
    time.sleep(2)
if matching(pid):
    state['forced_timeout_exit']=True
    os.kill(pid,signal.SIGTERM)
    for _ in range(10):
        if not matching(pid):break
        time.sleep(1)
    if matching(pid):os.kill(pid,signal.SIGKILL)
else:
    state['normal_exit']=True
state['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
report.write_text(json.dumps(state,indent=2)+'\n')
print(json.dumps(state))
