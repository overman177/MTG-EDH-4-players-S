-- Combat gesture regression: defender-first, multiple blockers per attacker.
Settings = {combatEnabledByColor = {White=true,Red=true,Yellow=true,Blue=true}}
local cards, updated, messages = {}, 0, {}
local function card(guid)
    local o = {tag="Card", guid=guid}
    function o.getGUID() return guid end
    function o.isDestroyed() return false end
    cards[guid] = o
    return o
end
local attackerA, attackerB = card("a11111"), card("b22222")
local defenderA, defenderB, defenderC =
    card("c33333"), card("d44444"), card("e55555")
function getObjectFromGUID(guid) return cards[guid] end
function printToColor(msg,color) messages[#messages+1]={msg,color} end
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.updated = function() updated=updated+1 end
local function gesture(color, defender, attacker)
    Combat.hotkey(color, defender, nil, false)
    Combat.hotkey(color, attacker, nil, true)
end
local function count(attacker)
    return Combat.countDefenders(Combat.links[attacker.getGUID()])
end

gesture("White", defenderA, attackerA)
assert(count(attackerA)==1 and Combat.singleDefender(attackerA.getGUID())==defenderA.getGUID(),
       "single blocker")
gesture("White", defenderB, attackerA)
assert(count(attackerA)==2 and Combat.singleDefender(attackerA.getGUID())==nil,
       "two blockers")
gesture("White", defenderC, attackerA)
assert(count(attackerA)==3,"third blocker")
-- Toggle only one defender, preserving the others.
gesture("White", defenderB, attackerA)
assert(count(attackerA)==2,"removed only selected blocker")
assert(Combat.links[attackerA.guid].defenders[defenderA.guid],
       "first blocker preserved")
assert(Combat.links[attackerA.guid].defenders[defenderC.guid],
       "third blocker preserved")
gesture("White", defenderC, attackerA)
assert(count(attackerA)==1 and Combat.singleDefender(attackerA.guid)==defenderA.guid,
       "back to single blocker")
gesture("White", defenderA, attackerA)
assert(Combat.links[attackerA.guid]==nil,"toggle last pair off")
-- Other attacker can share a defender.
gesture("White", defenderA, attackerA)
gesture("Blue", defenderA, attackerB)
assert(Combat.links[attackerA.guid] and Combat.links[attackerB.guid],
       "independent attackers may share defender")
-- Same-card tap clears all defenders for that attacker.
gesture("White", defenderB, attackerA)
gesture("White", attackerA, attackerA)
assert(Combat.links[attackerA.guid]==nil,"tap clears all its blockers")
assert(Combat.links[attackerB.guid]~=nil,"tap preserves other attacker")
gesture("Blue", defenderA, nil)
assert(count(attackerB)==1,"invalid release harmless")
Settings.combatEnabledByColor.Blue=false
gesture("Blue", attackerB, attackerB)
assert(count(attackerB)==1,"disabled hotkey harmless")
Settings.combatEnabledByColor.Blue=true
Combat.clear("Blue")
assert(Combat.links[attackerB.guid]==nil,"personal clear")
assert(updated>=10,"arrow updates triggered")
print("Multi-defender combat hotkey tests passed.")
