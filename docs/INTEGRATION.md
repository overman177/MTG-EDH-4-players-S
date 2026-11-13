# Git, TTS and deployment

## Initial one-time setup
1. Clone the repository or pull the architecture branch into your current scripts folder.
2. In VS Code open the repository root and select it as Smart Import v3 workdir.
3. The TTS game and the Git repository are separate. Updating scripts does not save the running TTS scene.
4. Run `python tools/build.py --check` to ensure the source sections reconstruct the corresponding live GUID scripts.
5. Run `python tools/audit_objects.py .` to check for duplicate GUID-target scripts.

## Editing Global, Lotus and UI
1. Edit `src/global/sections/`, `src/lotus/sections/` or `src/ui/sections/`.
2. `python tools/build.py` assembles into `.build/`, using names without GUIDs.
3. `python tools/deploy.py` previews the changed targets.
4. `python tools/deploy.py --apply` updates existing GUID scripts in place without backups.
5. Run Save & Play in TTS and review errors and regressions before committing.
6. Commit both `src/` changes and resulting `live/` changes to GitHub.

## Editing other objects
Edit their GUID-named file directly in `live/objects/`. Third-party bundles should remain untouched unless deliberately repaired.

## Get Lua Scripts
New TTS object GUIDs are imported to `New/`. Move reviewed objects into functional folders. Existing GUIDs update in place through Smart Import. If Global or Lotus was changed inside TTS, reconcile the updated live code with source sections **before redeploying** or the TTS edits may be overwritten.

## Recovery
GitHub history retains previously committed versions. `UPDATE_TABLE.bat` intentionally discards local tracked edits, unpublished `main` commits, and untracked TTS files in `New/` and `live/`. The updater and deploy tool do not create backups or stashes.
