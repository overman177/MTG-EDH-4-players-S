-- A destroyed TTS Unity object proxy must not break sibling event handlers.
dofile("src/lotus/sections/05_always-reveal-top-non-colliding-visual-clone.lua")
local dead = {
    type="Deck",
    getGUID=function() error("Object reference not set to an instance of an object") end
}
assert(pcall(RevealTop.onDestroy, dead), "RevealTop must tolerate invalid objects")
local seen = {}
DrawRandom={onDestroy=function() error("deck invalidated") end}
Combat={onDestroy=function() seen.combat=true end}
TargetRegistry={
    onDestroy=function() seen.target=true end,
    onHover=function() seen.hover=true end
}
Equipment={onHover=function() error("hovered deck invalidated") end}
dofile("src/lotus/sections/07_shared-event-dispatcher.lua")
assert(pcall(onObjectDestroy, dead))
assert(seen.combat and seen.target, "Destroy event skipped subsequent modules")
assert(pcall(onObjectHover, "White", dead))
assert(seen.hover, "Hover event skipped target registry")
print("Lotus lifecycle callbacks: OK")
