# Architecture proposal (non-destructive)

## Runtime boundaries

1. **Global.lua** is the table-wide script and contains the master event callbacks.
2. **MTG Lotus Helper** is a separate TTS object script; do not merge its event handlers into Global.
3. **Global UI.html** is global XML UI. Callbacks must continue to resolve to their existing TTS owners.
4. **Other objects** keep their current GUID-suffixed names and folder locations.

## Proposed layout

```text
src/
  global/    # ordered sections of Global.lua
  lotus/     # ordered sections of the Lotus Helper
  ui/        # ordered sections of Global UI.html
objects/     # other TTS GUID-named scripts (after live inventory)
New/         # incoming GUID objects from Smart Import v3
tools/       # build, audit and validation
docs/        # architecture, API contracts and test plans
```

**The source sections are not independent runtime Lua modules.** Initially concatenate them exactly in the original order, retaining lexical scope and callback registration. Do not introduce `require()` or change event dispatching until TTS regression tests exist.

## Feature areas

Global: zone resolution; player/seat state; shortcuts; mulligans; board reset; pregame flow; commander helpers; turns; card entry; land/fetchland systems; counters; context menus; Scryfall; chat; patch notes; settings.

Lotus: per-player previews; playmats; random draw; settings; equipment; reveal-top clones; TTS event dispatcher.

UI: deck/importer panels; reveal tools; Scryfall; patch notes; general and host settings; bug reports; Lotus settings.

## Source of truth

`src/` should eventually own the three central scripts; generated GUID target files must be deployed only after verification. Objects not yet migrated remain managed directly by Smart Import v3.

**Do not bulk reorganize or overwrite the live GUID files from this scaffold.** The current GitHub repository did not contain a committed object inventory when this branch was made.
