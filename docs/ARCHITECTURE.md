# Actual table architecture

This repository uses **two layers**:

- `src/`: human-editable ordered sections of the central Global Lua, Lotus Helper Lua and Global XML UI. `src/manifest.json` owns section ordering and target mapping.
- `live/`: real GUID-suffixed TTS object files, scanned recursively by Smart Import v3.

Additional new scripts are placed in `New/` until categorized. `savegame.json` is a preserved TTS save snapshot; editing the saved JSON is **not** part of this build system.

## Boundaries

**Global / live/global/Global.-1.lua**
- Player seats, turn flow, commander zones, counters, table buttons
- Land tracking, fetchlands, zone logic, preview and context menus
- Scryfall tools, chat, settings, UI callback handlers and patch notes

**Lotus Helper / live/objects/lotus-helper/**
- Card previews, playmats, random draw, personal settings
- Equipment actions and reveal-top clone visuals

**Global UI / live/global/Global.-1.xml**
- Context panels, Scryfall, importer controls, patch notes
- Player, host, Lotus settings and shortcuts overlay

**Other objects / live/objects/** are classified by role: counters-and-trackers, commander, mana, zones-and-hand, automation, interface, game-mechanics, utilities and third-party. A folder is an **organizational category, not evidence of original authorship**.

## Source section contract

The first refactor is intentionally **lossless concatenation**, not independent module loading. The resulting Global Lua and Lotus Lua remain single TTS Lua environments with shared locals and existing event handlers. XML is assembled as concatenated top-level fragments, matching the original TTS UI payload.

Use `python tools/build.py --check` to verify the baseline. Build outputs use plain `Global.lua`, `LotusHelper.lua` and `Global.xml` to avoid duplicate GUID identities.

When a legitimate source change is made, `--check` will report that it differs from the deployed live code. Run `python tools/deploy.py --apply` to update the original GUID target, with backups, then test with TTS.

## Work not yet automated

- Sync-back from edited live files to `src/` sections
- Runtime TTS integration and UI/zone interaction testing
- Object metadata/tag verification against `savegame.json`
- Automatic upstream third-party script refresh

These are deliberate boundaries to avoid silent gameplay regressions.
