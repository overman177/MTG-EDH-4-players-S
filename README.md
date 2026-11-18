# MTG EDH — Tabletop Simulator scripting

**Current scripted release: v1.9.5** (four-player table).

**Maintained source architecture with GUID-safe Smart Import v3 deployment.**

The table's active object scripts live in `live/objects/`, with their original GUID filenames and contents preserved. The tracked `New/` folder is deliberately empty: imports from the six-player table were removed from this four-player repository. `savegame.json` stays at the repository root.

For changes and testing notes, see [v1.9.5 patch notes](docs/RELEASE_NOTES_v1.9.5.md).

## Where to work

| Folder | Purpose |
|---|---|
| `src/global/sections/` | Editable Global.lua sections, **in manifest order** |
| `src/lotus/sections/` | Editable Lotus Helper sections, **in manifest order** |
| `src/ui/sections/` | Editable Global XML UI fragments |
| `src/manifest.json` | Authoritative concatenation order and deployment targets |
| `live/global/` | Existing GUID `Global.-1.lua` + `Global.-1.xml` |
| `live/objects/` | Other GUID-named TTS objects grouped by functionality |
| `New/` | Temporary inbox for newly discovered Smart Import scripts; classify them into `live/objects/` before committing |
| `tools/` | Build, deployment, and GUID inventory validation |
| `docs/` | Architecture and migration/feature guidance |
| `.build/` | Generated non-GUID build outputs (ignored by Git) |

## Register newly added TTS objects

**Add a scripted object to TTS, then use Smart Import > Get Lua Scripts** with this repository root as the workdir. This exports new GUID-named Lua/XML files into `New/`. **Before running UPDATE_TABLE.bat**, double-click **REGISTER_NEW_OBJECTS.bat**.

Registration:
1. Rejects duplicate GUIDs with different contents, and prevents automatic replacement of Global or Lotus source files.
2. Moves new Lua/XML unchanged into appropriate `live/objects/` folders; unknown names go to `unclassified/`.
3. Refreshes `docs/OBJECT_REGISTRY.json` with GUID, name, category and linked script paths.
4. Commits **only those imported scripts and the registry**, then pushes to GitHub `main` so the scripts are accessible for collaboration.

No stashes, backup copies, tag mutations or TTS runtime modifications are made. The command checks that local `main` matches GitHub **before** modifying imports. If it is behind, update first and re-export from TTS; never run the destructive updater while unregistered `New/` exports are present.

**Scriptless props and tags:** Smart Import cannot extract a script that doesn't exist. Export your current TTS table as JSON and register a known GUID with:

```powershell
python tools/register_new_objects.py --apply --publish --save "C:\path\to\current-table.json" --guid abc123
```

For newly scripted objects, supply `--save` (without `--guid`) to include their object type, nickname and tags in the registry. Save-derived metadata is a **snapshot** and does not prove the object's current in-game state. The importer does not assign gameplay tags or integrate callbacks automatically; those require a feature-specific review.

## In-game ornament and boot UI

The One Ring ornament `2d70e1` floats and rotates above The Ring card `d9fcbc`, using the Monarch-style follow animation. The startup banner slides in and fades out, while routine initialization reports go to the TTS console; errors remain visible in chat.

## Combat targeting (Lotus Helper)

In **Table Settings > General**, combat targeting has **two bindable hotkeys**:

- **MTG: Declare Combat Target** (C suggested): hold on the starting card, release on the destination card to **add** an arrow; duplicates never toggle an existing connection.
- **MTG: Undo Combat Target**: **tap and release** to remove your latest surviving arrow; **hold for your chosen duration (1–10 seconds, default 5)** to clear all arrows you created. Other players' arrows are untouched. Your existing Undo binding is preserved.

**Open Game Keys** opens the TTS keybinding dialog, or open **Options > Game Keys** manually. The General tab now has a **per-player Undo hold-duration slider** instead of Undo/Clear buttons. Your setting is saved. Arrows are visual only: no automatic combat result or rules enforcement.

More details: [Combat targeting](docs/COMBAT_TARGETING.md). The hotkey labels remain unchanged to preserve existing bindings; arrows do not assign MTG attacker or defender roles.

## One-click updates (Windows)

Both the 4-player and 6-player repositories use **exactly the same** `UPDATE_TABLE.bat` and `tools/update-and-deploy.ps1`. Double-click the BAT file or use **Terminal > Run Task > MTG: Update from GitHub + Deploy** in VS Code. **After resetting from GitHub, the updater relaunches itself in a fresh PowerShell process** so outdated in-memory code cannot run the remaining steps.

**This is a destructive, one-way download from GitHub.** It does not upload files, create Git stashes, or make backups.

1. `git fetch --prune origin main` downloads the latest GitHub version.
2. `git reset --hard origin/main` discards local changes to tracked files **including `savegame.json`**, and discards unpublished local commits on `main`.
3. `git clean -fd -- New live` deletes untracked files in the two TTS import folders. Legacy `.tts-backups/` and `.tts-smart-backup/` directories are ignored and left untouched; they cannot interrupt the update.
4. `python tools/deploy.py --apply` updates the existing GUID files without making backups.
5. `python tools/build.py --check` and `python tools/audit_objects.py .` verify the result.

Untracked files elsewhere in the repo (such as `.vscode/settings.json`) are not cleaned. Any tracked changes anywhere in the repo are overwritten. The updater does not export the running TTS game; `savegame.json` always comes **from GitHub**, including in the 6-player repository.

**First-time transition:** older local versions of the BAT file still launch the old updater. Before using the BAT for the first time after this change, run the following once in your repository's VS Code terminal:

```powershell
git fetch origin main
git reset --hard origin/main
git clean -fd -- New live
```

After that, double-click `UPDATE_TABLE.bat` for future updates. TTS still requires **Smart Import > Save & Play** to apply scripts in-game.

## Everyday workflow

1. Open **this repository root** in VS Code and set the Smart Import v3 TTS workdir to the **same root**.
2. Edit **source sections** under `src/` for Global, Lotus and Global XML (not `live/`).
3. Preview the assembled scripts: `python tools/build.py`.
4. Review differences versus live GUID files: `git diff` (or `python tools/build.py --check`; this check intentionally fails after real edits).
5. Preview deployment: `python tools/deploy.py`.
6. Deploy to the existing GUID files without backups: `python tools/deploy.py --apply`.
7. Use TTS Lua **Save & Play** only after reviewing changes, testing on a copy of the TTS table.
8. Commit and push the source sections and updated GUID target files together.

When **Get Lua Scripts** imports changes from TTS, the existing GUID-named files update in `live/` by GUID; scripts never seen before land in `New/`. Changes imported into `live/global/` or the Lotus target are **not automatically mirrored into `src/`**: review and reconcile before the next build/deploy to avoid overwriting your TTS-side edits.

## Safety rules

- Do not rename/remove the final `.GUID.lua` / `.GUID.xml` suffixes.
- Do not copy compiled GUID filenames into `src/` or `.build/`. Recursive Smart Import would see duplicates.
- Old ignored `.tts-backups/` and `.tts-smart-backup/` directories are left untouched. They are excluded from GUID auditing, and no new backups are created.
- Keep bundled third-party scripts complete; **do not** replace them with `require("import")`.
- Source sections concatenate **byte-for-byte**; avoid turning them into runtime Lua modules, renaming handlers, or changing their order without testing.
- Git push does not deploy to TTS, and Save & Play does not commit to GitHub.
- The updater does not export the current TTS scene or upload `savegame.json`.

## Validation

```powershell
python tools/audit_objects.py .
python tools/build.py --check
python tools/deploy.py
```

The CI workflow checks duplicate GUIDs and byte-identical reconstruction against the committed live source baseline.

See `docs/ARCHITECTURE.md`, `docs/INTEGRATION.md` and `docs/OBJECT_INVENTORY.md`.
