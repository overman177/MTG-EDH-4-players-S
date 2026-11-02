# Combat targeting (Lotus Helper)

## What it does
Hold **MTG: Declare Combat Target** with the cursor over the **DEFENDER** first, move to the **ATTACKER** and release. Lotus draws a colored attacker-to-target arrow for all players, following the two cards as they move.

This is a **visual declaration only**, not a Magic rules engine: it does not tap cards, assign blockers, check legal attacks, manage combat phases, or apply damage.

## Configure the key
Table Settings > General > **Configure key (C suggested)** opens the built-in TTS Game Keys dialog. Find **MTG: Declare Combat Target**, click its binding field and press **C** (or another free key). TTS's `addHotkey` API does **not** allow a script to assign the physical key; player binding is required once, then TTS retains it under the same label on subsequent loads.

If C already has a TTS action on a player's client, the two actions can both run; the player should change the conflicting binding in TTS Controls. Each player independently configures their own key.

## General tab controls
- **Enable combat targeting for me**: per-seat setting, on by default, saved with Lotus's existing settings and playmat data.
- **Configure key (C suggested)**: opens TTS Options > Game Keys.
- **Clear my arrows**: removes only target declarations made by that player. Disabling combat targeting also clears that player's arrows.

## Gesture and limits
- Only physical TTS **Card** objects are valid sources and targets.
- **Start on defender**, release over an **attacker**. The arrow is drawn from attacker toward defender.
- **Remove a single arrow:** tap the combat key while hovering the attacker (press and release on the same card).
- **Toggle off by repeating:** start on the same defender and release on the same attacker again.
- Start on a different defender and release on an attacker that already has an arrow to retarget it.
- **Remove every arrow you declared:** Table Settings > General > Clear my arrows.
- Each attacking card has one active defender target (a visual shortcut, not a complete multi-blocker combat model).
- Arrows use the Lotus Helper's vector-line layer, not Global/table lines.
- Declarations are session-only and disappear on script reload; saved playmats and settings are unaffected.
- Arrows update every 0.3 seconds while active. Destroyed cards clear related declarations.
- Do not use the native Tab ruler for this; the TTS Lua API does not expose native ruler drag start/end.

## Developer ownership
`src/lotus/sections/06_combat-targeting.lua` is the source; 
`src/lotus/sections/07_shared-event-dispatcher.lua` registers the hotkey and object-destroy cleanup.
`src/lotus/sections/03_edh-settings.lua` owns the General tab and settings persistence.
`src/ui/sections/08_lotus-settings.xml` owns the checked-in Global XML copy of the General tab.

Build with `py tools/build.py --check` and use a **copy** of the TTS table for the first Save & Play test. Check that the existing General, Counters and Card Preview tabs still function, that two players can declare simultaneously and that unrelated drawn lines are unaffected.
