#!/usr/bin/env python3
"""Deploy built Global, Lotus, and XML to their existing TTS GUID targets.

Dry run unless --apply is specified. Changes are written atomically in place,
without creating backups or introducing duplicate GUID-named files.
"""
import argparse
import json
import os
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
        print(("APPLY" if apply else "DRY RUN") + ": " + system +
              " -> " + str(target.relative_to(ROOT)))
    if not apply:
        print("No live files changed. Run: python tools/deploy.py --apply")
        return 0

    for system, target, source in updates:
        fd, temp = tempfile.mkstemp(prefix=".tts-deploy-", dir=target.parent)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(source.read_bytes())
            os.replace(temp, target)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
        print("Updated " + system + " (no backup)")
    print("Deployment complete. Run TTS Smart Import / Save & Play to apply.")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="Write built scripts to existing GUID targets")
    args = parser.parse_args()
    sys.exit(deploy(args.apply))
