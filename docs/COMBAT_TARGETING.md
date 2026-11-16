# Lotus combat arrows

Combat targeting is a **visual-only** feature inside the existing Lotus Helper. No damage calculation, FIGHT/AUTOFIGHT button, or combat-result UI is installed.

## Controls

In **Table Settings → General**, players can enable targeting, open the TTS **Game Keys** dialog, and set their personal **Hold Undo to clear all arrows** slider from **1 to 10 seconds** (default **5 seconds**). The setting persists with table settings and is independent for each seat. There are no separate Undo/Clear action buttons. Configure **two bindable game hotkeys** in **Options → Game Keys**:

- **MTG: Declare Combat Target** (C suggested): Hold over the **starting card**, move to the **destination card**, then release. The arrow points from start to finish. Adds one arrow. Repeating the same pair is harmless.
- **MTG: Undo Combat Target**: **Tap and release** to undo your most recently added still-existing arrow. **Hold for your configured duration (1–10 seconds)** to clear **all of your own arrows**; the long hold does not also undo a single arrow. Duration is sampled when pressing the key, so changes take effect on the next hold.

Any card can be the start or destination of multiple arrows; the gesture alone determines the arrow direction. Each arrow remembers its creating player. A tap, invalid target or duplicate **Draw** gesture never removes an arrow. **Short Undo** removes only the player's most recent remaining arrow. **Long Undo (configured duration)** clears all arrows owned by the holding player.

The **Open Game Keys** button calls the official TTS `showHotkeyConfig()` with no arguments. If a client's game window does not open the dialog, it can be opened manually through **Options → Game Keys**. Physical keys cannot be assigned by Lua.

**Old hotkey cleanup:** TTS has no API to unregister one named hotkey. Lotus calls `clearHotkeys()` before registering its two combat actions on load so the former **MTG: Remove Combat Target** row disappears. This resets the table's *custom* hotkey registry, not native TTS controls. The current table's Game Keys list contains only Lotus combat custom actions; if future mods add their own `addHotkey` actions, they must register them after this cleanup.

## Implementation

- Combat source: `src/lotus/sections/06_combat-targeting.lua`
- UI: `src/lotus/sections/03_edh-settings.lua` (migrates General tab to `v154`)
- Callbacks: `src/lotus/sections/07_shared-event-dispatcher.lua`
- Storage: `Combat.links[startGUID].defenders[destinationGUID] = ownerColor` (historic field names retained for compatibility)
- Rendering: Lotus vector lines from start to destination, preserving existing lines; arrows follow cards every 0.3 seconds
- Undo: per-player session history, skipping arrows already removed; a per-seat configurable hold is tracked via TTS key-down, key-up, and Wait.time; clearing resets the hold/history and suppresses keyboard-repeat until key release
- Preferences: `Settings.combatUndoHoldSecondsByColor` saved in the Lotus settings state, clamped to integer seconds in the range 1–10
- Cleanup: deleting a card removes its arrows; legacy AUTOFIGHT anchors/buttons/reports are removed on load

## Validation

Run `python tools/build.py --check`, `lua5.2 tests/combat_hotkey_test.lua`, and `lua5.2 tests/combat_arrows_test.lua`. These are mocked Lua tests, not an in-game verification. Validate actual multiplayer key events and the visual rendering in TTS before publishing.
