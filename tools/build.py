#!/usr/bin/env python3
"""Assemble ordered source sections without altering any live GUID files.

Default output is .build/ with NON-GUID filenames, so the Smart Import v3
recursive scanner will never confuse generated outputs with live TTS scripts.
"""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "src" / "manifest.json"
OUTPUT = ROOT / ".build"

def build(check=False):
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    failures = 0
    for item in manifest["files"]:
        chunks = []
        for relative in item["parts"]:
            path = ROOT / relative
            if not path.is_file():
                raise FileNotFoundError("Missing source section: " + relative)
            chunks.append(path.read_bytes())
        combined = b"".join(chunks)
        target = ROOT / item["target"]
        output = OUTPUT / item["output"]
        output.write_bytes(combined)
        matches = target.is_file() and target.read_bytes() == combined
        print(item["id"] + ": " + str(len(item["parts"])) +
              " sections -> " + output.relative_to(ROOT).as_posix() +
              (" [matches live]" if matches else " [DIFFERS FROM LIVE]"))
        if check and not matches:
            failures += 1
    if check and failures:
        print(str(failures) + " output(s) differ from live files", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Require assembled output to be byte-identical to live code")
    args = parser.parse_args()
    sys.exit(build(args.check))
