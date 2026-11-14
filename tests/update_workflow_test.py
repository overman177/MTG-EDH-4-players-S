#!/usr/bin/env python3
"""Regression checks for the shared one-way, no-backup TTS updater."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
bat = (ROOT / "UPDATE_TABLE.bat").read_text(encoding="utf-8")
ps = (ROOT / "tools/update-and-deploy.ps1").read_text(encoding="utf-8")
deploy = (ROOT / "tools/deploy.py").read_text(encoding="utf-8")

assert r"tools\update-and-deploy.ps1" in bat
for required in (
    "git fetch --prune origin main",
    "git reset --hard origin/main",
    "git clean -fd -- New live",
    "python tools/deploy.py --apply",
    "python tools/build.py --check",
    "python tools/audit_objects.py .",
):
    assert required in ps, required

for forbidden in (r"&\s*git\s+stash\b", r"&\s*git\s+push\b",
                  r"&\s*git\s+pull\b", r"\bCopy-Item\b",
                  r"\bMove-Item\b"):
    assert not re.search(forbidden, ps, flags=re.IGNORECASE), forbidden

assert "savegame.json" not in ps or "git reset --hard origin/main" in ps
# Historical backups are ignored, not traversed or deleted by the updater.
assert "Remove-Item" not in ps
assert "Get-ChildItem" not in ps
assert "git clean -fd -- New live" in ps
assert "backup_root" not in deploy
assert "shutil.copy" not in deploy
assert "datetime" not in deploy
assert "os.replace(temp, target)" in deploy
print("Shared one-way updater and no-backup deployment checks passed.")
