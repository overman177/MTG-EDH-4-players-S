-- Lua 5.2 regression test: DEFENDER is pressed first, ATTACKER released second.
-- Run from repository root: lua5.2 tests/combat_hotkey_test.lua
Settings = {combatEnabledByColor = {White = true, Blue = true, Red = true, Yellow = true}}
local cards = {}
local messages, updated = {}, 0
local function card(guid)
    local obj = {tag="Card", guid=guid}
    function obj.getGUID() return guid end
    function obj.isDestroyed() return false end
    cards[guid] = obj
    return obj
end
function getObjectFromGUID(guid) return cards[guid] end
function printToColor(msg, color) messages[#messages+1]={msg,color} end
local attackerA, attackerB = card("a11111"), card("b22222")
local defenderA, defenderB = card("c33333"), card("d44444")
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.updated = function() updated = updated + 1 end
local function gesture(color, defender, attacker)
    Combat.hotkey(color, defender, nil, false)
    Combat.hotkey(color, attacker, nil, true)
end

-- Defender FIRST, attacker SECOND; store keyed by the attacker.
gesture("White", defenderA, attackerA)
assert(Combat.links[attackerA.getGUID()].target == defenderA.getGUID(), "defender -> attacker declaration")
assert(Combat.links[defenderA.getGUID()] == nil, "link key must be the attacker")
-- Retarget by starting on a different defender and releasing on same attacker.
gesture("White", defenderB, attackerA)
assert(Combat.links[attackerA.getGUID()].target == defenderB.getGUID(), "retarget")
-- The exact same defender -> attacker gesture toggles off.
gesture("White", defenderB, attackerA)
assert(Combat.links[attackerA.getGUID()] == nil, "repeat-to-remove")
-- Tap an attacker to remove only that attacker's arrow.
gesture("White", defenderA, attackerA)
gesture("Blue", defenderB, attackerB)
gesture("White", attackerA, attackerA)
assert(Combat.links[attackerA.getGUID()] == nil, "tap-to-remove")
assert(Combat.links[attackerB.getGUID()] and Combat.links[attackerB.getGUID()].by == "Blue",
    "other player's arrows unaffected")
-- Tap without a link is harmless.
gesture("White", attackerA, attackerA)
assert(Combat.links[attackerA.getGUID()] == nil, "no arrow")
-- Release without card leaves previous arrow intact.
gesture("Blue", defenderA, nil)
assert(Combat.links[attackerB.getGUID()].target == defenderB.getGUID(), "invalid release")
-- Disabled player cannot create or remove arrows.
Settings.combatEnabledByColor.Blue = false
gesture("Blue", attackerB, attackerB)
assert(Combat.links[attackerB.getGUID()] ~= nil, "disabled gesture")
Settings.combatEnabledByColor.Blue = true
Combat.clear("Blue")
assert(Combat.links[attackerB.getGUID()] == nil, "clear my arrows")
assert(updated >= 6, "expected arrow updates")
print("Combat direction and removal tests passed.")
