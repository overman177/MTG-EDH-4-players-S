#!/usr/bin/env python3
"""Deploy built Global, Lotus and XML files to their existing GUID locations.

Safety:
- Dry run unless --apply is supplied.
- Rebuilds source first.
- Creates a timestamped backup of every changed target OUTSIDE the repo.
- Never creates a second GUID script path.
- No TTS or GitHub communication; use Smart Import Save & Play afterwards.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

from build import build, ROOT, MANIFEST, OUTPUT

def deploy(apply=False):
    if build() != 0:
        return 1
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    updates = []
    for item in manifest["files"]:
        target = ROOT / item["target"]
        source = OUTPUT / item["output"]
        if not target.is_file():
            print("ERROR: GUID target is missing: " + str(target), file=sys.stderr)
            return 2
        if target.read_bytes() != source.read_bytes():
            updates.append((item["id"], target, source))
    if not updates:
        print("All live targets already match the assembled sources.")
        return 0
    for system, target, _ in updates:
        print(("APPLY" if apply else "DRY RUN") + ": " + system + " -> " + str(target.relative_to(ROOT)))
    if not apply:
        print("No live files changed. Run: python tools/deploy.py --apply")
        return 0
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    # Smart Import v3 recursively scans the project directory for GUID scripts.
    # Keep deploy backups OUTSIDE that directory to avoid duplicate GUIDs.
    backup_root = ROOT.parent / (ROOT.name + "-backups") / stamp
    for system, target, source in updates:
        backup = backup_root / target.relative_to(ROOT)
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, backup)
        fd, temp = tempfile.mkstemp(prefix=".tts-deploy-", dir=target.parent)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(source.read_bytes())
            os.replace(temp, target)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
        print("Updated " + system + " (backup: " + str(backup) + ")")
    print("Deployment complete. Review diff before running TTS Save & Play.")
    return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Update GUID targets after writing backups")
    args = parser.parse_args()
    sys.exit(deploy(args.apply))
