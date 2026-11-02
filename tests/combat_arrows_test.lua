-- Lotus multi-defender ARROWS ONLY regression, runnable with Lua 5.2.
Settings = {combatEnabledByColor={White=true, Blue=true, Red=true, Yellow=true}}
local cards, lines, scheduled, timers = {}, {}, {}, {}
local originalLines = {
    {points={{-1,1,-1},{-2,1,-2}},color={0,1,0},thickness=0.05}
}
local dummyButtons={
    {index=0,tooltip="Settings",click_function="settingsButtonClick"},
    {index=1,tooltip="MTG_COMBAT_FIGHT:a11111",click_function="obsoleteCombat"},
    {index=2,tooltip="Other feature",click_function="otherButton"}
}
local xml={
    {tag="Panel",attributes={id="MTG_Settings_Tab_General"}},
    {tag="Panel",attributes={id="MTG_Combat_Fight_Result_White"}},
    {tag="Panel",attributes={id="MTG_Combat_Fight_Result_Blue"}},
    {tag="Panel",attributes={id="OtherPanel"}}
}
local oldAnchor={destroyed=false}
oldAnchor.destruct=function() oldAnchor.destroyed=true end
local uiResets=0
UI = {
    getXmlTable=function() return xml end,
    setXmlTable=function(nodes) xml=nodes; uiResets=uiResets+1 end
}
self = {
    getVectorLines=function() return originalLines end,
    setVectorLines=function(v) lines=v end,
    positionToLocal=function(v) return {x=v[1] or v.x, y=v[2] or v.y, z=v[3] or v.z} end,
    getButtons=function() return dummyButtons end,
    removeButton=function(index)
        table.remove(dummyButtons,index+1)
        for i,b in ipairs(dummyButtons) do b.index=i-1 end
    end
}
function spawnObject() error("Combat arrows must never spawn objects") end
function getObjectsWithTag(tag)
    assert(tag=="MTG_Lotus_AutoFightAnchor","only old marker tags are cleaned")
    return {oldAnchor}
end
Wait={
    frames=function(fn,n) assert(n==30,"deferred cleanup"); scheduled[#scheduled+1]=fn end,
    time=function(fn,n) timers[#timers+1]={fn,n} end
}
local config
function addHotkey(name,fn,up)
    assert(name=="MTG: Declare Combat Target" and up)
    config=fn
end
local messages={}
function printToColor(msg,col) messages[#messages+1]={msg,col} end
function getObjectFromGUID(guid) return cards[guid] end
local function card(guid,x,z)
    local o={tag="Card",guid=guid,pos={x=x,y=1,z=z},gone=false}
    o.getGUID=function() return o.guid end
    o.isDestroyed=function() return o.gone end
    o.getPosition=function() return o.pos end
    cards[guid]=o
    return o
end
local attacker=card("a11111",0,0)
local otherAttacker=card("b22222",-4,0)
local defA=card("c33333",4,0)
local defB=card("d44444",8,0)
local defC=card("e55555",5,4)
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.load()
assert(type(config)=="function","custom hotkey still registered")
assert(#scheduled==1 and #dummyButtons==3, "cleanup deferred until after load")
scheduled[1]()
assert(oldAnchor.destroyed,"old AUTOFIGHT world object removed")
assert(#dummyButtons==2 and dummyButtons[1].tooltip=="Settings" and
       dummyButtons[2].tooltip=="Other feature","other Lotus buttons preserved")
assert(#xml==2 and xml[1].attributes.id=="MTG_Settings_Tab_General"
       and xml[2].attributes.id=="OtherPanel","old report panels removed only")
assert(uiResets==1,"UI rebuilt only for removed legacy result panels")
local function gesture(color,def,atk,downAt,upAt)
    local startPos = downAt or (def and def.pos)
    local endPos = upAt or (atk and atk.pos)
    config(color,def,startPos,false)
    config(color,atk,endPos,true)
end
gesture("White",defA,attacker)
assert(Combat.countDefenders(Combat.links[attacker.guid])==1,"one defender")
assert(#lines==3,"existing line + two arrow segments")
assert(lines[1]==originalLines[1],"Lotus original vector lines preserved")
gesture("White",defB,attacker)
assert(Combat.countDefenders(Combat.links[attacker.guid])==2,"two defenders")
assert(#lines==5,"two arrows from same attacker")
gesture("White",defC,attacker)
assert(Combat.countDefenders(Combat.links[attacker.guid])==3,"three defenders")
assert(#lines==7,"three arrows with independent arrowheads")
-- Simulate a TTS hover collision: the hotkey reports attacker on both
-- events, but the pointer moved between cards. Keep all three arrows.
gesture("White",attacker,attacker, {x=0,z=0}, {x=4,z=0})
assert(Combat.countDefenders(Combat.links[attacker.guid])==3 and #lines==7,
       "moved cursor with same hovered attacker preserves all arrows")
defA.pos.x=9
Combat.render()
local moved = false
for i=2,#lines do
    local endpoint = lines[i].points[2]
    if math.abs(endpoint[1] - 8.65) < 0.07 then moved = true end
end
assert(moved,"arrow follows moved defender")
gesture("White",defB,attacker)
assert(Combat.countDefenders(Combat.links[attacker.guid])==3 and #lines==7,
       "repeated declaration preserves all 3 arrows")
gesture("White",defB,defB)
assert(Combat.countDefenders(Combat.links[attacker.guid])==2 and #lines==5,
       "tap defender removes only its arrow")
assert(Combat.links[attacker.guid].defenders[defA.guid] and
       Combat.links[attacker.guid].defenders[defC.guid],
       "remaining defender arrows kept")
gesture("Blue",defB,otherAttacker)
assert(#lines==7,"independent other player arrow")
gesture("White",attacker,attacker)
assert(Combat.links[attacker.guid]==nil and
       Combat.links[otherAttacker.guid]~=nil,"tap on attacker clears all its defenders only")
assert(#lines==3,"only other attack arrow + original line remain")
Combat.onDestroy(defB)
assert(Combat.links[otherAttacker.guid]==nil and #lines==1,
       "destroyed defender removes its linked arrow")
gesture("Blue",defC,otherAttacker)
Combat.clear("Blue")
assert(next(Combat.links)==nil and #lines==1,"personal clear removes only combat arrow")
assert(#dummyButtons==2,"never changed other Lotus buttons")
assert(#xml==2 and uiResets==1,"no new fight popup or UI updates")
print("Combat multi-defender, arrows-only, and legacy cleanup tests passed.")
