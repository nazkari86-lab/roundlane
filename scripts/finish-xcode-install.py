#!/usr/bin/env python3
"""Finish the authorized Xcode installation after Apple's xip process exits."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wait-for-pid", type=int, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    report = root / "docs/xcode-installation-2026-10-09.json"
    result = {"status": "waiting_for_signed_archive_expansion",
              "assessment_app_built": False, "assessment_session_started": False}
    report.write_text(json.dumps(result, indent=2) + "\n")
    while True:
        try:
            os.kill(args.wait_for_pid, 0)
        except ProcessLookupError:
            break
        time.sleep(10)
    source = root / "setup/Xcode.app"
    target = Path("/Applications/Xcode.app")
    try:
        version = plistlib.loads((source / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
        if version != "26.2":
            raise ValueError(f"Unexpected Xcode version: {version}")
        verification = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(source)],
                                      capture_output=True, text=True)
        if verification.returncode:
            raise ValueError("Xcode signature verification failed: " + verification.stderr[-2000:])
        if target.exists():
            raise FileExistsError("Existing /Applications/Xcode.app preserved; install not replaced")
        shutil.move(str(source), str(target))
        probe = subprocess.run([str(target / "Contents/Developer/usr/bin/xcodebuild"), "-version"],
                               capture_output=True, text=True, timeout=120)
        result.update(status="installed_signature_verified", path=str(target),
                      version=version, version_command_exit_code=probe.returncode,
                      version_command_output=(probe.stdout + probe.stderr).strip())
        launch = subprocess.run([str(target / "Contents/Developer/usr/bin/xcodebuild"), "-checkFirstLaunchStatus"],
                                capture_output=True, text=True, timeout=120)
        result.update(first_launch_ready=launch.returncode == 0,
                      first_launch_output=(launch.stdout + launch.stderr).strip())
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        result.update(status="installation_incomplete", error=str(error))
    report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)
    return 0 if result["status"] == "installed_signature_verified" else 1


if __name__ == "__main__":
    raise SystemExit(main())
