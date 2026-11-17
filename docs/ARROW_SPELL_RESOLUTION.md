# Manual-stack arrow spell resolution — 4-player test patch

**No stack engine, no priority engine and no automated casting.** Players handle
casting costs, responses and spell-card movement as usual.

## Workflow

1. Spawn [Swords to Plowshares](https://scryfall.com/search?q=%21%22Swords%20to%20Plowshares%22),
   [Oblivion Strike](https://scryfall.com/search?q=%21%22Oblivion%20Strike%22),
   [Lightning Bolt](https://scryfall.com/search?q=%21%22Lightning%20Bolt%22),
   and [Serra Angel](https://scryfall.com/search?q=%21%22Serra%20Angel%22).
2. Keep the spell physically on the table, wherever you manually manage spells.
3. Use the existing keybind to draw an **outgoing arrow from the spell** to
   the creature it will affect.
4. A green **RESOLVE** button appears **below the card**, not in the screen UI.
   It only appears for supported *instant/sorcery* spells with outgoing arrows.
5. After opponents respond and you agree to resolve, click RESOLVE.
   Only the clicked player's arrows *starting on that spell* count.
   Other incoming arrows, other source cards, and the target registry's
   older committed sessions cannot change this spell's targets.
6. On success the resolving player's outgoing arrows on that one source
   disappear; the **spell card stays in place** for manual movement to its
   owner's graveyard/exile afterward.

## Initial supported handlers

| Card | Target | Automated result |
|---|---|---|
| Swords to Plowshares (instant) | Exactly 1 battlefield creature | Exile creature to **owner's** exile; target's **controller** gains life equal to its **current encoded power** (minimum 0) |
| Oblivion Strike (sorcery) | Exactly 1 battlefield creature | Exile creature to owner's exile |
| Lightning Bolt (instant) | Exactly 1 battlefield creature | Add 3 to state service's marked damage; **players handle damage prevention, state-based lethal damage and triggered effects** |

Other instants/sorceries remain **manual** until a trusted handler exists.
Player/planeswalker/battle targets for Lightning Bolt are not supported yet:
there are no player-target arrows and no planeswalker/battle damage/loyalty
handling in this patch.

## Important limitations and safeguards

- No automatic **stack, priority, mana payment, timing or targeting decisions**.
- A button click is a player's decision to execute the supported effect.
- The card's type must be identified as instant or sorcery by local metadata.
- Only targets identified by **live outbound arrows** qualify. The Global
  effect API independently verifies those arrows via the Lotus helper.
- The resolving player's arrows only. Mixed-player arrows from the same
  source are rejected rather than silently changing other players' targets.
- Multi-target arrows are supported as visual links but current handlers require
  exactly one creature; additional arrows block auto-resolution.
- Targets must be face-up creatures on a battlefield, with known owner/controller.
- Known hexproof, protection, ward, shroud and likely commander/replacement
  cases are intentionally blocked for manual resolution. This is **not**
  a complete Magic target-legality or continuous-effects engine.
- Commander zone replacement, prevention, damage modifiers, other replacements,
  protection from colored sources, and temporary power/toughness layers require
  player judgment. The displayed current power uses existing Encoder data.
- Existing life trackers gained two small callable methods; no card is
  re-encoded, no custom card scripts are overwritten, and no generic
  `setLuaScript` is executed.
- The Resolve button is attached to the spell object using
  `createButton`, and removal uses a unique click function/tooltip; it
  never calls `clearButtons()` on existing encoded cards.
- UI reconciliation piggybacks on the existing arrow refresh loop; no new
  periodic whole-table scans. A bounded **one-time** load cleanup prevents
  buttons saved from an earlier play session surviving with no arrows.
- A successful resolution consumes the relevant arrows; clicking twice
  without new arrows does not apply an effect twice.
- The spell card itself is **never automatically moved**. Players handle
  its post-resolution destination and anything not explicitly handled.

## Regression tests

```sh
lua5.2 tests/arrow_spell_resolution_test.lua
python tools/build.py --check
```

Tests include: source-only targeting, unsupported/no-arrow cases, wrong-arrow
owner, exact count, correct exile owner vs controller life gain, marked
damage, sorcery handling, button cleanup, retaining unrelated Encoder buttons,
and preventing forged target GUIDs.

**Please test in TTS before using for real games**; GitHub CI mocks the TTS
card and life-tracker APIs and cannot verify 3D button placement or movement.
