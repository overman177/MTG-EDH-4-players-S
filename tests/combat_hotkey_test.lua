-- Lua 5.2: additive drawing, explicit removal, undo, ownership.
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
local function gesture(fn,color,def,atk)
    fn(color,def,nil,false);fn(color,atk,nil,true)
end
local function count(atk) return Combat.countDefenders(Combat.links[atk.guid]) end
gesture(Combat.hotkey,"White",d1,a)
gesture(Combat.hotkey,"White",d2,a)
gesture(Combat.hotkey,"White",d3,a)
assert(count(a)==3,"multi-defender pairings")
gesture(Combat.hotkey,"White",a,a)
gesture(Combat.hotkey,"White",d1,d1)
assert(count(a)==3,"tap must never delete")
gesture(Combat.hotkey,"White",d2,a)
assert(count(a)==3,"duplicate pair idempotent")
gesture(Combat.hotkey,"Blue",d2,a)
assert(Combat.links[a.guid].defenders[d2.guid]=="White","cannot claim other player's pair")
gesture(Combat.removeHotkey,"Blue",d2,a)
assert(count(a)==3,"cannot remove other player's pair")
gesture(Combat.removeHotkey,"White",d2,a)
assert(count(a)==2 and not Combat.links[a.guid].defenders[d2.guid],"remove one exact arrow")
assert(Combat.undo("White"),"undo most recent existing arrow")
assert(count(a)==1 and Combat.links[a.guid].defenders[d1.guid],"undo skips removed arrow")
gesture(Combat.hotkey,"Blue",d2,b)
gesture(Combat.hotkey,"White",d3,b)
Combat.undoHotkey("White",nil,nil,false)
assert(count(b)==1 and Combat.links[b.guid].defenders[d2.guid]=="Blue","undo own arrow only")
gesture(Combat.removeHotkey,"White",d1,nil)
assert(count(a)==1,"invalid release harmless")
gesture(Combat.hotkey,"White",d3,a)
Settings.combatEnabledByColor.White=false
gesture(Combat.removeHotkey,"White",d1,a)
assert(count(a)==2,"disabled remove harmless")
Settings.combatEnabledByColor.White=true
Combat.clear("White")
assert(not Combat.links[a.guid] and count(b)==1,"clear preserves other player")
Combat.clear("Blue")
assert(not next(Combat.links),"all clear")
assert(updates>0)
print("Combat additive draw / remove / undo test passed.")
