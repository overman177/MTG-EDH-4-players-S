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
    if method=="mtgCardState" then
        return {status="ready", name="Serra Angel", owner="White",
            controller="White", zone="Battlefield", zoneColor="Red",
            basePower="4",baseToughness="4",powerAdjustment=1,
            toughnessAdjustment=2,currentPower=7,currentToughness=8,
            powerToughnessSource="encoder",
            counters={plusOnePlusOne=2,named=0,stun=0},
            encodedKeywords={flying=1,vigilance=1},tapped=true,
            controlReady=false,damageMarked=0}
    end
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

-- The chat snapshot must show the original encoded base separately from
-- adjustments, +1/+1 counters and displayed P/T (plus known false values).
TargetRegistry.onHover("White",target2)
assert(TargetRegistry.onChat("mtg state",{color="White"})==false)
local output={}
for _, entry in ipairs(messages) do output[#output+1]=entry.msg end
local chatLog=table.concat(output,"\n")
assert(chatLog:find("Encoded base P/T 4/4",1,true),"show encoded base")
assert(chatLog:find("adjustments +1/+2",1,true),"show signed adjustments")
assert(chatLog:find("+1/+1 counters 2",1,true),"show stat counters separately")
assert(chatLog:find("Displayed P/T 7/8",1,true),"show combined P/T")
assert(chatLog:find("tapped=true, ready=false, damage=0",1,true),
    "retain zero and false values without treating them as unknown")

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

-- Regression: arrows were drawn BEFORE "mtg target", but the player
-- last hovered the destination (Serra Angel), not the source (Comet Storm).
local comet=card("555551","Comet Storm")
local elf=card("555552","Llanowar Elves")
local angel=card("555553","Serra Angel")
local blueTarget=card("555554","Blue target")
Combat.hotkey("White",comet,nil,false)
Combat.hotkey("White",elf,nil,true)
Combat.hotkey("White",comet,nil,false)
Combat.hotkey("White",angel,nil,true)
Combat.hotkey("Blue",comet,nil,false)
Combat.hotkey("Blue",blueTarget,nil,true)
TargetRegistry.onHover("White",angel)
assert(TargetRegistry.onChat("mtg target",{color="White"})==false)
local fromEnd=TargetRegistry.read({color="White"})
assert(fromEnd.status=="active" and fromEnd.sourceGUID=="555551",
    "source is recovered from an inbound arrow rather than last hovered target")
assert(fromEnd.count==2 and fromEnd.targets[1].guid=="555552"
    and fromEnd.targets[2].guid=="555553",
    "both already drawn White arrows get registered in drawing order")
assert(TargetRegistry.onChat("mtg target",{color="White"})==false)
assert(TargetRegistry.read({color="White"}).count==2,
    "repeating command reports active session, never erases earlier targets")
assert(TargetRegistry.onChat("mtg done",{color="White"})==false)
local seededCommit=TargetRegistry.read({color="White"})
assert(seededCommit.status=="committed" and seededCommit.count==2)
Combat.clear("White")
assert(TargetRegistry.read({id=seededCommit.id}).count==2,
    "committed targets independent of removed visual arrows")

-- Regression: initiating a session BEFORE drawing arrows must not lock the
-- source accidentally to the previously hovered destination.
local newSpell=card("666661","New source")
local secondTarget=card("666662","Second target")
TargetRegistry.onHover("White",newSpell)
assert(TargetRegistry.onChat("mtg target",{color="White"})==false)
local before=TargetRegistry.read({color="White"})
assert(before.status=="active" and before.sourceGUID==nil and before.count==0)
assert(TargetRegistry.finish({color="White"}).status=="invalid",
    "empty sessions cannot be accidentally committed")
Combat.hotkey("White",newSpell,nil,false)
Combat.hotkey("White",angel,nil,true)
Combat.hotkey("White",newSpell,nil,false)
Combat.hotkey("White",secondTarget,nil,true)
local after=TargetRegistry.read({color="White"})
assert(after.sourceGUID=="666661" and after.count==2,
    "first arrow locks the correct source and subsequent arrows add targets")
Combat.hotkey("White",newSpell,nil,false)
Combat.hotkey("White",angel,nil,true)
assert(TargetRegistry.read({color="White"}).count==2,"duplicate gestures are harmless")
assert(TargetRegistry.onChat("mtg done",{color="White"})==false)
assert(TargetRegistry.read({color="White"}).count==2)

print("Target registration source auto-detection, pre-existing arrows, multiple targets and commit tests passed.")
