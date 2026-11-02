# Integrating the live table without data loss

1. Preserve a TTS save backup and copy of the current Smart Import v3 working folder.
2. Run **Get Lua Scripts** on the known-good table. Confirm complete third-party bundled scripts (e.g. importer GUID `222541`) are present.
3. Check Git status before and after the import. Do not run Save & Play until files and GUIDs reconcile.
4. Commit the imported scripts in their **current relative paths**, keeping `Name.GUID.lua` and matching XML together. Do not rename GUID suffixes.
5. Detect duplicate GUIDs; resolve only after examining which object is authoritative.
6. Capture a baseline for Global, Lotus and UI. Compare their hashes against the known-good TTS save before migrating them into `src/`.
7. In a separate change, split the verified baseline into ordered source sections and verify byte-identical reconstruction.
8. Only after the build matches a known-good baseline, test deploy on a cloned TTS save. Check shortcuts, settings, previews, equipment, context menus, patch notes and importer behavior.
9. Commit tested changes to main; preserve rollback commits.

## Git and TTS are separate

Git commit/push backs up versioned code. Smart Import reads or sends scripts to TTS. A git push does not deploy to TTS, and Save & Play does not push to GitHub.

## Where to keep generated output

Keep generated scripts in a separate ignored `.build/` directory. When deploying, overwrite only the existing GUID-matched target files *with backup*, rather than allowing a second `Global.-1.lua` or Lotus GUID script to be scanned by Smart Import.

## Bundled third-party scripts

Treat existing luabundle output as opaque runtime code unless all component modules are available. Never overwrite a complete bundle with a bare `require("import")` entrypoint.
