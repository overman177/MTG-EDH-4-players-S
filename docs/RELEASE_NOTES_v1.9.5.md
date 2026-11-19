# v1.9.5 — Four-player maintenance release

Based on the stable v1.9.0 feature set. No new MTG card-resolution
automation is included in this release.

- Fixed Draw Random with Always Reveal Top enabled: removes the temporary
  top-card clone during the draw, prevents stale copies, and refreshes it
  after a short 45-frame pause while TTS updates the library.

- Hardened Lotus Helper callbacks against destroyed Card/Deck references
  encountered during shuffles, merges, and object lifecycle events.
- Added safer deferred updates for Equipment hover buttons and Always
  Reveal Top, reducing errors when decks are replaced or consumed.
- Corrected the misspelled \`/dispaly/\` path to \`/display/\` for new
  card-image imports using the bundled importer. External DNS/CDN
  outages are outside the table's control.
- Improved in-game bug-report validation, prevented concurrent
  duplicate reports, and added a local two-minute cooldown.
- Added automatic closure/cleanup for recurring Discord-invitation
  spam in the GitHub Issues tracker.

- Corrected the Lotus Helper's visible version label to v1.9.5 (the Global
  version was already v1.9.5), and included maintenance notes directly in
  Lotus Settings without modifying the owner's Notebook page.

- Prevented temporary Reveal Top cards from spawning physically above a
  library before collision removal is verified. Previews that cannot be
  made collision-free are discarded rather than risking duplicated cards.

## Deferred to a later update

The experimental card catalog, semantic target registry, Encoder-backed
card state service, and automatic instant/sorcery Resolve buttons are
not part of v1.9.5. Their source and related tests were rolled back
from the active table scripts. Existing visual combat arrows remain.

## Notes

GitHub code updates are not the same as uploading a Tabletop Simulator
Steam Workshop version. To test locally, import the compiled GUID scripts
and use Smart Import > Save & Play.
