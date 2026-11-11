# Black Lotus anti-worm guard (report-only)

Both 4-player and 6-player tables include a non-destructive Global Lua monitor in
`src/global/sections/39_security-guard.lua`. The guard is included in
`src/manifest.json` and the built GUID-bound `live/global/Global.-1.lua`.

## Behavior

- An initial, batched scan starts after the table has loaded.
- `onObjectSpawn` and `onObjectStateChange` check newly visible objects.
- The monitor reads Lua scripts and recursively inspects serialized
  `ContainedObjects` and `States`, to identify scripted deck cards and
  alternate states.
- Official bundled object GUIDs are exempted from **unexpected-script** warnings.
  Their scripts are compared against the first code observed during that session.
- Unknown scripts are reported, with indicators such as `setLuaScript`,
  `script_code =`, `spawnObjectJSON`, and `WebRequest`.
- **No objects are deleted, locked, modified, reloaded, or quarantined.**
  A finding is a warning, not proof of malware. No card names are broadcast.
- The built-in `scryfall <card>` command validates downloaded JSON *before*
  spawning it, blocking non-Card/Deck payloads or JSON with embedded Lua/UI.
  Valid card JSON is spawned byte-for-byte as before, preserving DFC states.
- Type `security scan` in TTS chat to trigger a fresh batched scan; a summary
  is sent privately to the requesting seat. To avoid abuse, scans have a short
  cooldown.
- To run the offline regression tests: `lua5.2 tests/security_guard_test.lua`.

## Limitations

This is a **heuristic detector**, not a sandbox or client-side antivirus.
TTS may execute an imported object's `onLoad` before `onObjectSpawn` detects it;
objects imported through third-party scripts are **not** pre-sanitized by this
guard. A malicious host can edit/disable Global or forge the reports.

Official GUID membership is not cryptographic authentication. A script already
modified before the initial scan may be accepted as the session baseline.
Future work: release-pinned script hashes, third-party importer hardening, and
removing automatic player promotions and unrestricted third-party updater commands.

For live safety, test on a copy of the saved table first. This code should not
change gameplay rules, counters, hand zones, playmats, or other object behavior.
