#!/usr/bin/env python3
"""Read-only inventory of GUID-named TTS scripts. No writes to the project."""
from collections import defaultdict
from pathlib import Path
import argparse
import re

GUID = re.compile(r"\.([0-9a-fA-F]{6}|-1)\.(lua|xml)$", re.IGNORECASE)
SKIP = {".git", "node_modules", ".build", ".tts-backups", ".tts-smart-backup"}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path, help="Live Smart Import workdir")
    args = parser.parse_args()
    root = args.directory.resolve()
    if not root.is_dir():
        parser.error(f"Not a directory: {root}")
    index = defaultdict(list)
    for file in root.rglob("*"):
        if not file.is_file() or any(part in SKIP for part in file.relative_to(root).parts):
            continue
        match = GUID.search(file.name)
        if match:
            index[(match.group(1).lower(), match.group(2).lower())].append(file.relative_to(root))
    duplicates = 0
    for (guid, ext), paths in sorted(index.items()):
        print(f"{guid}.{ext}: {', '.join(str(p) for p in paths)}")
        if len(paths) > 1:
            duplicates += 1
            print("  WARNING: duplicate GUID and extension")
    print(f"GUID-linked entries: {len(index)}; duplicate identities: {duplicates}")
    raise SystemExit(1 if duplicates else 0)

if __name__ == "__main__":
    main()
