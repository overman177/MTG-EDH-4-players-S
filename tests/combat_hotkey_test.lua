-- Regression: normal defender -> attacker gesture only ADDS; tapping removes.
Settings = {combatEnabledByColor = {White=true,Red=true,Yellow=true,Blue=true}}
local cards, updated, nextX = {}, 0, 0
local function card(guid)
    nextX = nextX + 3
    local obj = {tag="Card", guid=guid, point={x=nextX,z=0}}
    function obj.getGUID() return guid end
    function obj.isDestroyed() return false end
    cards[guid] = obj
    return obj
end
local atkA, atkB = card("a11111"), card("b22222")
local defA, defB, defC = card("c33333"), card("d44444"), card("e55555")
function getObjectFromGUID(guid) return cards[guid] end
function printToColor() end
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.updated = function() updated=updated+1 end
local function gesture(color, startObj, endObj, downAt, upAt)
    local startPos = downAt or (startObj and startObj.point)
    local endPos = upAt or (endObj and endObj.point)
    Combat.hotkey(color, startObj, startPos, false)
    Combat.hotkey(color, endObj, endPos, true)
end
local function count(attacker)
    return Combat.countDefenders(Combat.links[attacker.guid])
end
gesture("White", defA, atkA)
assert(count(atkA)==1 and Combat.links[atkA.guid].defenders[defA.guid]=="White",
       "first defender added")
gesture("White", defB, atkA)
assert(count(atkA)==2 and Combat.links[atkA.guid].defenders[defA.guid]=="White",
       "second defender does not remove first")
gesture("White", defC, atkA)
assert(count(atkA)==3,"third defender added")
-- BUG REPRODUCTION: both hovered objects resolve to the attacker while the
-- pointer actually moves substantially. This must NOT be treated as a tap.
gesture("White", atkA, atkA, {x=0,z=0}, {x=5,z=0})
assert(count(atkA)==3, "moved cursor must not erase previously declared arrows")
assert(Combat.isStationaryTap({x=0,z=0}, {x=5,z=0})==false,
       "moved gesture cannot be mistaken for a removal tap")
local previousUpdates=updated
gesture("White", defA, atkA)
assert(count(atkA)==3 and updated==previousUpdates,
       "repeating same pair is a no-op, NEVER a toggle")
gesture("Blue", defA, atkA)
assert(count(atkA)==3 and Combat.links[atkA.guid].defenders[defA.guid]=="White",
       "repeating another player's pair does not steal ownership")
-- Same-card stationary tap on a non-attacking defender removes its arrows.
gesture("White", defB, defB)
assert(count(atkA)==2 and Combat.links[atkA.guid].defenders[defB.guid]==nil,
       "tap defender B removes B only")
assert(Combat.links[atkA.guid].defenders[defA.guid] and
       Combat.links[atkA.guid].defenders[defC.guid],
       "other two defender arrows are preserved")
gesture("White", defC, defC)
assert(count(atkA)==1 and Combat.singleDefender(atkA.guid)==defA.guid,
       "removal leaves one blocker")
gesture("White", defA, defA)
assert(Combat.links[atkA.guid]==nil,"last defender tap removes attacker link")
-- A defender may participate in several attacker declarations, independently.
gesture("White", defA, atkA)
gesture("Blue", defA, atkB)
assert(count(atkA)==1 and count(atkB)==1, "shared defender on two attackers")
gesture("White", defA, defA)
assert(Combat.links[atkA.guid]==nil and Combat.links[atkB.guid]~=nil,
       "defender tap only removes that player's own declaration")
-- Mixed owners on the SAME attacking card must remain independent.
gesture("White", defB, atkA)
gesture("Blue", defC, atkA)
assert(count(atkA)==2,"mixed owner pair")
Combat.clear("White")
assert(count(atkA)==1 and Combat.links[atkA.guid].defenders[defC.guid]=="Blue",
       "Clear my arrows preserves other players' arrows on the same attacker")
assert(count(atkB)==1,"Clear my arrows preserves other attack")
-- Moved same-hover event must never clear mixed-player arrows either.
gesture("White", atkA, atkA, {x=-2,z=-2}, {x=0,z=0})
assert(count(atkA)==1, "movement cannot erase mixed-player declarations")
-- A truly stationary key tap on attacker clears all its arrows.
gesture("White", atkA, atkA)
assert(Combat.links[atkA.guid]==nil and Combat.links[atkB.guid]~=nil,
       "tap on attacker clears all that attacker's arrows")
gesture("Blue", defC, nil)
assert(count(atkB)==1,"invalid release doesn't clear anything")
Settings.combatEnabledByColor.Blue=false
gesture("Blue", atkB, atkB)
assert(count(atkB)==1,"disabled hotkey cannot clear arrows")
Settings.combatEnabledByColor.Blue=true
Combat.clear("Blue")
assert(Combat.links[atkB.guid]==nil,"Blue clears own arrows")
assert(updated>=10,"drawing updates fired")
-- A key-up without recorded pointer positions is never destructive.
gesture("White", defA, atkA)
assert(count(atkA)==1,"re-create after clear")
Combat.hotkey("White", atkA, nil, false)
Combat.hotkey("White", atkA, nil, true)
assert(count(atkA)==1,"missing pointer data cannot clear existing arrow")
print("Additive multi-defender hotkey tests passed.")
