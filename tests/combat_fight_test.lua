-- TTS-free Lua 5.2 integration checks for read-only Lotus FIGHT.
Settings = {combatEnabledByColor={White=true,Blue=true,Red=true,Yellow=true},
            playerColor=function(p) return p.color end}
local cards, reports = {}, {}
local buttons, vectorLines, uiNodes, changes = {
    {index=0, tooltip="Unrelated Lotus button", click_function="settingsButtonClick"}
}, {}, {}, 0
local function fixIndexes()
    for i, btn in ipairs(buttons) do btn.index = i-1 end
end
self = {
    getVectorLines = function() return {} end,
    setVectorLines = function(v) vectorLines=v end,
    positionToLocal = function(v) return {x=v.x,y=v.y,z=v.z} end,
    getButtons = function() return buttons end,
    createButton = function(p)
        buttons[#buttons+1] = p; fixIndexes()
    end,
    editButton = function(p)
        local b = buttons[p.index+1]
        assert(b, "edited missing button")
        if p.position then b.position=p.position end
        changes=changes+1
    end,
    removeButton = function(i)
        table.remove(buttons,i+1)
        fixIndexes()
    end,
    getGUID = function() return "185063" end,
}
UI = {
    getXmlTable = function() return uiNodes end,
    setXmlTable = function(x) uiNodes=x end,
    setAttribute = function(id,k,v) reports[id..":"..k]=v end
}
local deferred = {}
Wait = {time = function() end, frames = function(fn, n)
    assert(n == 4, "wait for XML rebuild")
    deferred[#deferred + 1] = fn
end}
function addHotkey() end
local function card(guid,name,p,t,x,modifierP,modifierT,plus,keywords)
    local result = {tag="Card",guid=guid,name=name,point={x=x,y=1,z=0}}
    result.getGUID=function() return guid end
    result.isDestroyed=function() return false end
    result.getName=function() return name end
    result.getPosition=function() return result.point end
    result.stats={
      cardFaces={{basePower=p,baseToughness=t}},activeFace=1,
      power=modifierP or 0,toughness=modifierT or 0,plusOneCounters=plus or 0
    }
    result.keywords=keywords or {}
    cards[guid]=result
    return result
end
local attacker=card("a11111","Mother of Runes",2,2,0,1,0,1)
local defender=card("b22222","Defender card",3,3,4,0,1,0)
function getObjectFromGUID(guid) return cards[guid] end
function printToColor() error("Fallback message should not be used in tests") end
Global={getVar=function(_,key) end}
local encoder={call=function(method,p)
    if method ~= "APIobjGetPropData" then return nil end
    if p.propID=="_MTG_Simplified_UNIFIED" then
        return {tyrantUnified=p.obj.stats}
    elseif p.propID=="πKeywords" then
        return {activeIcons=p.obj.keywords}
    end
end}
Global.getVar=function(name) if name=="Encoder" then return encoder end end

dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.baseLines = {}
Combat.buttonPositions = {}
Combat.links={ [attacker.guid] = {target=defender.guid,by="White"} }

local stats=Combat.readStats(attacker)
assert(stats.known and stats.power==4 and stats.toughness==3,"counter/modifier P/T")
local other=Combat.readStats(defender)
assert(other.known and other.power==3 and other.toughness==4,"defender P/T")
local result=Combat.evaluate(attacker,defender)
assert(result.known and result.attackerDamage==4 and result.defenderDamage==3,
       "combat damage")
assert(result.attackerLethal and result.defenderLethal,"simultaneous lethal")
Combat.render()
assert(#buttons==2,"one FIGHT button plus existing settings button")
assert(buttons[1].click_function=="settingsButtonClick","existing button intact")
assert(buttons[2].label=="FIGHT","fight marker created")
assert(#vectorLines==2,"body and arrowhead unchanged")
assert(buttons[2].position[1]==2,"marker midpoint")
local fightName=buttons[2].click_function
assert(type(_G[fightName])=="function","per-attacker click registered")
_G[fightName](self,"White",false)
assert(#uiNodes==4,"one report panel per player")
assert(#deferred==1,"first result update deferred until UI rebuild")
assert(reports["MTG_Combat_Fight_Result_White_body:text"]==nil,
       "no premature XML attribute writes")
deferred[1]()
local report=reports["MTG_Combat_Fight_Result_White_body:text"]
assert(report and report:find("Mother of Runes",1,true),"clicked report correct")
assert(report:find("Attacker deals 4",1,true),"result displays damage")
assert(reports["MTG_Combat_Fight_Result_White:active"]=="true",
       "visible for clicker")
Combat.closeEstimate({color="White"})
assert(reports["MTG_Combat_Fight_Result_White:active"]=="false",
       "close panel")
Combat.showResult("Blue","Other player's outcome")
assert(reports["MTG_Combat_Fight_Result_Blue_body:text"]=="Other player's outcome",
       "independent per-color panel")
-- Test movement: preserve fight callback and update its position.
defender.point.x=8
Combat.render()
assert(buttons[2].position[1]==4 and changes>0,"moving cards repositions FIGHT")
-- Unsupported base stat yields uncertainty, not invented numeric P/T.
attacker.stats.cardFaces[1].basePower="*"
assert(not Combat.readStats(attacker).known,"nonnumeric power is unknown")
assert(not Combat.evaluate(attacker,defender).known,"unknown avoids damage verdict")
attacker.stats.cardFaces[1].basePower=2
attacker.keywords={"mtg_deathtouchcounter"}
assert(#Combat.evaluate(attacker,defender).notes>0,"keyword warning")
-- Clear arrow removes only owned button; unrelated Settings button stays.
Combat.links={}
Combat.render()
assert(#buttons==1 and buttons[1].click_function=="settingsButtonClick",
       "FIGHT removed, unrelated button preserved")
assert(_G[fightName]==nil,"removed callback cleaned up")
assert(#vectorLines==0,"arrows removed")
print("Combat FIGHT button/stat/overlay tests passed.")
