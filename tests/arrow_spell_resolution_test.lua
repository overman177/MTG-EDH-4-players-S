-- Lua 5.2: Manual-stack arrow spell button + exact outbound target resolution.
local objects,states,logs,history={}, {}, {}, {}
local life={White=40,Red=40,Blue=40,Yellow=40}
self={
  getVectorLines=function() return {} end,
  setVectorLines=function() end,
  positionToLocal=function(p) return {x=p.x,y=p.y,z=p.z} end
}
Wait={time=function() end,frames=function() end}
Settings={combatEnabledByColor={White=true,Red=true,Yellow=true,Blue=true}}
function printToColor(msg,color) logs[#logs+1]={msg=msg,color=color} end
function getAllObjects() return {} end
local lotus={type="Custom_Model"}
function lotus.call(fn,params)
  assert(fn=="mtgReadSpellArrows")
  return mtgReadSpellArrows(params)
end
function getObjectFromGUID(guid)
  if guid=="185063" then return lotus end
  return objects[guid]
end
local exiles={}
local function makeTracker(color)
  return {call=function(method,p)
      if method=="mtgLifeReady" then return {ok=true,color=color,count=life[color]} end
      assert(method=="mtgGainLife")
      life[color]=life[color]+p.amount
      return {ok=true}
  end}
end
data={
  White={exileZone=true,lifeTracker=makeTracker("White")},
  Red={exileZone=true,lifeTracker=makeTracker("Red")},
  Blue={exileZone=true,lifeTracker=makeTracker("Blue")},
  Yellow={exileZone=true,lifeTracker=makeTracker("Yellow")}
}
function mtgGetZonePlacement(color,role)
  assert(role=="exileZone")
  return {x=1,y=2,z=3,color=color},{x=0,y=0,z=0}
end
local function card(guid,name,typeName,controller,owner,pt)
  local o={type="Card",tag="Card",dead=false,buttons={},pos={x=0,y=1,z=0},
           is_face_down=false,name=name,description="",transfers=0}
  function o.getGUID() return guid end
  function o.getName() return o.name end
  function o.getDescription() return o.description end
  function o.isDestroyed() return o.dead end
  function o.getButtons()
    for i,b in ipairs(o.buttons) do b.index=i-1 end
    return o.buttons
  end
  function o.createButton(b) b.index=#o.buttons;o.buttons[#o.buttons+1]=b end
  function o.removeButton(i) table.remove(o.buttons,i+1) end
  function o.getPosition() return o.pos end
  function o.getRotation() return {x=0,y=0,z=0} end
  function o.setPositionSmooth(p)
    o.pos=p;o.transfers=o.transfers+1
    exiles[guid]=p.color
  end
  function o.setRotationSmooth(r) end
  function o.hasTag(t) return false end
  objects[guid]=o
  states[guid]={status="ready",owner=owner,controller=controller,zone="Battlefield",
    types={typeName},typeLine=typeName=="creature" and "Creature" or typeName,
    currentPower=pt,damageMarked=0,encodedKeywords={}}
  return o
end
local swords=card("111111","Swords to Plowshares\nInstant 1CMC","instant","White","White")
local bolt=card("222222","Lightning Bolt\nInstant 1CMC","instant","White","White")
local strike=card("333333","Oblivion Strike\nSorcery 4CMC","sorcery","White","White")
local elf=card("444444","Llanowar Elves\nCreature 1CMC","creature","Red","Blue",7)
local angel=card("555555","Serra Angel\nCreature 5CMC","creature","White","White",4)
local other=card("666666","Other Creature\nCreature 1CMC","creature","Blue","Blue",2)
local unsupported=card("777777","Opt\nInstant 1CMC","instant","White","White")
function mtgCardMetadata(p)
  local obj=objects[p.guid];local kind="creature"
  if obj==swords or obj==bolt or obj==unsupported then kind="instant" end
  if obj==strike then kind="sorcery" end
  return {types={kind}}
end
function mtgCardState(p) return states[p.guid] end
function mtgSetCardDamage(p)
  states[p.guid].damageMarked=p.damage
  return {ok=true}
end
dofile("src/global/sections/00d_arrow-spell-resolution.lua")
Global={call=function(fn,pars)
  if fn=="mtgSupportedArrowSpell" then return mtgSupportedArrowSpell(pars) end
  if fn=="mtgResolveArrowSpell" then return mtgResolveArrowSpell(pars) end
  error("unexpected global method "..tostring(fn))
end}
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.baseLines={}
dofile("src/lotus/sections/06b_spell-buttons.lua")
local function arrow(src,dst,color)
  assert(Combat.addDefender(src.getGUID(),dst.getGUID(),color)==true)
end
-- Buttons appear only on supported instant/sorcery arrow sources.
arrow(swords,elf,"White")
assert(SpellButtons.visible["111111"])
assert(#swords.buttons==1 and swords.buttons[1].label=="RESOLVE")
assert(swords.buttons[1].function_owner==self)
arrow(unsupported,angel,"White")
assert(#unsupported.buttons==0,"unsupported Oracle text cannot auto-resolve")
arrow(elf,other,"White")
assert(#elf.buttons==0,"creature source cannot be a Resolve spell")
-- Malicious caller cannot forge an endpoint not connected by an arrow.
local bad=mtgResolveArrowSpell({sourceGUID="111111",caster="White",targets={"666666"}})
assert(not bad.ok and other.transfers==0 and elf.transfers==0)
-- Another player's arrow has a different source and is unaffected.
arrow(strike,angel,"Red")
-- Swords: target's controller Red gets seven life; owner's exile Blue.
SpellButtons.onClick(swords,"White")
assert(elf.transfers==1 and exiles["444444"]=="Blue",
    "only arrow destination exiled to owner's zone")
assert(life.Red==47 and life.White==40 and life.Blue==40,
    "controller, not owner/caster, gets life")
assert(#swords.buttons==0 and Combat.links["111111"]==nil)
assert(angel.transfers==0 and other.transfers==0)
assert(Combat.links["333333"]~=nil and Combat.links["777777"]~=nil,
    "other source arrows unaffected")
SpellButtons.onClick(swords,"White")
assert(elf.transfers==1 and life.Red==47,"cannot double-resolve without arrows")
-- Bolt marks damage; lethal cleanup and source card are manual.
arrow(bolt,angel,"White")
SpellButtons.onClick(bolt,"White")
assert(states["555555"].damageMarked==3 and angel.transfers==0)
assert(bolt.transfers==0 and #bolt.buttons==0)
-- Sorcery works with same button, but clicker must own its arrow.
SpellButtons.onClick(strike,"White")
assert(angel.transfers==0,"wrong arrow owner cannot resolve")
SpellButtons.onClick(strike,"Red")
assert(angel.transfers==1 and exiles["555555"]=="White")
assert(other.transfers==0)
-- More than the printed target count is rejected, with NO changes.
arrow(swords,other,"White")
arrow(swords,angel,"White")
local count=mtgResolveArrowSpell({
    sourceGUID="111111",caster="White",targets={"666666","555555"}})
assert(count.ok==false and other.transfers==0 and angel.transfers==1)
-- Source and destination must not be reversed.
assert(#SpellButtons.readArrows({
    sourceGUID="666666",color="White"
}).targets==0)
-- Encoder-added unrelated buttons are preserved.
swords.createButton({click_function="encode",tooltip="Other tool"})
Combat.clearSource("White","111111")
assert(#swords.buttons==1 and swords.buttons[1].tooltip=="Other tool",
    "removal only touches the Resolve button")
print("Arrow spells: source-only targeting, button lifecycle, Swords, Bolt, sorcery, permissions passed")
