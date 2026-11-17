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
4. Hover the source card (for example Swords to Plowshares) and type
   `mtg target`. Hold the existing arrow hotkey over the **same source
   card**, then release it over Llanowar Elves; repeat with Serra Angel.
5. Type `mtg targets` to review your **draft** selection.
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
  Only gestures performed **after** `mtg target` are recorded, including
  explicitly repeated gestures across pre-existing arrows.
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
