# Lotus Helper release history

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
