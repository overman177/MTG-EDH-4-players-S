# Lotus Helper release history

## Version 1.5.1 — Card preview reliability

- Cache preview images under stable per-face UI asset names, up to 24.
- Give clients three extra seconds to render newly registered artwork.
- Retry battlefield placement checks instead of relying on one five-frame check.
- Preserve hand/commander origin until battlefield placement succeeds.
- Recover missed hand-entry events on pickup/leave.
- Allow optional Lotus preview diagnostics.

TTS does not expose per-client image loading status; the longer first-load
display mitigates that limitation, but cannot guarantee a remote download.

The in-game Patch Notes reader uses the Black `LOTUS_PATCH_NOTES` notebook page,
which is saved with the table and is not overwritten by script deployment.
