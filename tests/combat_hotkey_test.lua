-- Lua 5.2: additive draw, key-down personal clear, and undo remain independent.
Settings={combatEnabledByColor={White=true,Blue=true,Red=true,Yellow=true}}
local cards,updates={},0
local function card(guid)
    local o={tag="Card",guid=guid}
    o.getGUID=function() return guid end
    o.isDestroyed=function() return false end
    cards[guid]=o
    return o
end
function getObjectFromGUID(guid) return cards[guid] end
function printToColor() end
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.updated=function() updates=updates+1 end
local a=card("a11111");local b=card("b22222")
local d1=card("d11111");local d2=card("d22222");local d3=card("d33333")
local function draw(color,def,atk)
    Combat.hotkey(color,def,nil,false)
    Combat.hotkey(color,atk,nil,true)
end
local function count(atk) return Combat.countDefenders(Combat.links[atk.guid]) end

draw("White",d1,a)
draw("White",d2,a)
draw("White",d3,a)
assert(count(a)==3,"three defenders coexist")
draw("White",d2,a)
assert(count(a)==3,"duplicate draw is idempotent")
draw("White",a,a)
assert(count(a)==3,"same-card DRAW tap is harmless")
assert(Combat.undo("White") and count(a)==2,"UNDO removes most recent arrow")
assert(Combat.links[a.guid].defenders[d3.guid]==nil,"UNDO removed d3 only")
assert(Combat.links[a.guid].defenders[d1.guid]=="White","UNDO preserves older arrow")

-- Blue owns a separate arrow on the same attacker, plus one on another.
draw("Blue",d3,a)
draw("Blue",d3,b)
assert(count(a)==3 and count(b)==1,"both players have visible arrows")
-- REMOVE is now an instant clear on key-down, not a defender-to-attacker gesture.
Combat.removeHotkey("White",nil,nil,true)
assert(count(a)==3,"key-up alone must never clear")
Combat.removeHotkey("White",nil,nil,false)
assert(count(a)==1 and count(b)==1,"one press clears all White arrows only")
assert(Combat.links[a.guid].defenders[d3.guid]=="Blue","Blue arrow preserved on shared attacker")
assert(Combat.undo("White")==false,"clear empties White undo history")
assert(Combat.undo("Blue")==true and count(b)==0,"Blue undo still works")

draw("White",d1,a)
draw("White",d2,b)
assert(count(a)==2 and count(b)==1,"new White arrows can be created")
Settings.combatEnabledByColor.White=false
Combat.removeHotkey("White",nil,nil,false)
assert(count(a)==2 and count(b)==1,"disabled player cannot clear on press")
Settings.combatEnabledByColor.White=true
Combat.removeHotkey("Purple",nil,nil,false)
assert(count(a)==2 and count(b)==1,"non-seat input is ignored")
Combat.removeHotkey("White",a,nil,false)
assert(count(a)==1 and count(b)==0,"pointer location irrelevant to key press")
assert(Combat.undo("White")==false,"cleared arrows cannot be undone back")
Combat.clear("Blue")
assert(next(Combat.links)==nil,"personal clear also available for Blue")
assert(updates>0)
print("Combat draw / key-down personal clear / undo tests passed.")
