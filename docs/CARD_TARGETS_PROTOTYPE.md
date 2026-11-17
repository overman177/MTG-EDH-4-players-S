# 4-player MTG card catalog + targeting prototype

This is **testing infrastructure**, not a Magic rules engine. It never casts
spells, moves cards, modifies counters, or auto-resolves abilities. The current
combat/visual arrow hotkeys are unchanged. The six-player table is unchanged.

## In-game test workflow

1. Pull the 4-player repo, deploy the GUID files, and run Smart Import **Save & Play**.
2. Use `scryfall Lightning Bolt`, `scryfall Swords to Plowshares`,
   `scryfall Llanowar Elves`, and `scryfall Serra Angel` to spawn cards.
   The existing `scryfall <name>` command is unchanged.
3. Hover over a **face-up** card and type `mtg inspect` in chat.
   The Lua Global catalog looks up the exact printed name in the MTGA
   read-only API. If absent/unavailable, it tries Scryfall. Results are sent
   privately to the requesting color, with source (`mtga`/`scryfall`).
   Repeating a lookup uses an in-memory cache. No requests are made on hover.
4. Two supported workflows:
   - **Draw first:** draw arrows from Comet Storm to Llanowar Elves and
     Serra Angel. Hover the **source OR either destination**, then type
     `mtg target`. The helper identifies your most recent matching arrow
     group and imports **both** targets in drawing order.
   - **Start first:** type `mtg target` before drawing any arrows. The
     **first arrow** establishes the source automatically; additional arrows
     from the same source register more targets. You no longer have to
     hover the correct source while typing the command.
5. Type `mtg targets` to review your **draft** selection. After each
   recorded gesture the helper also reports the target count privately.
   Tap the existing Undo hotkey: the last draft target should disappear.
6. Type `mtg done` to commit. Record its `target-N` ID.
   Undo/clear the visual arrows, then type `mtg targets` again:
   the committed target remains registered. Type `mtg cancel`
   instead of `mtg done` to discard the current draft only.
7. A different seated player can draw arrows without changing your selection.
   Destroying a committed target leaves its ID in the record but marks it
   `valid=false`; no automatic target revalidation or game action occurs.
8. Type `mtg help` for command instructions.

## Public scripting interface

Global (read-only local metadata + remote on-demand cache):

- `Global.call("mtgCardCatalogRequest", {guid="abcdef",color="White"})`:
  returns `{status,localData,remote}` immediately; response may be
  `pending`. Passing a valid seat color also prints remote results privately
  on completion. `remote` only exists for `ready`.
- `Global.call("mtgCardCatalogGet", {guid="abcdef"})`:
  checks memory without initiating a network request.
- Underlying `Global.call("mtgCardMetadata", {guid="abcdef"})`
  remains unchanged.

Lotus (GUID `185063`; no automatic link-to-target semantics outside a session):

- `lotus.call("mtgBeginTargetSelection", {color="White",sourceGUID="abcdef"})`
- `lotus.call("mtgReadTargetSelection", {color="White"})` for draft/latest,
  or `{id="target-N"}` for a committed selection.
- `lotus.call("mtgFinishTargetSelection", {color="White"})` commits.
- `lotus.call("mtgCancelTargetSelection", {color="White"})` discards a draft.

A committed record has an independent ID, ordered targets and validity flags.
Links are session-only, as before. After Save & Play, active and committed
selection records are reset intentionally. GUIDs are TTS object identities,
not stable Oracle identities.

## Limits and guardrails

- Remote metadata is **not** executable spell/ability behavior. The MTGA API
  may return multiple printings; this prototype prefers primary,
  non-rebalanced, non-token, nondigital records for an exact name. It does
  **not** establish a unique printing ID or resolve split/DFC face identity.
- The catalog lookup is name-based and explicitly refuses face-down cards.
  Never use this interface to inspect an opponent's hidden game information.
- At most three active remote lookups; 24 waiting; 256 cached names. Requests
  time out after 12 seconds per endpoint and may fall back to Scryfall.
  Successful results last only for the current scripting session. Failed
  lookups can be retried after two minutes.
- Up to 20 targets per selection and 64 committed selections are kept.
  `mtg target` captures existing arrows from the last hovered source (or
  from its most recently drawn inbound arrow), **owned by that same seat**.
  If no matching existing arrows are found, the first subsequent arrow
  establishes the source. Repeated gestures across pre-existing arrows
  add targets without duplicate registration.
- Repeating `mtg target` during an active selection reports its current
  count without replacing it. A source mismatch is reported privately.
  An empty draft cannot be committed.
- Undo/clear of visual arrows changes **draft** targets, not committed choices.
  This does not enforce legal targets, mana costs, priority, targets that are
  players, spells on the stack, or spell resolution.
- There are no periodic table-wide scans, HTTP calls on hover, or changes
  to the other Lotus modules.

## Mocked regression tests

From repository root with a Lua 5.2 interpreter:

```sh
lua5.2 tests/card_catalog_test.lua
lua5.2 tests/target_registry_test.lua
lua5.2 tests/combat_arrows_test.lua
lua5.2 tests/combat_hotkey_test.lua
python tools/build.py --check
```

Lua mocks test interfaces and lifecycle; they are not multiplayer/TTS runtime
verification. Validate live behavior on a separate 4-player test save.
