# MTG EDH — Tabletop Simulator scripting

**Maintained source architecture with GUID-safe Smart Import v3 deployment.**

The table's imported object scripts have been organized from `New/` into functional folders. Existing TTS GUID filenames and Lua/XML contents are preserved. `savegame.json` remains at the repository root.

## Where to work

| Folder | Purpose |
|---|---|
| `src/global/sections/` | Editable Global.lua sections, **in manifest order** |
| `src/lotus/sections/` | Editable Lotus Helper sections, **in manifest order** |
| `src/ui/sections/` | Editable Global XML UI fragments |
| `src/manifest.json` | Authoritative concatenation order and deployment targets |
| `live/global/` | Existing GUID `Global.-1.lua` + `Global.-1.xml` |
| `live/objects/` | Other GUID-named TTS objects grouped by functionality |
| `New/` | Only objects not yet classified after Smart Import |
| `tools/` | Build, deployment, and GUID inventory validation |
| `docs/` | Architecture and migration/feature guidance |
| `.build/` | Generated non-GUID build outputs (ignored by Git) |

## Combat targeting (Lotus Helper)

In **Table Settings > General**, combat targeting has **two bindable hotkeys**:

- **MTG: Declare Combat Target** (C suggested): hold on defender, release on attacker to **add** an arrow; duplicates never toggle an existing connection.
- **MTG: Undo Combat Target**: **tap and release** to remove your latest surviving arrow; **hold for your chosen duration (1–10 seconds, default 5)** to clear all arrows you created. Other players' arrows are untouched. Your existing Undo binding is preserved.

**Open Game Keys** opens the TTS keybinding dialog, or open **Options > Game Keys** manually. The General tab now has a **per-player Undo hold-duration slider** instead of Undo/Clear buttons. Your setting is saved. Arrows are visual only: no automatic combat result or rules enforcement.

More details: [Combat targeting](docs/COMBAT_TARGETING.md).

## One-click updates (Windows)

Once the latest files are on your PC, **double-click `UPDATE_TABLE.bat`** in the repository root. Or in VS Code choose **Terminal > Run Task > MTG: Update from GitHub + Deploy**. The updater:

1. Moves any old `.tts-backups/` folder outside the repository to stop Smart Import duplicate GUID errors.
2. Stashes local code edits and new files safely, while keeping `savegame.json`, `.vscode/settings.json` and incoming `New/` files in place.
3. Runs `git pull --ff-only origin main`.
4. Runs `python tools/deploy.py --apply` and `python tools/build.py --check`.
5. Stops with an error if any step fails. It never force-resets or deletes your code.

After a successful update, **Smart Import > Save & Play** in TTS is still required; the launcher cannot click inside TTS.

**First-time setup when your current `git pull` is blocked:** run these commands once in the VS Code terminal to fetch the launcher safely:

```powershell
git stash push -u -m "Before one-click updater" -- . ":(exclude)savegame.json" ":(exclude).vscode/settings.json" ":(exclude)New/**"
git pull --ff-only origin main
```

Your stashed edits are **preserved**, not automatically reapplied. In particular, do not blindly `git stash pop` old GUID scripts over the new code. To review them, run `git stash list`. The updater will show a notice when it creates a new stash. Personal `savegame.json`, `.vscode/settings.json` and `New/` files stay on disk; if a remote change would overwrite them, pull stops safely instead.

## Everyday workflow

1. Open **this repository root** in VS Code and set the Smart Import v3 TTS workdir to the **same root**.
2. Edit **source sections** under `src/` for Global, Lotus and Global XML (not `live/`).
3. Preview the assembled scripts: `python tools/build.py`.
4. Review differences versus live GUID files: `git diff` (or `python tools/build.py --check`; this check intentionally fails after real edits).
5. Preview deployment: `python tools/deploy.py`.
6. Deploy with automatic backups **outside the repository**, in its sibling `MTG-EDH-4-players-S-backups/` directory: `python tools/deploy.py --apply`.
7. Use TTS Lua **Save & Play** only after reviewing changes, testing on a copy of the TTS table.
8. Commit and push the source sections and updated GUID target files together.

When **Get Lua Scripts** imports changes from TTS, the existing GUID-named files update in `live/` by GUID; scripts never seen before land in `New/`. Changes imported into `live/global/` or the Lotus target are **not automatically mirrored into `src/`**: review and reconcile before the next build/deploy to avoid overwriting your TTS-side edits.

## Safety rules

- Do not rename/remove the final `.GUID.lua` / `.GUID.xml` suffixes.
- Do not copy compiled GUID filenames into `src/` or `.build/`. Recursive Smart Import would see duplicates.
- **Never keep `.lua` GUID backup copies under the repository root.** Smart Import v3 discovers scripts recursively even in Git-ignored directories such as `.tts-backups/`. If old `.tts-backups/` exists, move it to a sibling folder outside the project before using Smart Import.
- Keep bundled third-party scripts complete; **do not** replace them with `require("import")`.
- Source sections concatenate **byte-for-byte**; avoid turning them into runtime Lua modules, renaming handlers, or changing their order without testing.
- Git push does not deploy to TTS, and Save & Play does not commit to GitHub.
- Backup your table save before changing or deploying scripts.

## Validation

```powershell
python tools/audit_objects.py .
python tools/build.py --check
python tools/deploy.py
```

The CI workflow checks duplicate GUIDs and byte-identical reconstruction against the committed live source baseline.

See `docs/ARCHITECTURE.md`, `docs/INTEGRATION.md` and `docs/OBJECT_INVENTORY.md`.
