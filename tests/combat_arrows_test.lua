-- Lua 5.2: vector lines, multi-defender, legacy cleanup.
Settings={combatEnabledByColor={White=true,Blue=true,Red=true,Yellow=true}}
local cards,lines,scheduled,timers={}, {}, {}, {}
local oldLines={{points={{-1,1,-1},{-2,1,-2}},color={0,1,0},thickness=0.05}}
local buttons={{index=0,tooltip="Settings"},{index=1,tooltip="MTG_COMBAT_FIGHT:a11111"},{index=2,tooltip="Other"}}
local xml={{tag="Panel",attributes={id="OtherPanel"}},{tag="Panel",attributes={id="MTG_Combat_Fight_Result_White"}}}
local anchor={destroyed=false}
anchor.destruct=function() anchor.destroyed=true end
UI={getXmlTable=function() return xml end,setXmlTable=function(t) xml=t end}
self={
    getVectorLines=function() return oldLines end,
    setVectorLines=function(v) lines=v end,
    positionToLocal=function(v) return {x=v[1] or v.x,y=v[2] or v.y,z=v[3] or v.z} end,
    getButtons=function() return buttons end,
    removeButton=function(i) table.remove(buttons,i+1);for n,b in ipairs(buttons) do b.index=n-1 end end
}
function spawnObject() error("combat cannot spawn objects") end
function getObjectsWithTag(tag) assert(tag=="MTG_Lotus_AutoFightAnchor");return {anchor} end
Wait={frames=function(fn) scheduled[#scheduled+1]=fn end,time=function(fn,n) timers[#timers+1]={fn=fn,delay=n} end}
local binds={["MTG: Remove Combat Target"]={fn=function() end,up=false}}
local resetCount, callOrder = 0, {}
function clearHotkeys()
    resetCount=resetCount+1
    binds={}
    callOrder[#callOrder+1]="clear"
end
function addHotkey(name,fn,up)
    callOrder[#callOrder+1]=name
    binds[name]={fn=fn,up=up}
end
function getObjectFromGUID(guid) return cards[guid] end
function printToColor() end
local function card(guid,x,z)
    local o={tag="Card",pos={x=x,y=1,z=z},dead=false}
    o.getGUID=function() return guid end
    o.isDestroyed=function() return o.dead end
    o.getPosition=function() return o.pos end
    cards[guid]=o;return o
end
local attacker=card("a11111",0,0)
local d1=card("d11111",4,0)
local d2=card("d22222",8,0)
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.load()
assert(resetCount==1,"hotkeys cleared during Lotus load")
assert(#callOrder==3 and callOrder[1]=="clear","clear precedes both registrations")
assert(callOrder[2]=="MTG: Declare Combat Target" and
       callOrder[3]=="MTG: Undo Combat Target","register Draw and Undo only")
assert(binds["MTG: Declare Combat Target"].up)
assert(binds["MTG: Undo Combat Target"].up==true,"Undo requires key release")
assert(binds["MTG: Remove Combat Target"]==nil,"only two hotkeys registered")
scheduled[1]()
assert(anchor.destroyed and #buttons==2 and #xml==1,"legacy cleanup only")
local function gesture(fn,def,atk)
    fn("White",def,def.pos,false);fn("White",atk,atk.pos,true)
end
local draw=binds["MTG: Declare Combat Target"].fn
local undo=binds["MTG: Undo Combat Target"].fn
gesture(draw,d1,attacker);gesture(draw,d2,attacker)
assert(Combat.countDefenders(Combat.links["a11111"])==2)
assert(#lines==5 and lines[1]==oldLines[1],"both arrows and base line")
gesture(draw,attacker,attacker)
assert(#lines==5,"stationary tap never deletes")
d1.pos.x=10;Combat.render()
local moved=false
for i=2,#lines do
    if math.abs(lines[i].points[2][1]-9.65)<0.08 then moved=true end
end
assert(moved,"moving card moves arrow")
undo("White",nil,nil,false)
assert(#lines==5,"short-press down does not undo")
undo("White",nil,nil,true)
assert(#lines==3,"short-press release removes latest arrow")
gesture(draw,d2,attacker)
assert(#lines==5,"drawing works after an undo")
undo("White",nil,nil,false)
assert(timers[#timers].delay==5.0,"long hold timer is five seconds")
local longHold=timers[#timers].fn
longHold()
assert(#lines==1 and not next(Combat.links),"long hold clears every own arrow")
gesture(draw,d2,attacker)
undo("White",nil,nil,true)
assert(#lines==3,"release after long hold does not undo")
Combat.onDestroy(d2)
assert(#lines==1 and not next(Combat.links),"destroy cleanup")
print("Combat vector line and two-key short/long Undo tests passed.")
