-- TTS-free regression for world-space AUTOFIGHT anchor and damage estimate.
Settings = {combatEnabledByColor={White=true,Blue=true,Red=true,Yellow=true},
            playerColor=function(p) return p.color end}
local cards, anchors, reports, uiNodes, vectorLines, deferred = {}, {}, {}, {}, {}, {}
local unique = 0
local lotusButtons = {{label="Existing Lotus Settings"}}
self = {
  getButtons = function() return lotusButtons end,
  getVectorLines = function() return {} end,
  setVectorLines = function(lines) vectorLines=lines end,
  positionToLocal = function(pos) return {x=pos.x,y=pos.y,z=pos.z} end,
  getGUID = function() return "185063" end,
}
UI = {
  getXmlTable = function() return uiNodes end,
  setXmlTable = function(tbl) uiNodes=tbl end,
  setAttribute = function(id,attribute,value) reports[id..":"..attribute]=value end,
}
Wait = {time = function() end,frames = function(f,n)
  assert(n==4,"XML first-use delay")
  deferred[#deferred+1]=f
end}
function addHotkey() end
function getObjectFromGUID(guid) return cards[guid] end
function printToColor(msg) error("Unexpected fallback: "..msg) end
function spawnObject(opts)
  assert(opts.type=="BlockSquare","must use small ordinary world-space button host")
  unique=unique+1
  local o={guid="zone"..unique,point=opts.position,buttons={},destroyed=false,
           tag="Scripting",tags={}}
  o.getGUID=function() return o.guid end
  o.setPosition=function(pos) o.point=pos end
  o.setName=function(name) o.name=name end
  o.addTag=function(tag) o.tags[tag]=true end
  o.setColorTint=function(tint) o.tint=tint end
  o.lock=function() o.locked=true end
  o.createButton=function(params) o.buttons[#o.buttons+1]=params end
  o.destruct=function() o.destroyed=true end
  anchors[#anchors+1]=o
  opts.callback_function(o)
  return o
end
local function card(guid,name,p,t,x,modP,modT,plus,keywords)
  local o={tag="Card",guid=guid,name=name,point={x=x,y=1,z=0}}
  o.getGUID=function() return guid end
  o.getName=function() return name end
  o.getPosition=function() return o.point end
  o.isDestroyed=function() return false end
  o.stats={cardFaces={{basePower=p,baseToughness=t}},activeFace=1,
    power=modP or 0,toughness=modT or 0,plusOneCounters=plus or 0}
  o.keywords=keywords or {}
  cards[guid]=o
  return o
end
local attacker=card("a11111","Mother of Runes",2,2,0,1,0,1)
local defender=card("b22222","Defender",3,3,4,0,1,0)
local defender2=card("c33333","Other defender",2,1,6)
local attacker2=card("d44444","Another attacker",3,2,-4)
local encoder={call=function(method,p)
  assert(method=="APIobjGetPropData")
  if p.propID=="_MTG_Simplified_UNIFIED" then
    return {tyrantUnified=p.obj.stats}
  end
  if p.propID=="πKeywords" then
    return {activeIcons=p.obj.keywords}
  end
end}
Global={getVar=function(name) if name=="Encoder" then return encoder end end}
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.baseLines={}
Combat.anchors={}
Combat.links={[attacker.guid]={by="White",defenders={[defender.guid]=true}}}
local stat=Combat.readStats(attacker)
assert(stat.known and stat.power==4 and stat.toughness==3,"manual stats + counters")
local outcome=Combat.evaluate(attacker,defender)
assert(outcome.attackerDamage==4 and outcome.defenderDamage==3,"combat damage")
assert(outcome.defenderLethal and outcome.attackerLethal,"lethal calculation")
Combat.render()
assert(#anchors==1 and #anchors[1].buttons==1,"anchor created exactly once")
assert(anchors[1].buttons[1].label=="AUTOFIGHT","button renamed AUTOFIGHT")
assert(anchors[1].buttons[1].function_owner==self,"callback owned by Lotus")
assert(anchors[1].tint.a==0 and anchors[1].locked,"invisible locked anchor")
assert(anchors[1].buttons[1].scale[1]>1,"button size compensated for anchor scale")
assert(anchors[1].point.x==2,"world midpoint")
assert(#vectorLines==2,"single arrow")
assert(#lotusButtons==1,"no distant Lotus object buttons")
local fn=anchors[1].buttons[1].click_function
assert(type(_G[fn])=="function","click handler registered")
_G[fn](anchors[1],"White",false)
assert(#uiNodes==4,"private report panels")
assert(#deferred==1,"first display waits for TTS XML rebuild")
deferred[1]()
assert(reports["MTG_Combat_Fight_Result_White_body:text"]:find("Attacker deals 4",1,true),
       "click opens damage report")
Combat.closeEstimate({color="White"})
assert(reports["MTG_Combat_Fight_Result_White:active"]=="false","close report")
-- Follow movements; do not respawn button on every refresh.
defender.point.x=8
Combat.render()
assert(anchors[1].point.x==4 and #anchors==1,"button follows midpoint")
-- Add second defender: keep two arrows but remove AUTOFIGHT.
Combat.toggleDefender(attacker.guid,defender2.guid,"White")
assert(Combat.countDefenders(Combat.links[attacker.guid])==2,"multi-blocker state")
assert(#vectorLines==4,"two attacker-to-defender arrows")
assert(anchors[1].destroyed and Combat.anchors[attacker.guid]==nil,
       "AUTOFIGHT hidden when two blockers")
assert(_G[fn]==nil,"click callback cleaned")
-- Stale click must not show results when there are multiple defenders.
Combat.fightClick(attacker.guid,"White")
assert(#deferred==1,"no additional results for multi-defender attacker")
-- Remove second defender: AUTOFIGHT reappears at first arrow's midpoint.
Combat.toggleDefender(attacker.guid,defender2.guid,"White")
assert(#anchors==2 and #anchors[2].buttons==1 and not anchors[2].destroyed,
       "AUTOFIGHT returns for single defender")
-- Two independent attackers, each one defender, get separate buttons.
Combat.toggleDefender(attacker2.guid,defender.guid,"Blue")
assert(#anchors==3 and #vectorLines==4,"one button per distinct single attack")
-- Invalid stats must report unknown, never guess.
attacker.stats.cardFaces[1].basePower="*"
assert(not Combat.evaluate(attacker,defender).known,"variable stats guarded")
attacker.stats.cardFaces[1].basePower=2
attacker.keywords={"mtg_deathtouchcounter"}
assert(#Combat.evaluate(attacker,defender).notes>0,"keyword warning")
-- Tapping attacker clears only its declaration and button.
Combat.hotkey("White",attacker,nil,false)
Combat.hotkey("White",attacker,nil,true)
assert(Combat.links[attacker.guid]==nil and anchors[2].destroyed,
       "single attack cleared")
assert(Combat.links[attacker2.guid]~=nil and not anchors[3].destroyed,
       "unrelated attack retained")
Combat.clear("Blue")
assert(Combat.links[attacker2.guid]==nil and anchors[3].destroyed,
       "clear own arrows removes marker")
print("World-space AUTOFIGHT and multi-defender tests passed.")
