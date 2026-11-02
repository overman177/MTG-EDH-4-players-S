# MTG EDH — Tabletop Simulator scripting

Version-controlled scripting project for the four-player MTG EDH table.

> **Repository status:** initialized with an architecture scaffold. The complete live TTS GUID-indexed object scripts have not yet been uploaded here. Do not use this repository to overwrite your live table until the complete source is reconciled.

## Architecture

- `src/global/`: ordered source sections for `Global.lua` (one TTS Lua environment).
- `src/lotus/`: ordered source sections for the Lotus Helper object (separate TTS Lua environment).
- `src/ui/`: source sections for Global XML UI.
- `tools/`: reproducible assembly, inventory, and validation tools.
- `docs/`: architecture, integration and safety guidance.
- `objects/` and `New/`: GUID-suffixed object scripts managed by Smart Import v3, once imported from a **verified** TTS table.

**Do not turn the ordered sections into separate runtime `require()` modules.** Their lexical scoping and TTS event handlers currently depend on the assembled file. A successful assembly should be byte-for-byte identical to the source snapshot until refactoring is deliberately tested.

See the `architecture/initial-source-layout` branch for the proposed directory architecture and automation. The default branch remains a safe repository initialization until source and live GUIDs are reviewed.
