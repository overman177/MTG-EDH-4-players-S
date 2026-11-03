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

In **Table Settings > General**, combat targeting has three independent controls:

- **MTG: Declare Combat Target** (C suggested): hold on defender, release on attacker to **add** an arrow; duplicates never toggle an existing connection.
- **MTG: Remove Combat Target**: **press once anywhere** to clear all arrows you created. Other players' arrows are untouched. Existing bindings are preserved.
- **MTG: Undo Combat Target**: removes your latest surviving arrow. The **Undo last arrow** button also works without binding another hotkey.

**Open Game Keys** opens the TTS keybinding dialog, or open **Options > Game Keys** manually. The **Clear my arrows** button performs the same action as the Remove key. Arrows are visual only: no automatic combat result or rules enforcement.

More details: [Combat targeting](docs/COMBAT_TARGETING.md).

## Everyday workflow

1. Open **this repository root** in VS Code and set the Smart Import v3 TTS workdir to the **same root**.
2. Edit **source sections** under `src/` for Global, Lotus and Global XML (not `live/`).
3. Preview the assembled scripts: `python tools/build.py`.
4. Review differences versus live GUID files: `git diff` (or `python tools/build.py --check`; this check intentionally fails after real edits).
5. Preview deployment: `python tools/deploy.py`.
6. Deploy with automatic backups: `python tools/deploy.py --apply`.
7. Use TTS Lua **Save & Play** only after reviewing changes, testing on a copy of the TTS table.
8. Commit and push the source sections and updated GUID target files together.

When **Get Lua Scripts** imports changes from TTS, the existing GUID-named files update in `live/` by GUID; scripts never seen before land in `New/`. Changes imported into `live/global/` or the Lotus target are **not automatically mirrored into `src/`**: review and reconcile before the next build/deploy to avoid overwriting your TTS-side edits.

## Safety rules

- Do not rename/remove the final `.GUID.lua` / `.GUID.xml` suffixes.
- Do not copy compiled GUID filenames into `src/` or `.build/`. Recursive Smart Import would see duplicates.
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
