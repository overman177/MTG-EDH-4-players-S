# Black Lotus anti-worm guard (report-only)

Both 4-player and 6-player tables include a non-destructive Global Lua monitor in
`src/global/sections/39_security-guard.lua`. The guard is included in
`src/manifest.json` and the built GUID-bound `live/global/Global.-1.lua`.

## Behavior

- A very light initial scan runs in small batches after loading. Only scripts with worm-like capabilities are reported.
- `onObjectSpawn` and `onObjectStateChange` check newly visible objects.
- Normal scans keep `getObjects()` inspection for real decks and bags. Known Black Lotus keyword dispensers and utility props are exempt from that method by GUID/name because TTS rejects the call on them. Their own Lua remains inspected. `security deep scan` uses `getData()` to inspect nested contents, including those of exempt props, when explicitly requested.
- Official bundled GUIDs are exempted from heuristic warnings. GUID presence is not cryptographic verification.
  Their scripts are compared against the first code observed during that session.
- Only high-signal script replacement, remote-code execution, and script-bearing spawn patterns are reported. Innocuous unknown scripts are not counted as infections.
- **No objects are deleted, locked, modified, reloaded, or quarantined.**
  A finding is a warning, not proof of malware. No card names are broadcast.
- The built-in `scryfall <card>` command validates downloaded JSON *before*
  spawning it, blocking non-Card/Deck payloads or JSON with embedded Lua/UI.
  Valid card JSON is spawned byte-for-byte as before, preserving DFC states.
- Type `security scan` in chat for a lightweight manual scan; `security deep scan` performs slower recursive checks. A summary
  is sent privately to the requesting seat. To avoid abuse, scans have a short
  cooldown.
- To run the offline regression tests: `lua5.2 tests/security_guard_test.lua`.

## Limitations

This is a **heuristic detector**, not a sandbox or client-side antivirus.
TTS may execute an imported object's `onLoad` before `onObjectSpawn` detects it;
objects imported through third-party scripts are **not** pre-sanitized by this
guard. A malicious host can edit/disable Global or forge the reports.

Official GUID membership is not cryptographic authentication. Known bundled scripts are not hashed against a release manifest. The scanner is heuristic and may miss obfuscated worms.
Future work: release-pinned script hashes, third-party importer hardening, and
removing automatic player promotions and unrestricted third-party updater commands.

For live safety, test on a copy of the saved table first. This code should not
change gameplay rules, counters, hand zones, playmats, or other object behavior.
