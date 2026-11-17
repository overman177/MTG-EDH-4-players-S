# Four-player card state v1 — Encoder-backed

**Experimental, read-only on inspection.** The 6-player table is not changed.
Pull the 4-player table, use `UPDATE_TABLE.bat`, and Smart Import > Save & Play.

## Inspect a card

Hover a face-up card and type **`mtg state`** in chat. The result includes:

- **Owner:** write-once GM Notes `owner` from library, hand, commander zone, or
  an owner's graveyard; fallback to Encoder's `tyrantUnified.ownerColor` when
  no GM Notes owner is available. An owner's exile zone is not proof of
  ownership: cards can be exiled by opponents.
- **Controller:** defaults to owner when known and remains unchanged when
  cards move onto a different playmat. An explicit effect API is the sole way
  the new state layer changes it. The result may legitimately be unknown.
- **Zone:** current zone/zone seat, reported separately from control.
- **P/T:** reads current, already-encoded Unified module data
  (`_MTG_Simplified_UNIFIED` / `tyrantUnified`).
  `currentPower = numeric basePower + power adjustment + plusOneCounters`;
  same for toughness. Uses the selected face; optionally falls back to
  already-cached remote card data. Symbolic P/T (e.g. *) stays unknown.
  **Not** a Magic continuous-effect/layer engine.
- **Counters:** Unified `plusOneCounters` and `namedCounters`
  (loyalty/defense, when the active face specifies one), `πCounter`'s
  `picounter`, stun, suspend/time and all numerical Encoder value IDs
  containing `counter` (under `counters.encodedById`).
  Printed +1/+1 counters are not double counted.
- **Keywords/statuses:** `πKeywords` numbers/booleans, including flying,
  hexproof, indestructible, vigilance, frozen and exerted. Printed keywords
  are supplied separately; a dynamically granted ability not represented in
  Encoder cannot be inferred.
- **Tapped:** inferred from TTS card Y rotation; **damage** is the explicit
  engine-tracked amount (unknown if not recorded). Tapped state is not inferred
  from an Encoder keyword.
- **Summoning sickness:** tracked conservatively from observed battlefield
  entries, explicit control changes, and the start of the controller's turn.
  May be `nil` when history is unavailable. Haste is reported separately.
- **Cast history:** explicit effect events only, not the last player who
  physically moved the card. Last mover / previous zone are diagnostic fields.
- **Identity:** name, card types, mana value, print keywords, Scryfall IDs when
  known. Face-down queries do not reveal information.

The module uses the existing Encoder **read-only** API; it never auto-encodes
cards, toggles Encoder props, or polls all cards every frame.

## Scripting interfaces

```lua
local s = Global.call("mtgCardState", {guid = card.getGUID()})
-- s.owner, s.controller, s.zone, s.zoneColor, s.currentPower,
-- s.currentToughness, s.counters.plusOnePlusOne,
-- s.counters.named, s.counters.encodedById, s.encodedKeywords, s.statuses,
-- s.damageMarked, s.tapped, s.summoningSick, s.lastCastBy
```

**Only effects should write controller/cast/damage**, with nonempty `effectId`.
These functions do not grant spell legitimacy or verify an effect actually
resolved; that is the responsibility of the later spell/stack engine.

```lua
Global.call("mtgSetCardController", {
    guid=card.getGUID(), controller="Red", effectId="spell-effect-123"
})
Global.call("mtgRecordSpellCast", {
    guid=card.getGUID(), caster="White", fromZone="Exile",
    effectId="spell-cast-124"
})
Global.call("mtgSetCardDamage", {
    guid=card.getGUID(), damage=3, effectId="damage-125"
})
```

The controller update mirrors Encoder's `controllerColor` **only when that
property is already enabled**; GM Notes ownership never changes. If the
Encoder/controller display is manually changed, the authoritative state is
unaffected. Zone movement cannot change controller.

State history is saved with Global player settings and restored on reload.
Damage recorded by this module is cleared no later than the next turn start.
The engine does **not** track physical dice, temporary layer effects,
perpetual effects, zone-change object identity, or effects expiring at
end of turn. Such facts must not be treated as known when unrecorded.

## Mock regression

```sh
lua5.2 tests/card_state_test.lua
python tools/build.py --check
```

The test exercises live Encoder data reads, modified P/T, encoded counters,
GM Notes ownership versus wrong-playmat location, explicit control changes,
turn-based readiness, cast/damage records, persistence, and hidden-card safety.
Live TTS verification is still required before any automatic resolution.
