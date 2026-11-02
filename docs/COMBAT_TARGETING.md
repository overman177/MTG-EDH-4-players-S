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
4. Start on another defender and end on the **same attacker** to **add a second, third, or further arrow**. All existing arrows stay visible.
5. Repeating an already-declared defender → attacker gesture **does nothing**. It never removes or overwrites an existing arrow.
6. To remove **one defender's arrows**, briefly press and release the key **without moving the cursor** while hovering that **defender** (as long as that card isn't also an attacker with active arrows). This removes only your own arrows pointing at that card.
7. To remove **every arrow from an attacker**, briefly press and release the key **without moving the cursor** while hovering the **attacker**.
8. Use **Clear my arrows** in General to remove all combat arrows you declared, without removing another player's arrows.

Each attacker can point at multiple defenders. A defender can also be targeted by more than one attacker. Each individual arrow remembers the player who created it, including when different players declare defenders for the same attacker.

**Safety against false deletion:** A key-up event that happens to report the same hovered card as key-down cannot remove arrows unless the world-space cursor moved no more than 0.24 table units. A drag with ambiguous hovered-object data is ignored rather than interpreted as a tap. TTS reports pointer positions separately for the press and release events. If pointer coordinates are unavailable, the operation cannot delete arrows. The arrows are session-only, follow cards when moved, and are removed when the referenced card is destroyed. TTS cards are not tapped, moved, or modified by this feature.

## Implementation boundaries
- Source: `src/lotus/sections/06_combat-targeting.lua` assembled into the original Lotus GUID script.
- Hotkey registration and TTS event dispatch: `src/lotus/sections/07_shared-event-dispatcher.lua`.
- Settings and preferences: `src/lotus/sections/03_edh-settings.lua` and `src/ui/sections/08_lotus-settings.xml`.
- Tracking: `Combat.links[attackerGUID] = {defenders = {[defenderGUID] = playerColor, ...}, by = originalColor}`.
- Drawing: Lotus vector lines, not extra world-space buttons or spawned objects. Existing Lotus vector lines are preserved.
- Updates: once every 0.30 seconds while arrows are present, plus immediately on changes.

## Removed legacy FIGHT artifacts
An older version spawned transparent, temporary world-space AUTOFIGHT anchors, added dynamic private combat report panels, and potentially attached FIGHT buttons to the Lotus object. They are no longer created. On load the new script removes only the tagged **`MTG_Lotus_AutoFightAnchor`** objects, any Lotus buttons with the `MTG_COMBAT_FIGHT:` tooltip prefix, and top-level XML panels with the `MTG_Combat_Fight_Result_` ID prefix. It does not remove unrelated user objects, buttons, XML, or drawing lines.

## Validation
Run `python tools/build.py --check`, `lua5.2 tests/combat_hotkey_test.lua`, and `lua5.2 tests/combat_arrows_test.lua`. These test the Lua source and fake TTS objects. In-game verification is still required for actual vector-line rendering and cursor events.
