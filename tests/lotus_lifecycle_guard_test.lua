-- Deck merges must not let one invalid Unity proxy cancel other event handlers.
dofile("src/lotus/sections/05_always-reveal-top-non-colliding-visual-clone.lua")
local dead = {type="Deck",getGUID=function() error("Object reference not set to an instance of an object") end}
assert(pcall(RevealTop.onDestroy, dead))
local seen = {}
DrawRandom = {onDestroy=function() error("invalid deck reference") end}
RevealTop.onDestroy = function() seen.reveal = true end
Combat = {onDestroy=function() seen.combat = true end}
Preview = {onDrop=function() error("card merged before drop") end}
Equipment = {
    onDrop=function() seen.drop = true end,
    onHover=function() error("hovered object disappeared") end
}
dofile("src/lotus/sections/07_shared-event-dispatcher.lua")
assert(pcall(onObjectDestroy, dead))
assert(seen.reveal and seen.combat, "Other destroy handlers must continue")
assert(pcall(onObjectDrop, "White", dead))
assert(seen.drop, "Equipment drop handler must continue")
assert(pcall(onObjectHover, "White", dead))
print("Lotus invalid Unity object regression: OK")
