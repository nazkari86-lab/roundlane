#!/usr/bin/env python3
"""Build a local observer rehearsal copy; restore production source afterwards."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

kit=Path(__file__).resolve().parent.parent
work=kit/'setup/mac-observer-rehearsal-20261013'
work.mkdir(exist_ok=True)
source=kit/'upstream/seb-mac/OtherSources/RoundlaneBootstrap.m'
original=source.read_bytes()
before=hashlib.sha256(original).hexdigest()
text=original.decode()
old='settings[@"allowSwitchToApplications"] = @NO;'
assert text.count(old)==1
replacement='''// LOCAL OBSERVER REHEARSAL ONLY. Never included in the contest release.
    settings[@"allowSwitchToApplications"] = @YES;
    settings[@"roundlaneObserverRehearsal"] = @YES;
    settings[@"autoQuitApplications"] = @NO;
    NSMutableArray *observerApps = [NSMutableArray arrayWithArray:settings[@"permittedProcesses"] ?: @[]];
    for (NSString *bundleID in @[@"com.openai.codex", @"com.openai.sky.CUAService", @"com.openai.sky.CUAService.guardian"]) {
        [observerApps addObject:@{@"active":@YES, @"os":@0, @"identifier":bundleID,
            @"title":@"Rehearsal observer", @"runInBackground":@YES,
            @"allowAccessibility":@YES, @"allowNetworkAccess":@YES}];
    }
    settings[@"permittedProcesses"] = observerApps;'''
text=text.replace(old,replacement)
test='&& ![settings[@"allowSwitchToApplications"] boolValue]'
assert text.count(test)==1
text=text.replace(test,'&& [settings[@"allowSwitchToApplications"] boolValue]')
(work/'RoundlaneBootstrap-observer.m').write_text(text)
env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
try:
    source.write_text(text)
    with (work/'build.log').open('w') as log:
        subprocess.run([env['DEVELOPER_DIR']+'/usr/bin/xcodebuild',
            '-workspace',str(kit/'upstream/seb-mac/SafeExamBrowser.xcworkspace'),
            '-scheme','Safe Exam Browser','-configuration','Debug',
            '-destination','generic/platform=macOS','-derivedDataPath',str(kit/'setup/seb-mac-build'),
            '-disableAutomaticPackageResolution','-jobs','2',
            'CODE_SIGNING_ALLOWED=NO','ENABLE_DEBUG_DYLIB=NO',
            'ARCHS=arm64 x86_64','ONLY_ACTIVE_ARCH=NO',
            'PRODUCT_BUNDLE_IDENTIFIER=local.roundlane.observer-rehearsal','build'],
            env=env,stdout=log,stderr=subprocess.STDOUT,check=True)
    app=work/'Roundlane Observer Rehearsal.app'
    assert not app.exists(),'Preserve an existing rehearsal build'
    subprocess.run(['ditto',str(kit/'setup/seb-mac-build/Build/Products/Debug/Roundlane.app'),str(app)],check=True)
    (app/'Contents/Helpers').mkdir(exist_ok=True)
    shutil.copy2(kit/'setup/Roundlane-hardened-candidate.app/Contents/Helpers/contest-hub-server',app/'Contents/Helpers/contest-hub-server')
    subprocess.run(['bash',str(kit/'scripts/sign-native-mac.sh'),str(app)],env=env,check=True)
    for flag,name in [('--self-test','self-test'),('--roundlane-integrity-check','integrity-check')]:
        result=subprocess.run([str(app/'Contents/MacOS/Roundlane'),flag],capture_output=True,text=True,check=True,timeout=30)
        (work/(name+'.json')).write_text(result.stdout)
    (work/'build-verification.json').write_text(json.dumps(dict(
        app=str(app),observer_exception_only_in_local_copy=True,
        app_switching_relaxed=True,strict_app_switch_blocking_verified=False,
        production_source_sha256=before,production_source_restored=True,
        published_archive_modified=False,exam_started=False),indent=2)+'\n')
    print(str(app))
finally:
    source.write_bytes(original)
    assert hashlib.sha256(source.read_bytes()).hexdigest()==before
