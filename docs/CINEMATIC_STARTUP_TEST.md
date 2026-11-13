# Cinematic startup test (4-player)

This is an experimental full-screen UI intro. It has **not** been merged into main and cannot display until its feature branch is checked out and imported into TTS. It replaces the previous small banner for about nine seconds, then fades away. The progress bar represents a timed animation, **not** measured loading progress.

## Add the artwork

In Tabletop Simulator open **Scripting > UI > Custom UI Assets**, add an image asset called **MTG_Cinematic_Logo**, and point it to an uploaded/public copy of WORKSHOP_4_PLAYER.png. Do not replace the table's other custom assets. The in-game script checks for that specific asset and otherwise displays a text-only fallback. Upload the image to TTS Cloud or another permanent HTTPS host through the normal UI.

## Run the test

1. In VS Code, check out the feature branch without running the destructive updater: \`git fetch origin && git switch feature/cinematic-loading-screen-test\`.
2. Run \`python tools/deploy.py --apply\`, then TTS **Smart Import > Save & Play**.
3. The splash appears automatically on load. Replay from the TTS scripting console with \`Global.call("mtgShowVersionBanner")\`.
4. Click **SKIP >>** to dismiss it for everyone. The animation never alters cards, zones, camera, or gameplay.
5. To return to the published code, switch back to \`main\` and run your normal update/deploy process.

Only Global UI, startup Lua, this document, and the corresponding test are modified. GitHub main and the published Workshop item remain unchanged.
