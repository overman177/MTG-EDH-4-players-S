# Lotus combat arrows

Combat targeting is a **visual-only** feature inside the existing Lotus Helper. No damage calculation, FIGHT/AUTOFIGHT button, or combat-result UI is installed.

## Controls

In **Table Settings → General**, players can enable combat targeting, open the TTS **Game Keys** dialog, **Undo last arrow**, or **Clear my arrows**. Configure **two bindable game hotkeys** in **Options → Game Keys**:

- **MTG: Declare Combat Target** (C suggested): Hold over a **defender**, move to an **attacker**, release. Adds one arrow. Repeating the same pair is harmless.
- **MTG: Undo Combat Target**: **Tap and release** to undo your most recently added still-existing arrow. **Hold for 5 seconds** to clear **all of your own arrows**; the long hold does not also undo a single arrow. The General-tab **Undo last arrow** button still performs an immediate single undo.

One attacker can have multiple defenders, and one defender can connect to multiple attackers. Each arrow remembers its creating player. A tap, invalid target or duplicate **Draw** gesture never removes an arrow. **Short Undo** removes only the player's most recent remaining arrow. **Long Undo (5 seconds)** clears all arrows owned by the holding player. The **Clear my arrows** button remains available without a hotkey.

The **Open Game Keys** button calls the official TTS `showHotkeyConfig()` with no arguments. If a client's game window does not open the dialog, it can be opened manually through **Options → Game Keys**. Physical keys cannot be assigned by Lua.

## Implementation

- Combat source: `src/lotus/sections/06_combat-targeting.lua`
- UI: `src/lotus/sections/03_edh-settings.lua` (migrates General tab to `v153`)
- Callbacks: `src/lotus/sections/07_shared-event-dispatcher.lua`
- Storage: `Combat.links[attackerGUID].defenders[defenderGUID] = ownerColor`
- Rendering: Lotus vector lines, preserving existing lines; arrows follow cards every 0.3 seconds
- Undo: per-player session history, skipping arrows already removed; a 5-second hold is tracked separately for each player via TTS key-down, key-up, and Wait.time; clearing cancels the hold and resets that player's history
- Cleanup: deleting a card removes its arrows; legacy AUTOFIGHT anchors/buttons/reports are removed on load

## Validation

Run `python tools/build.py --check`, `lua5.2 tests/combat_hotkey_test.lua`, and `lua5.2 tests/combat_arrows_test.lua`. These are mocked Lua tests, not an in-game verification. Validate actual multiplayer key events and the visual rendering in TTS before publishing.
