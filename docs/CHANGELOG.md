# Lotus Helper release history

## Version 1.9.0 — Directional arrows and automation improvements
- Arrows now point from the first (key-down) card to the second (key-up) card, without assigning attacker/defender roles.
- Preserved multiple arrows, card-following arrows, Undo and configurable hold-to-clear.
- Automatically recognizes printed card keywords and displays their Encoder indicators.
- Improved card metadata handling and reduced unnecessary table polling.
- Hardened Draw Random against transient deck merges, splits and destroyed objects.


## Version 1.8.0 — Ring ornament and Black Lotus quality-of-life
- Added an animated One Ring ornament that floats and follows The Ring card.
- Enlarged and restyled the startup banner with Black Lotus purple/cyan colors.
- Reduced startup chat clutter; routine initialization messages now go to the system console.
- Added a one-click workflow to register and publish newly imported TTS objects.
- Simplified updates across both tables and fixed problems caused by legacy backup files and self-updating scripts.
- Organized repository scripts and strengthened automated validation.

## Version 1.7.0 — Counter visibility and deck stacking

- Fixed occasional Lua errors while multiple loose cards merge onto a library.
- Prevented Always Reveal Top from using a destroyed or replaced library reference.
- Deferred equipment processing until dropped cards can be resolved by GUID.
- Made ME counter visibility independent after EVERYONE is turned off.
- Changed EVERYONE toggles into per-counter bulk controls across all four seats.
- Migrated older counter settings without unexpectedly revealing hidden counters.


## Version 1.6.0 — Personal previews and feedback

- Added per-player card preview sizing from 50% to 150%, saved per seat.
- Card preview scaling now affects only your own screen.
- Connected in-game bug reports and feature requests to the table's own GitHub Issues.
- Fixed the missing bug report icon.
- Centered the host and player settings gear icons.
- Moved the bottom-right table controls slightly left for better spacing.

## Version 1.5.1 — Card preview reliability

- Cache preview images under stable per-face UI asset names, up to 24.
- Give clients three extra seconds to render newly registered artwork.
- Retry battlefield placement checks instead of relying on one five-frame check.
- Preserve hand/commander origin until battlefield placement succeeds.
- Recover missed hand-entry events on pickup/leave.
- Allow optional Lotus preview diagnostics with `getObjectFromGUID("185063").call("previewDebug", {enabled=true})` in the TTS console.

TTS does not expose per-client image loading status; the longer first-load
display mitigates that limitation, but cannot guarantee a remote download.

The in-game Patch Notes reader uses the Black `LOTUS_PATCH_NOTES` notebook page,
which is saved with the table and is not overwritten by script deployment.
