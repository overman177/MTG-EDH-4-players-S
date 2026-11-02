-- Standalone Lua 5.2 regression test for Lotus' combat hotkey lifecycle.
-- Run from repository root: lua5.2 tests/combat_hotkey_test.lua
Settings = {combatEnabledByColor = {White = true, Blue = true, Red = true, Yellow = true}}
local cards = {}
local messages = {}
local updated = 0
local function card(guid)
    local obj = {tag="Card", guid=guid}
    function obj.getGUID() return guid end
    function obj.isDestroyed() return false end
    cards[guid] = obj
    return obj
end
function getObjectFromGUID(guid) return cards[guid] end
function printToColor(msg, color) messages[#messages+1]={msg,color} end
local a, b, c, d = card("a11111"), card("b22222"), card("c33333"), card("d44444")
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.updated = function() updated = updated + 1 end
local function gesture(color, from, to)
    Combat.hotkey(color, from, nil, false)
    Combat.hotkey(color, to, nil, true)
end
-- Declare and retarget.
gesture("White", a, b)
assert(Combat.links[a.getGUID()].target == b.getGUID(), "declaration")
gesture("White", a, c)
assert(Combat.links[a.getGUID()].target == c.getGUID(), "retarget")
-- Repeat exact gesture toggles off.
gesture("White", a, c)
assert(Combat.links[a.getGUID()] == nil, "repeat-to-remove")
-- Tap on attacker clears only that attacker's arrow.
gesture("White", a, b)
gesture("Blue", d, b)
gesture("White", a, a)
assert(Combat.links[a.getGUID()] == nil, "tap-to-remove")
assert(Combat.links[d.getGUID()] and Combat.links[d.getGUID()].by == "Blue",
    "other player's arrows unaffected")
-- Tapping an attacker with no arrow is harmless.
gesture("White", a, a)
assert(Combat.links[a.getGUID()] == nil, "tap without arrow")
-- Missing release target is safe, retaining existing arrow.
gesture("Blue", d, nil)
assert(Combat.links[d.getGUID()].target == b.getGUID(), "invalid target should not clear")
-- Disabled player cannot create or clear arrows.
Settings.combatEnabledByColor.Blue = false
gesture("Blue", d, d)
assert(Combat.links[d.getGUID()].target == b.getGUID(), "disabled ignores gesture")
Settings.combatEnabledByColor.Blue = true
Combat.clear("Blue")
assert(Combat.links[d.getGUID()] == nil, "clear my arrows")
assert(updated >= 6, "expected arrow render updates")
print("Combat hotkey tests passed.")
