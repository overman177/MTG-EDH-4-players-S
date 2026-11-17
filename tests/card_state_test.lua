-- Lua 5.2 mock regression: live Encoder stats + explicit controller lifecycle.
local cards, reads, writes = {}, 0, 0
local whiteMat={type="Scripting"}
local redMat={type="Scripting"}
local blueMat={type="Scripting"}
local whiteGY={type="Scripting"}
local handCards={}
local zones={White=whiteMat, Red=redMat, Blue=blueMat}
local face={basePower="2",baseToughness="3"}
local stats={
    hasParsed=true,activeFace=1,
    cardFaces={face},
    power=1,toughness=-1,plusOneCounters=2,namedCounters=4,
    ownerColor="Blue",controllerColor="Blue",
}
local values={
    tyrantUnified=stats,mtg_flyingcounter=1,
    mtg_stuncounter=2,mtg_frozen=true,
    mtg_suspendcounter=3,picounter=7,
}
local spell={type="Card",tag="Card",face=false,dead=false,rotation={y=90}}
function spell.getGUID() return "abcdef" end
function spell.getName() return "Test Creature" end
function spell.isDestroyed() return spell.dead end
function spell.getRotation() return spell.rotation end
function spell.getZones() return {} end
cards.abcdef=spell
function getObjectFromGUID(guid) return cards[guid] end
function mtgZoneObjects(zone)
    if zone==redMat or zone==blueMat or zone==whiteGY then
        return zone.objects or {}
    end
    return {}
end
data={
    White={playmat=whiteMat,graveyard=whiteGY},
    Red={playmat=redMat},
    Blue={playmat=blueMat}
}
redMat.objects={spell}
Player={}
for _,color in ipairs({"White","Red","Blue","Yellow"}) do
    Player[color]={getHandObjects=function() return handCards end}
end
function mtgCardMetadata(pars)
    return {name="Test Creature",owner="Blue",types={"creature"},
        typeLine="Creature",manaValue=2,
        printedKeywords={"mtg_flyingcounter"}}
end
function mtgCardCatalogGet(pars)
    return {status="ready",remote={power=2,toughness=3,manaValue=2}}
end
function getCardNote(obj,key) if key=="owner" then return "Blue" end end
Encoder={call=function(method,pars)
    if method=="APIobjectExists" then return true end
    if method=="APIobjGetAllData" then reads=reads+1;return values end
    if method=="APIobjIsPropEnabled" then
        assert(pars.propID=="_MTG_Simplified_UNIFIED")
        return true
    end
    if method=="APIobjGetPropData" then return {tyrantUnified=stats} end
    if method=="APIobjSetPropData" then
        writes=writes+1;stats=pars.data.tyrantUnified
        values.tyrantUnified=stats
        return
    end
    if method=="APIrebuildButtons" then return end
    error("Unexpected encoder call "..tostring(method))
end}

dofile("src/global/sections/00c_card-state.lua")
local s=mtgCardState({guid="abcdef"})
assert(s.status=="ready" and s.owner=="Blue" and s.controller=="Blue",
    "ownership from notes and default controller, not red playmat")
assert(s.zone=="Battlefield" and s.zoneColor=="Red")
assert(s.powerToughnessSource=="encoder")
assert(s.basePower=="2" and s.baseToughness=="3")
assert(s.currentPower==5 and s.currentToughness==4,
    "2+1+2 / 3-1+2 includes +1/+1 counters once")
assert(s.counters.plusOnePlusOne==2 and s.counters.named==4)
assert(s.counters.stun==2 and s.counters.time==3 and s.counters.generic==7)
assert(s.counters.encodedById.mtg_stuncounter==2)
assert(s.encodedKeywords.flying==1 and s.statuses.frozen)
assert(s.tapped==true)
spell.rotation={y=0}
assert(mtgCardState({guid="abcdef"}).tapped==false,
    "untapped is a known false, not an unknown nil")
spell.rotation={y=90}
assert(s.damageMarked==nil and s.summoningSick==nil,
    "unobserved damage and control readiness must be unknown")
assert(writes==0,"card queries must not mutate Encoder")

-- Changes in existing UI values are reflected without caching or new polls.
stats.plusOneCounters=4
values.mtg_stuncounter=5
local updated=mtgCardState("abcdef")
assert(updated.currentPower==7 and updated.currentToughness==6)
assert(updated.counters.stun==5 and writes==0,
    "read current Encoder values on each requested query")

mtgCardStateOnZoneEnter(redMat,spell)
assert(mtgCardState({guid="abcdef"}).summoningSick==true)
mtgCardStateOnTurn("Blue")
assert(mtgCardState({guid="abcdef"}).summoningSick==false,
    "controller has had permanent since start of their turn")
assert(mtgCardState({guid="abcdef"}).controller=="Blue")
mtgCardStateOnTurn("Red")
assert(mtgCardState({guid="abcdef"}).controller=="Blue",
    "turn and battlefield must not change controller")
assert(mtgSetCardController({guid="abcdef",controller="Red"}).ok==false,
    "only explicit effects with an ID may change controller")
local changed=mtgSetCardController({
    guid="abcdef",controller="Red",effectId="steal-effect-01"})
assert(changed.ok and changed.previous=="Blue")
s=mtgCardState({guid="abcdef"})
assert(s.owner=="Blue" and s.controller=="Red" and s.summoningSick==true)
assert(stats.controllerColor=="Red" and writes==1,"mirror effect into Unified")
mtgCardStateOnTurn("Blue")
assert(mtgCardState({guid="abcdef"}).summoningSick==true,
    "another player's turn doesn't grant readiness")
mtgCardStateOnTurn("Red")
assert(mtgCardState({guid="abcdef"}).summoningSick==false,
    "control readiness updates at new controller's turn")

local cast=mtgRecordSpellCast({
    guid="abcdef",caster="White",effectId="spell-3",fromZone="Exile"})
assert(cast.ok and cast.fromZone=="Exile")
assert(mtgSetCardDamage({guid="abcdef",damage=3,effectId="damage-4"}).ok)
s=mtgCardState({guid="abcdef"})
assert(s.lastCastBy=="White" and s.lastCastFrom=="Exile")
assert(s.damageMarked==3)
local saved=mtgCardStateSave()
mtgCardStateLoad(saved)
assert(mtgCardState({guid="abcdef"}).controller=="Red",
    "effect controller survives saved-state restore")
assert(mtgCardState({guid="abcdef"}).damageMarked==3)
mtgCardStateOnTurn("White")
assert(mtgCardState({guid="abcdef"}).damageMarked==0)

-- Hidden cards expose no card metadata or Encoder stats.
spell.is_face_down=true
s=mtgCardState({guid="abcdef"})
assert(s.status=="hidden" and s.owner==nil and s.currentPower==nil)
spell.is_face_down=false
mtgCardStateOnDestroy(spell)
assert(mtgCardState({guid="abcdef"}).controller=="Blue",
    "discard runtime controller when card object is destroyed")
print("Card state: Encoder stats/counters, ownership, explicit control, readiness, cast/damage, persistence passed")
