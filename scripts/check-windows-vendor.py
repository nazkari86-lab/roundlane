#!/usr/bin/env python3
"""Fail closed when bundled dependency bytes differ from audited vendor files."""
import hashlib
import json
import sys
from pathlib import Path

kit = Path(__file__).resolve().parents[1]
vendor = kit / "win-app/dependencies"
manifest = json.loads((vendor / "manifest.json").read_text())
signatures = json.loads((kit / "setup/bundle-check/vendor-signatures.json").read_text(encoding="utf-8-sig"))
for item in manifest:
    if "--native" in sys.argv and item["file"].startswith("SEB_"):
        continue
    path = (kit if item["file"].startswith("SEB_") else vendor) / item["file"]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert digest == item["sha256"], f"Dependency hash changed: {path}"
    entry = next(s for s in signatures if s["Name"] == item["file"])
    assert entry["Status"] == "Valid", f"Vendor signature is not valid: {path}"
    assert entry["SHA256"].lower() == digest, f"Signature checked different bytes: {path}"
print("Bundled vendor hashes and Authenticode signatures verified")
