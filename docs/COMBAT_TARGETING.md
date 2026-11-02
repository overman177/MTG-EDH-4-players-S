# Lotus combat arrows

Combat targeting is a **visual-only** feature inside the existing Lotus Helper. No combat damage calculation, FIGHT/AUTOFIGHT button, or damage-result UI is installed.

## Controls
In **Table Settings → General**, players can:
- Enable or disable combat targeting for their seat (enabled by default).
- Open **Configure key (C suggested)** to assign the **MTG: Declare Combat Target** game hotkey in TTS. A physical default key cannot be set by Lua; each client must assign its own binding.
- Use **Clear my arrows** to remove their own declarations without changing another player's arrows.

### Defender-first gesture
1. Hover a **defending card** and **hold** the combat hotkey.
2. Move the pointer to the **attacking card**.
3. **Release** the hotkey: Lotus draws an arrow from that attacker to that defender.
4. Repeat this exact defender → attacker gesture to remove **that single arrow**.
5. Start on a different defender and end on the same attacker to **add another defender**, keeping the existing arrows.
6. Press and release the hotkey while hovering the **attacker itself** to remove **all defenders for that attacker**.

Each attacker can point at multiple defenders. A defender can also be targeted by more than one attacker. The arrows are session-only, follow cards when moved, and are removed when the referenced card is destroyed. TTS cards are not tapped, moved, or modified by this feature.

## Implementation boundaries
- Source: `src/lotus/sections/06_combat-targeting.lua` assembled into the original Lotus GUID script.
- Hotkey registration and TTS event dispatch: `src/lotus/sections/07_shared-event-dispatcher.lua`.
- Settings and preferences: `src/lotus/sections/03_edh-settings.lua` and `src/ui/sections/08_lotus-settings.xml`.
- Tracking: `Combat.links[attackerGUID] = {defenders = {[defenderGUID] = true, ...}, by = playerColor}`.
- Drawing: Lotus vector lines, not extra world-space buttons or spawned objects. Existing Lotus vector lines are preserved.
- Updates: once every 0.30 seconds while arrows are present, plus immediately on changes.

## Removed legacy FIGHT artifacts
An older version spawned transparent, temporary world-space AUTOFIGHT anchors, added dynamic private combat report panels, and potentially attached FIGHT buttons to the Lotus object. They are no longer created. On load the new script removes only the tagged **`MTG_Lotus_AutoFightAnchor`** objects, any Lotus buttons with the `MTG_COMBAT_FIGHT:` tooltip prefix, and top-level XML panels with the `MTG_Combat_Fight_Result_` ID prefix. It does not remove unrelated user objects, buttons, XML, or drawing lines.

## Validation
Run `python tools/build.py --check`, `lua5.2 tests/combat_hotkey_test.lua`, and `lua5.2 tests/combat_arrows_test.lua`. These test the Lua source and fake TTS objects. In-game verification is still required for actual vector-line rendering and cursor events.
