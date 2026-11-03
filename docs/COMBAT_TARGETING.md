# Lotus combat arrows

Combat targeting is a **visual-only** feature inside the existing Lotus Helper. No damage calculation, FIGHT/AUTOFIGHT button, or combat-result UI is installed.

## Controls

In **Table Settings → General**, players can enable combat targeting, open the TTS **Game Keys** dialog, **Undo last arrow**, or **Clear my arrows**. Configure three bindable game hotkeys in **Options → Game Keys**:

- **MTG: Declare Combat Target** (C suggested): Hold over a **defender**, move to an **attacker**, release. Adds one arrow. Repeating the same pair is harmless.
- **MTG: Remove Combat Target**: Hold over the **defender**, move to the **attacker**, release. Removes only that exact connection and only if you created it.
- **MTG: Undo Combat Target**: Press once to remove the most recently added still-existing arrow belonging to you. The General-tab **Undo last arrow** button performs the same action.

One attacker can have multiple defenders, and one defender can connect to multiple attackers. Each arrow remembers its creating player. A plain key tap, invalid target or duplicate gesture **never removes any arrow**. **Clear my arrows** removes only the player's own connections.

The **Open Game Keys** button calls the official TTS `showHotkeyConfig()` with no arguments. If a client's game window does not open the dialog, it can be opened manually through **Options → Game Keys**. Physical keys cannot be assigned by Lua.

## Implementation

- Combat source: `src/lotus/sections/06_combat-targeting.lua`
- UI: `src/lotus/sections/03_edh-settings.lua` (migrates General tab to `v151`)
- Callbacks: `src/lotus/sections/07_shared-event-dispatcher.lua`
- Storage: `Combat.links[attackerGUID].defenders[defenderGUID] = ownerColor`
- Rendering: Lotus vector lines, preserving existing lines; arrows follow cards every 0.3 seconds
- Undo: per-player session history, skipping arrows already removed
- Cleanup: deleting a card removes its arrows; legacy AUTOFIGHT anchors/buttons/reports are removed on load

## Validation

Run `python tools/build.py --check`, `lua5.2 tests/combat_hotkey_test.lua`, and `lua5.2 tests/combat_arrows_test.lua`. These are mocked Lua tests, not an in-game verification. Validate actual multiplayer key events and the visual rendering in TTS before publishing.
