#!/usr/bin/env python3
"""Verify the official Windows ISO before making it available for VM setup."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time

EXPECTED = "dbf606ceb4ce1390f9f21ad1d96331848bc6b701cbab0012785881a1a1c0ec63"
SOURCE = "https://www.microsoft.com/en-us/software-download/windows11arm64"
# Values published in the hash table on SOURCE, checked 2026-10-09.
# These are reference row names, not a claim about the image's actual UI locale.
REFERENCE_HASHES = {
    "English 64-bit": EXPECTED,
    "Arabic 64-bit": "8992f2d2cfd2fa647e579e9eb31fc21f34da8333c29b6170fde17d2ed6623e9c",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--wait-for-pid", type=int)
    parser.add_argument("--reference-row", choices=REFERENCE_HASHES, default="English 64-bit",
                        help="Published Microsoft hash-table row; verify image locale separately")
    args = parser.parse_args()
    expected = REFERENCE_HASHES[args.reference_row]
    report = args.image.parent / "windows-image-verification.json"
    result = {"source": SOURCE, "expected_sha256": expected, "hash_reference_row": args.reference_row,
              "status": "waiting_for_download", "vm_installed": False}
    report.write_text(json.dumps(result, indent=2) + "\n")
    if args.wait_for_pid:
        while True:
            try:
                os.kill(args.wait_for_pid, 0)
            except ProcessLookupError:
                break
            time.sleep(10)
    digest = hashlib.sha256()
    try:
        with args.image.open("rb") as stream:
            for data in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                digest.update(data)
        result["sha256"] = digest.hexdigest()
        result["bytes"] = args.image.stat().st_size
        if digest.hexdigest() != expected:
            raise ValueError("ISO SHA-256 does not match Microsoft's published value")
        target = args.image.with_suffix("") if args.image.suffix == ".part" else args.image
        if target != args.image:
            if target.exists():
                raise FileExistsError(f"Verified target already exists: {target}")
            args.image.rename(target)
        result.update(status="sha256_verified", image=str(target.resolve()))
    except (OSError, ValueError) as error:
        result.update(status="verification_failed", error=str(error))
    report.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result), flush=True)
    return 0 if result["status"] == "sha256_verified" else 1


if __name__ == "__main__":
    raise SystemExit(main())
