#!/usr/bin/env python3
"""Classify freshly exported TTS GUID scripts and publish a searchable registry.

Exports arrive in New/ from Smart Import > Get Lua Scripts. This tool never
executes Lua, changes GUIDs, injects tags, or modifies the in-game TTS scene.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GUID_FILE = re.compile(r"^(.+)\.([0-9a-fA-F]{6}|-1)\.(lua|xml)$", re.I)
COLORS = re.compile(r"\[(?:[0-9A-Fa-f]{6}|-)?\]|\[/?b\]", re.I)
REGISTRY = Path("docs/OBJECT_REGISTRY.json")


def guid_file(path):
    hit = GUID_FILE.fullmatch(path.name)
    return (hit.group(1), hit.group(2).lower(), hit.group(3).lower()) if hit else None


def friendly(name):
    return COLORS.sub("", name).strip() or name


def classify(name):
    n = friendly(name).casefold()
    if "counter" in n or "life tracker" in n or "radiation helper" in n:
        return "counters-and-trackers"
    if "commander zone" in n or "commander" in n and "zone" in n:
        return "commander"
    if "mana" in n and not "manager" in n:
        return "mana"
    if any(s in n for s in ("tokenzone", "highlight mat", "hand zone", "battlefield zone", "scripting zone")):
        return "zones-and-hand"
    if any(s in n for s in ("encoder", "importer", "tyrantnomad", "rikrassen", "darbs")):
        return "third-party"
    if any(s in n for s in ("timer", "swapper", "promoter", "promoted access")):
        return "automation"
    if any(s in n for s in ("monarch", "phasing", "morph", "planechase", "dungeon", "the ring", "goes first", "day/night", "pirate cannon", "is it a token", "crowns", "wilderness", "undercity")):
        return "game-mechanics"
    if any(s in n for s in ("notecard", "notepad", "instructions", "hold alt", "menu", "keywords", "scry")):
        return "interface"
    if "custom tile" in n:
        return "utilities"
    return "unclassified"


def scan(root, folder):
    directory = root / folder
    result = {}
    if not directory.exists():
        return result
    for path in sorted(directory.rglob("*")):
        if not path.is_file():
            continue
        identity = guid_file(path)
        if identity is None:
            continue
        label, guid, ext = identity
        key = (guid, ext)
        if key in result:
            raise ValueError(f"Duplicate GUID {guid}.{ext}: {result[key]} and {path}")
        result[key] = path
    return result


def read_metadata(save_path, guids):
    if save_path is None:
        return {}
    with save_path.open(encoding="utf-8-sig") as stream:
        scene = json.load(stream)
    if not isinstance(scene, dict) or not isinstance(scene.get("ObjectStates"), list):
        raise ValueError("Not a valid TTS save (ObjectStates missing)")
    found = {}
    pending = list(scene["ObjectStates"])
    while pending and len(found) < len(guids):
        obj = pending.pop()
        if not isinstance(obj, dict):
            continue
        guid = str(obj.get("GUID", "")).lower()
        if guid in guids and guid not in found:
            found[guid] = {
                "tts_type": str(obj.get("Name", "")),
                "nickname": str(obj.get("Nickname", "")),
                "tags": [str(x) for x in (obj.get("Tags") or []) if isinstance(x, str)],
                "metadata_source": save_path.name,
            }
        pending.extend(obj.get("ContainedObjects") or [])
        states = obj.get("States") or {}
        if isinstance(states, dict):
            pending.extend(v for v in states.values() if isinstance(v, dict))
    return found


def prepare(root, requested_guids=()):
    existing = scan(root, "live")
    incoming = scan(root, "New")
    requested = {g.lower() for g in requested_guids}
    if any(not re.fullmatch(r"[0-9a-f]{6}", g) for g in requested):
        raise ValueError("--guid must be a six-character hexadecimal TTS GUID")
    actions = []
    for (guid, ext), source in sorted(incoming.items()):
        name, _, _ = guid_file(source)
        if guid == "-1":
            raise ValueError(f"Global script {source} must be reconciled with src/ manually")
        if "lotus helper" in friendly(name).casefold() and (guid, ext) not in existing:
            raise ValueError(f"New Lotus Helper {source} needs a manifest/source review")
        if (guid, ext) in existing:
            original = existing[(guid, ext)]
            if source.read_bytes() != original.read_bytes():
                raise ValueError(f"GUID {guid}.{ext} already exists at {original}, but contents differ; reconcile manually")
            actions.append(("duplicate", source, original))
            continue
        other = existing.get((guid, "xml" if ext == "lua" else "lua"))
        category = other.parent.name if other else classify(name)
        destination = root / "live" / "objects" / category / source.name
        if destination.exists():
            raise ValueError(f"Destination exists: {destination}")
        actions.append(("move", source, destination))
    return actions, requested


def make_registry(root, manual_guids=(), metadata=None):
    metadata = metadata or {}
    paths = scan(root, "live")
    previous = root / REGISTRY
    existing_manual = {}
    if previous.is_file():
        doc = json.loads(previous.read_text(encoding="utf-8"))
        existing_manual = {o["guid"]: o for o in doc.get("objects", []) if o.get("manual")}
    objects = {}
    for (guid, ext), file in sorted(paths.items()):
        name, _, _ = guid_file(file)
        item = objects.setdefault(guid, {
            "guid": guid, "name": friendly(name),
            "category": "global" if file.is_relative_to(root / "live" / "global") else file.parent.name,
            "files": {},
        })
        item["files"][ext] = {"path": file.relative_to(root).as_posix(),
                               "bytes": file.stat().st_size}
        if guid in metadata:
            item["savegame"] = metadata[guid]
    for guid, item in existing_manual.items():
        if guid not in objects:
            objects[guid] = item
    for guid in manual_guids:
        if guid not in objects:
            if guid not in metadata:
                raise ValueError(f"GUID {guid} not present in supplied savegame; cannot register scriptless object")
            objects[guid] = {"guid": guid, "name": metadata[guid]["nickname"] or guid,
                             "category": "scriptless", "files": {}, "manual": True,
                             "savegame": metadata[guid]}
    return json.dumps({"schema": 1, "description": "Index of TTS GUID scripts; savegame metadata is a snapshot, not live table state.",
                       "objects": [objects[g] for g in sorted(objects)]},
                      ensure_ascii=False, indent=2) + "\n"


def git(root, *args):
    result = subprocess.run(["git", *args], cwd=root, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"git {' '.join(args)} failed:\n{result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def preflight_publish(root):
    if git(root, "branch", "--show-current") != "main":
        raise ValueError("Publication requires checked-out main branch")
    if git(root, "diff", "--cached", "--name-only"):
        raise ValueError("Clear unrelated staged changes before publishing; no existing staged files will be committed")
    git(root, "fetch", "origin", "main")
    if git(root, "rev-parse", "HEAD") != git(root, "rev-parse", "origin/main"):
        raise ValueError("Local main differs from GitHub. Sync before importing; do not run UPDATE_TABLE.bat with unregistered New/ scripts")


def register(root, apply=False, publish=False, save=None, guids=()):
    if publish and not apply:
        raise ValueError("--publish requires --apply")
    if publish:
        preflight_publish(root)
    actions, requested = prepare(root, guids)
    if requested and save is None:
        raise ValueError("--guid requires --save pointing to a freshly exported TTS save")
    target_guids = set(requested) | {guid_file(src)[1] for _, src, _ in actions}
    metadata = read_metadata(save, target_guids)
    missing = requested - metadata.keys()
    if missing:
        raise ValueError("GUID(s) not found in savegame: " + ", ".join(sorted(missing)))
    for operation, source, dest in actions:
        print(f"{operation.upper()}: {source.relative_to(root)} -> {dest.relative_to(root)}")
    if not apply:
        print("Dry run only. Use --apply to organize; --apply --publish to commit and push.")
        return 0

    changed = []
    for operation, source, dest in actions:
        if operation == "move":
            dest.parent.mkdir(parents=True, exist_ok=True)
            source.rename(dest)
            changed.append(dest.relative_to(root).as_posix())
        else:
            source.unlink()
        # Register removed incoming paths too, if they were ever tracked.
        if subprocess.run(["git", "ls-files", "--error-unmatch", "--", str(source.relative_to(root))],
                          cwd=root, capture_output=True).returncode == 0:
            changed.append(source.relative_to(root).as_posix())
    index = make_registry(root, requested, metadata)
    index_path = root / REGISTRY
    index_path.parent.mkdir(parents=True, exist_ok=True)
    if not index_path.is_file() or index_path.read_text(encoding="utf-8") != index:
        index_path.write_text(index, encoding="utf-8")
        changed.append(REGISTRY.as_posix())
    if publish and changed:
        git(root, "add", "-A", "--", *sorted(set(changed)))
        # preflight_publish guarantees no unrelated paths were staged.
        git(root, "commit", "-m", "Register TTS objects and refresh GUID registry")
        git(root, "push", "origin", "main")
        print("Published new object scripts and registry to GitHub main.")
    elif publish:
        print("No changes to publish.")
    else:
        print("Local registration complete; publish to GitHub to make the files available for review.")
    print(f"Registry: {REGISTRY.as_posix()} ({len(json.loads(index)['objects'])} GUIDs)")
    if not actions and not requested:
        print("No new GUID scripts found in New/. Scriptless props require a current savegame and --guid.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Move incoming scripts and write the registry")
    parser.add_argument("--publish", action="store_true", help="Commit and push only registered objects and registry")
    parser.add_argument("--save", type=Path, help="Optional freshly exported TTS savegame for nickname, type, and tags")
    parser.add_argument("--guid", action="append", default=[], help="Register a scriptless object by GUID (requires --save)")
    parser.add_argument("--root", type=Path, default=ROOT, help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        return register(args.root.resolve(), args.apply, args.publish, args.save, args.guid)
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
