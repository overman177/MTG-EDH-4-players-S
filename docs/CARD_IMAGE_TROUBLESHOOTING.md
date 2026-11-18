# Card-image troubleshooting (4 players)

The bundled importer uses https://img.klrmngr.com for card artwork.

Issue #1022 reports \`WWW Image Error: Cannot resolve destination host\`,
with a URL containing \`/dispaly/\` instead of \`/display/\`.

The importer now normalizes that misspelled path in custom URLs and supplied
deck JSON. This does not repair cards already imported into saved games.

DNS failures or ISP blocks on the image CDN cannot be repaired by the
table's Lua script. Some players see cards from their local texture cache
while their opponents cannot download the same URL.

Recommended diagnostic: copy the exact failing URL, open it from the affected
player's browser, verify hostname resolution and spelling, and if needed
reimport the affected deck with a working image source. Do not blindly replace
image URLs on all objects: player-supplied custom art and deck sheets may
use different formats or hosts.

See https://github.com/overman177/MTG-EDH-4-players-S/issues/1022
