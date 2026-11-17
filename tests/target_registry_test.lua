-- Mocked Lua 5.2 test: explicit targeting sessions over existing combat arrows.
Settings = {combatEnabledByColor = {White=true, Blue=true, Red=true, Yellow=true}}
local objects, messages = {}, {}
local function card(guid, name)
    local obj = {tag="Card", dead=false, is_face_down=false}
    obj.getGUID=function() return guid end
    obj.getName=function() return name end
    obj.isDestroyed=function() return obj.dead end
    objects[guid]=obj
    return obj
end
function getObjectFromGUID(guid) return objects[guid] end
function printToColor(msg, color) messages[#messages+1]={msg=msg, color=color} end
Wait = {time=function() end}
Global = {call=function(method, params)
    assert(method=="mtgCardCatalogRequest")
    return {status="pending", localData={name="Test"}} end}

dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.updated=function() end
dofile("src/lotus/sections/06a_target-registry.lua")
TargetRegistry.load()
TargetRegistry.onHover("White",card("aaaaaa","Temporary"))
TargetRegistry.onHover("White",nil)
assert(TargetRegistry.hovered.White=="aaaaaa","nil hover preserves last card for chat")

local spell=card("111111","Swords to Plowshares")
local target1=card("222222","Llanowar Elves")
local target2=card("333333","Serra Angel")
local other=card("444444","Shock")

-- Ordinary arrows must not constitute registered targets.
Combat.hotkey("White", spell, nil, false)
Combat.hotkey("White", target1, nil, true)
assert(TargetRegistry.read({color="White"}).status=="none")

local start=TargetRegistry.begin({color="White",sourceGUID="111111"})
assert(start.status=="active" and start.sourceGUID=="111111")
-- Gesture over a pre-existing arrow still selects the target.
Combat.hotkey("White",spell,nil,false)
Combat.hotkey("White",target1,nil,true)
Combat.hotkey("White",spell,nil,false)
Combat.hotkey("White",target2,nil,true)
Combat.hotkey("Blue",other,nil,false)
Combat.hotkey("Blue",target2,nil,true)
local pending=TargetRegistry.read({color="White"})
assert(pending.count==2 and pending.targets[1].guid=="222222")
assert(pending.targets[2].guid=="333333","target order matches gestures")
assert(TargetRegistry.read({color="Blue"}).status=="none","not ambient arrows")
Combat.undo("White")
assert(TargetRegistry.read({color="White"}).count==1,"undo updates draft")
local completed=TargetRegistry.finish({color="White"})
assert(completed.status=="committed" and completed.count==1)
Combat.clear("White")
assert(TargetRegistry.read({id=completed.id}).count==1,
    "clearing visual arrows cannot silently alter committed targets")

local again=TargetRegistry.begin({color="White", sourceGUID="111111"})
assert(again.id~=completed.id,"each session has distinct identity")
Combat.hotkey("White",spell,nil,false)
Combat.hotkey("White",target2,nil,true)
assert(TargetRegistry.read({color="White"}).count==1)
TargetRegistry.cancel({color="White"})
assert(TargetRegistry.read({color="White"}).id==completed.id,
    "cancel restores access to last committed selection")

-- Deletion retains committed target identity, but marks it invalid.
target1.dead=true
objects["222222"]=nil
local stale=TargetRegistry.read({id=completed.id})
assert(stale.count==1 and stale.targets[1].valid==false)
-- Caller cannot begin with a destroyed source.
spell.dead=true
assert(TargetRegistry.begin({color="White",sourceGUID="111111"}).status=="invalid")
assert(TargetRegistry.onChat("mtg help", {color="White"})==false)
print("Target registration isolation/undo/commit/invalid-target tests passed.")
