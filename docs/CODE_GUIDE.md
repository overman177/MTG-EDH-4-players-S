# Reading the MTG EDH table code

Start in `src/`, not the large deployable scripts in `live/`. Each numbered section is a piece of one shared Lua or XML file, not a separately loaded module. `src/manifest.json` specifies the exact concatenation order.

| To change... | Start here |
| --- | --- |
| Player seats, GUIDs and zone tags | Global section 00 |
| Card types, mana value and printed keywords | Global section 00a |
| Draw, untap, mill, scry and numbered shortcuts | Global sections 01 and 22–25 |
| Opening hands and board reset | Global sections 03–06 |
| Land counts and fetchlands | Global sections 14 and 19 |
| Context actions, card ownership and cascade | Global sections 28–29 |
| Spawner and imports | Global sections 30–31 |
| Global player and host preferences | Global sections 33–37 |
| Card previews, artwork and random draw | Lotus sections 00–02 |
| Counter visibility, preview options and settings | Lotus section 03 |
| Equipment | Lotus section 04 |
| Always Reveal Top | Lotus section 05 |
| Arrows and keybinds | Lotus section 06 |
| TTS event routing and Lotus XML callbacks | Lotus section 07 |
| UI controls and layouts | `src/ui/sections/` |

## Important implementation details

- A GUID identifies a physical TTS object, not a permanent identity for a printed Magic card. A merge or reload can invalidate object references; keep the existing delayed-callback guards.
- Zones use role and seat tags. Cards need not match those tags. Global's occupancy reconciliation compensates for native zone events that TTS may skip.
- Metadata and card-specific helpers are not a complete rules engine. Unknown metadata stays unknown; players resolve unsupported interactions manually.
- The top-card preview is a temporary visual, never a real gameplay card. Do not include it in a draw, shuffle or search. Keep the collision and lifecycle safeguards.
- Arrows are visual links only. Historical attacker/defender variable names mean start/destination.
- XML IDs and callback names are contracts between the UI and Lua. A GUID-prefixed callback invokes an object script instead of Global. Do not copy GUID mappings between table variants.
- Global and Lotus have separate saved state. Preserve old-save compatibility unless deliberately migrating it.

## Other object scripts

The individual physical-object scripts live under `live/objects/`: automation, counters and trackers, commander, game mechanics, interface, mana, zones and hands, utilities, and third-party integrations. Use `docs/OBJECT_INVENTORY.md` and `docs/OBJECT_REGISTRY.json` to locate a script by GUID. Similar counters often repeat the same implementation for different seats. The folders describe purpose, not original authorship; preserve attribution and licensing.

## Edit and verify

Edit source sections first, run `python tools/deploy.py --apply` to regenerate the matching live files, and run `python tools/build.py --check` to verify assembly. The repository tests cover fragile interactions, but in-game testing is still needed for functional changes. The preserved `savegame.json` is not a source file in this build system.

This comment-only pass does not change gameplay or the release version.
