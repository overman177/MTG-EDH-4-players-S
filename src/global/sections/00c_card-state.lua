-- MTG CARD STATE v1 | four-player experimental, read-only Encoder adapter
-- Public: Global.call("mtgCardState", {guid="xxxxxx"})
--         Global.call("mtgSetCardController", {guid="xxxxxx", controller="Red", effectId="..."})
--         Global.call("mtgRecordSpellCast", {guid="xxxxxx", caster="Red", effectId="..."})
--         Global.call("mtgSetCardDamage", {guid="xxxxxx", damage=2, effectId="..."})
--         Global.call("mtgCardStateOnTurn", color), "mtgCardStateOnZoneEnter"(zone, obj)
-- No automatic controller changes from positions, player dragging or zones.
-- Encoder values are read live; unknown derived rules facts remain nil.
local MTG_STATE_COLORS = {White=true, Red=true, Yellow=true, Blue=true}
local MTG_STATE_MAX = 2048
local mtgStateRuntime = {}
local mtgStateCount = 0
local mtgStateTurn = 0
local mtgStateTurnColor = nil
local mtgStatePickups = {}

local function mtgStateColor(value)
    return type(value) == "string" and MTG_STATE_COLORS[value] and value or nil
end

local function mtgStateCard(guid)
    if type(guid) ~= "string" or #guid ~= 6 then return nil end
    local obj = getObjectFromGUID(guid)
    if obj == nil or obj.type ~= "Card" or obj.isDestroyed() then return nil end
    return obj
end

local function mtgStateSafe(callable)
    local ok, value = pcall(callable)
    if ok then return value end
    return nil
end

local function mtgStateNumber(value)
    if type(value) == "number" and value == value and value < math.huge
        and value > -math.huge then return value end
    if type(value) == "string" then return tonumber(value) end
    return nil
end

local function mtgStateRec(guid)
    local rec = mtgStateRuntime[guid]
    if rec ~= nil then return rec end
    if mtgStateCount >= MTG_STATE_MAX then
        -- Never drop an established controller change because of cache pressure.
        return nil
    end
    rec = {ready = nil, damage = nil}
    mtgStateRuntime[guid] = rec
    mtgStateCount = mtgStateCount + 1
    return rec
end

local function mtgStateEncoder(obj)
    local enc = Encoder
    if enc == nil then return nil, nil end
    local ok, exists = pcall(function()
        return enc.call("APIobjectExists", {obj=obj})
    end)
    if not ok or exists ~= true then return nil, nil end
    local all = mtgStateSafe(function()
        return enc.call("APIobjGetAllData", {obj=obj})
    end)
    if type(all) ~= "table" then return nil, nil end
    local unified = type(all.tyrantUnified) == "table" and all.tyrantUnified or nil
    return all, unified
end

local MTG_STATE_KEYWORDS = {
    mtg_deathtouchcounter="deathtouch", mtg_defendercounter="defender",
    mtg_doublestrikecounter="doubleStrike", mtg_firststrikecounter="firstStrike",
    mtg_flyingcounter="flying", mtg_hastecounter="haste",
    mtg_hexproofcounter="hexproof", mtg_indestructiblecounter="indestructible",
    mtg_lifelinkcounter="lifelink", mtg_menacecounter="menace",
    mtg_reachcounter="reach", mtg_tramplecounter="trample",
    mtg_vigilancecounter="vigilance"
}
local MTG_STATE_STATUS = {
    mtg_frozen="frozen", mtg_exert="exerted", mtg_monstrous="monstrous",
    mtg_renowned="renowned"
}
local MTG_STATE_NUMERIC_COUNTERS = {
    mtg_stuncounter="stun", mtg_suspendcounter="time",
    picounter="generic"
}
local function mtgStateEncodedValues(all, unified)
    local counters, keywords, status = {}, {}, {}
    if type(all) ~= "table" then return counters, keywords, status end
    counters.encodedById = {}
    local discovered = 0
    for id, value in pairs(all) do
        if type(id)=="string" and id:lower():find("counter",1,true)
            and mtgStateNumber(value) ~= nil and discovered < 64 then
            counters.encodedById[id] = mtgStateNumber(value)
            discovered = discovered + 1
        end
    end
    for id, name in pairs(MTG_STATE_NUMERIC_COUNTERS) do
        local n = mtgStateNumber(all[id])
        if n ~= nil then counters[name] = n end
    end
    for id, name in pairs(MTG_STATE_KEYWORDS) do
        local n = mtgStateNumber(all[id])
        if n ~= nil and n > 0 then
            keywords[name] = n
        elseif all[id] == true then
            keywords[name] = 1
        end
    end
    for id, name in pairs(MTG_STATE_STATUS) do
        if all[id] == true then status[name] = true end
    end
    if unified ~= nil then
        -- +1/+1 counters are NOT included in Unified's power/toughness delta.
        counters.plusOnePlusOne = mtgStateNumber(unified.plusOneCounters)
        -- Named counters may represent loyalty, defense, or another counter,
        -- depending on the card. Do not assume all are loyalty counters.
        counters.named = mtgStateNumber(unified.namedCounters)
    end
    return counters, keywords, status
end

local function mtgStateStats(unified, remote)
    local baseP, baseT, powerDelta, toughnessDelta
    local statSource = "unknown"
    local face = nil
    if type(unified) == "table" then
        face = tonumber(unified.activeFace) or 1
        local faces = type(unified.cardFaces) == "table" and unified.cardFaces or {}
        local current = faces[face]
        if type(current) == "table" and unified.hasParsed == true then
            baseP = current.basePower
            baseT = current.baseToughness
            if baseP ~= nil or baseT ~= nil then statSource = "encoder" end
        end
        powerDelta = mtgStateNumber(unified.power)
        toughnessDelta = mtgStateNumber(unified.toughness)
    end
    if statSource ~= "encoder" and type(remote) == "table" then
        baseP, baseT = remote.power, remote.toughness
        if baseP ~= nil or baseT ~= nil then statSource = "catalog" end
    end
    local p, t = mtgStateNumber(baseP), mtgStateNumber(baseT)
    local plus = unified and mtgStateNumber(unified.plusOneCounters) or nil
    local dp, dt = powerDelta or 0, toughnessDelta or 0
    local cc = plus or 0
    return {
        source=statSource, face=face,
        basePower=baseP, baseToughness=baseT,
        powerAdjustment=powerDelta, toughnessAdjustment=toughnessDelta,
        plusOneCounters=plus,
        currentPower=p and p + dp + cc or nil,
        currentToughness=t and t + dt + cc or nil,
        -- These are Encoder-displayed values, not complete MTG layer evaluation.
        complete=false
    }
end

local function mtgStateZone(obj)
    local guid = obj.getGUID()
    if type(data) ~= "table" then return nil, nil end
    -- Explicit priority: smaller overlapping zones before the broad playmat.
    local keys = {
        {"libraryZone","Library"}, {"graveyard","Graveyard"},
        {"exileZone","Exile"}, {"commandZone","Command"},
        {"landZone","Battlefield"}, {"playmat","Battlefield"}
    }
    for _, color in ipairs({"White","Red","Yellow","Blue"}) do
        local p = data[color]
        if p and p.libraryZone then
            -- Hand membership must not be confused with the nearby playmat.
            local handObj = Player and Player[color]
            if handObj then
                local held = mtgStateSafe(function() return handObj.getHandObjects(1) end)
                for _, card in ipairs(type(held)=="table" and held or {}) do
                    if card == obj then return "Hand", color end
                end
            end
        end
    end
    local zones = mtgStateSafe(function() return obj.getZones() end) or {}
    for _, z in ipairs(zones) do
        if z.type == "Hand" then return "Hand", nil end
    end
    -- Prefer querying recorded zone occupants with ignore_tags=true, since
    -- a scripting zone's tags can exclude unrelated cards in getZones().
    for _, entry in ipairs(keys) do
        for _, color in ipairs({"White","Red","Yellow","Blue"}) do
            local pd = data[color]
            local zone = pd and pd[entry[1]]
            if zone ~= nil then
                local contains = false
                for _, occupant in ipairs(mtgZoneObjects(zone)) do
                    if occupant == obj or
                       (type(occupant.getGUID)=="function" and occupant.getGUID()==guid) then
                        contains=true; break
                    end
                end
                if contains then return entry[2], color end
            end
        end
    end
    return "Other", nil
end

local function mtgStateController(owner, rec)
    -- Explicit controller from an effect wins; otherwise it defaults to owner.
    -- Encoder controllerColor and playmat location are intentionally NOT used.
    return mtgStateColor(rec and rec.controller) or owner
end

-- Guaranteed no zone scans, no network calls, no Encoder mutations, no hidden
-- card disclosure. Invoke only for a named card from scripting, not every frame.
function mtgCardState(params)
    local guid = type(params)=="table" and params.guid or params
    local obj = mtgStateCard(guid)
    if obj == nil then return {status="invalid"} end
    if obj.is_face_down then return {status="hidden", guid=guid} end
    local meta = mtgStateSafe(function() return mtgCardMetadata({guid=guid}) end) or {}
    local raw, unified = mtgStateEncoder(obj)
    local rec = mtgStateRuntime[guid]
    local owner = mtgStateColor(meta.owner)
    -- Legacy Unified tracks an imported ownerColor. Only use as fallback when
    -- the table's write-once GMNotes owner has never been established.
    local ownerSource = owner and "gmnotes" or nil
    if owner == nil and unified ~= nil then
        owner = mtgStateColor(unified.ownerColor)
        if owner ~= nil then ownerSource="encoder" end
    end
    local controller = mtgStateController(owner, rec)
    local zone, zoneColor = mtgStateZone(obj)
    local catalog = mtgStateSafe(function()
        return mtgCardCatalogGet({guid=guid})
    end)
    local remote = type(catalog)=="table" and catalog.remote or nil
    local stats = mtgStateStats(unified, remote)
    local counters, encodedKeywords, statuses = mtgStateEncodedValues(raw, unified)
    local rotation = mtgStateSafe(function() return obj.getRotation() end)
    local rotY = rotation and mtgStateNumber(rotation.y)
    -- TTS rotation convention used by existing Untap module: 90/270 = tapped.
    local tapped = nil
    if rotY ~= nil then tapped = (rotY % 180 > 45 and rotY % 180 < 135) end
    local readiness = rec and rec.ready
    local summoningSick = nil
    if zone == "Battlefield" and readiness ~= nil then
        -- Readiness is tracked on turn-start + explicit control events. Haste
        -- is separate; a hasty creature may act while still summoning sick.
        summoningSick = not readiness
    end
    return {
        status="ready", guid=guid, name=meta.name, owner=owner,
        ownerSource=ownerSource, controller=controller,
        controllerSource=rec and rec.controller and "effect" or
            (owner and "owner" or "unknown"),
        zone=zone, zoneColor=zoneColor,
        lastMovedBy=rec and rec.lastMovedBy or nil,
        lastMoveFrom=rec and rec.lastMoveFrom or nil,
        lastCastBy=rec and rec.lastCastBy or nil,
        lastCastFrom=rec and rec.lastCastFrom or nil,
        lastCastEffectId=rec and rec.lastCastEffectId or nil,
        types=meta.types, typeLine=meta.typeLine,
        manaValue=meta.manaValue or (remote and remote.manaValue),
        printedKeywords=meta.printedKeywords,
        scryfallId=meta.scryfallId or (remote and remote.scryfallId),
        oracleId=meta.oracleId or (remote and remote.oracleId),
        tapped=tapped, faceDown=false,
        basePower=stats.basePower, baseToughness=stats.baseToughness,
        powerAdjustment=stats.powerAdjustment, toughnessAdjustment=stats.toughnessAdjustment,
        currentPower=stats.currentPower, currentToughness=stats.currentToughness,
        powerToughnessSource=stats.source, activeFace=stats.face,
        powerToughnessComplete=stats.complete,
        counters=counters, encodedKeywords=encodedKeywords, statuses=statuses,
        loyalty=unified and unified.cardFaces and unified.cardFaces[tonumber(unified.activeFace) or 1]
            and unified.cardFaces[tonumber(unified.activeFace) or 1].isPlaneswalker
            and counters.named or nil,
        defense=unified and unified.cardFaces and unified.cardFaces[tonumber(unified.activeFace) or 1]
            and unified.cardFaces[tonumber(unified.activeFace) or 1].isBattle
            and counters.named or nil,
        damageMarked=rec and rec.damage or nil,
        summoningSick=summoningSick, controlReady=readiness,
        controlSinceTurn=rec and rec.controlSinceTurn or nil,
        enteredBattlefieldTurn=rec and rec.enteredBattlefieldTurn or nil,
        lastControlEffectId=rec and rec.lastControlEffectId or nil,
        turn=mtgStateTurn, turnColor=mtgStateTurnColor
    }
end

local function mtgStateEffectParams(params)
    local guid = type(params)=="table" and params.guid
    local effectId = type(params)=="table" and params.effectId
    if type(effectId)~="string" or effectId=="" or #effectId>120 then
        return nil, nil, "effectId is required"
    end
    local obj = mtgStateCard(guid)
    if obj == nil then return nil, nil, "invalid card" end
    local rec = mtgStateRec(guid)
    if rec == nil then return nil, nil, "state capacity reached" end
    return obj, rec, nil
end

-- The ONLY controller mutation path. Effects must call this explicitly;
-- dragging to another playmat never changes controller.
function mtgSetCardController(params)
    local obj, rec, err = mtgStateEffectParams(params)
    if err then return {ok=false,error=err} end
    local controller = mtgStateColor(params.controller)
    if not controller then return {ok=false,error="invalid controller seat"} end
    local owner = getCardNote(obj, "owner")
    if not mtgStateColor(owner) then
        local raw = mtgStateEncoder(obj)
        local tmp = type(raw)=="table" and raw.tyrantUnified or nil
        owner = mtgStateColor(tmp and tmp.ownerColor)
    end
    local prior = mtgStateController(mtgStateColor(owner), rec)
    if controller ~= prior then
        rec.controller = controller
        rec.controlSinceTurn = mtgStateTurn
        rec.ready = false
    end
    rec.lastControlEffectId = params.effectId
    -- The GMNote "owner" is never modified by a control-changing effect.
    -- Reflect controller in existing Unified display *if it is already enabled*.
    local enc = Encoder
    if enc ~= nil then
        pcall(function()
            if enc.call("APIobjectExists",{obj=obj}) and
                enc.call("APIobjIsPropEnabled",{obj=obj,propID="_MTG_Simplified_UNIFIED"}) then
                local decoded=enc.call("APIobjGetPropData",
                    {obj=obj,propID="_MTG_Simplified_UNIFIED"})
                if type(decoded)=="table" and type(decoded.tyrantUnified)=="table" then
                    decoded.tyrantUnified.controllerColor=controller
                    enc.call("APIobjSetPropData",
                        {obj=obj,propID="_MTG_Simplified_UNIFIED",data=decoded})
                    enc.call("APIrebuildButtons",{obj=obj})
                end
            end
        end)
    end
    return {ok=true,owner=mtgStateColor(owner),previous=prior,controller=controller}
end

function mtgRecordSpellCast(params)
    local obj, rec, err = mtgStateEffectParams(params)
    if err then return {ok=false,error=err} end
    local caster = mtgStateColor(params.caster)
    if not caster then return {ok=false,error="invalid caster seat"} end
    rec.lastCastBy = caster
    rec.lastCastEffectId = params.effectId
    rec.lastCastFrom = params.fromZone or rec.lastMoveFrom
    return {ok=true,caster=caster,fromZone=rec.lastCastFrom}
end

function mtgSetCardDamage(params)
    local _, rec, err = mtgStateEffectParams(params)
    if err then return {ok=false,error=err} end
    local damage = mtgStateNumber(params.damage)
    if damage == nil or damage < 0 or damage > 100000 then
        return {ok=false,error="invalid damage"}
    end
    rec.damage = damage
    return {ok=true,damageMarked=damage}
end

-- Track observed zone/turn history for readiness. No controller assignment.
function mtgCardStateOnZoneEnter(zone, obj)
    if obj == nil or obj.type~="Card" then return end
    local guid = obj.getGUID()
    local rec = mtgStateRec(guid)
    if not rec then return end
    if zone ~= nil and zone.type == "Hand" then
        rec.battlefield=false
        rec.ready=nil
        return
    end
    if type(data)~="table" then return end
    for _, color in ipairs({"White","Red","Yellow","Blue"}) do
        local pd = data[color]
        if pd and (zone==pd.playmat or zone==pd.landZone) then
            if rec.battlefield ~= true then
                rec.ready=false
                rec.battlefield=true
                rec.enteredBattlefieldTurn=mtgStateTurn
            end
            return
        end
        if pd and (zone==pd.libraryZone or zone==pd.graveyard
            or zone==pd.exileZone or zone==pd.commandZone) then
            rec.battlefield=false
            rec.ready=nil
            return
        end
    end
end

function mtgCardStateOnTurn(color)
    if not mtgStateColor(color) then return end
    mtgStateTurn = mtgStateTurn + 1
    mtgStateTurnColor = color
    -- Only scan on turn change; never infer controller from mat position.
    if type(data)=="table" then
        for _, seat in ipairs({"White","Red","Yellow","Blue"}) do
            local pd = data[seat]
            local zone = pd and pd.playmat
            if zone~=nil then
                for _, obj in ipairs(mtgZoneObjects(zone)) do
                    if obj and obj.type=="Card" then
                        local guid=obj.getGUID()
                        local meta=mtgStateSafe(function()
                            return mtgCardMetadata({guid=guid})
                        end) or {}
                        local raw, united=mtgStateEncoder(obj)
                        local owner=mtgStateColor(meta.owner) or
                            mtgStateColor(united and united.ownerColor)
                        local rec=mtgStateRuntime[guid]
                        local controller=mtgStateController(owner,rec)
                        if controller==color then
                            rec=rec or mtgStateRec(guid)
                            if rec then rec.ready=true; rec.battlefield=true end
                        end
                    end
                end
            end
        end
    end
    -- Damage should be removed during cleanup; without a cleanup hook,
    -- clear the engine's tracked damage no later than the next turn start.
    for _, rec in pairs(mtgStateRuntime) do
        if rec.damage ~= nil then rec.damage=0 end
    end
end

function mtgCardStateOnPickUp(color, obj)
    if obj==nil or obj.type~="Card" or not mtgStateColor(color) then return end
    local guid=obj.getGUID()
    local zone = mtgStateZone(obj)
    mtgStatePickups[guid] = {color=color,zone=zone}
end

function mtgCardStateOnDrop(color, obj)
    if obj==nil or obj.type~="Card" then return end
    local guid=obj.getGUID()
    local pickup=mtgStatePickups[guid]
    mtgStatePickups[guid]=nil
    if not pickup or pickup.color~=color then return end
    local rec=mtgStateRec(guid)
    if rec then
        rec.lastMovedBy=color
        rec.lastMoveFrom=pickup.zone
    end
end

function mtgCardStateOnDestroy(obj)
    if obj==nil or type(obj.getGUID)~="function" then return end
    local guid=obj.getGUID()
    if mtgStateRuntime[guid]~=nil then
        mtgStateRuntime[guid]=nil
        mtgStateCount=math.max(0,mtgStateCount-1)
    end
    mtgStatePickups[guid]=nil
end

function mtgCardStateSave()
    return {turn=mtgStateTurn,turnColor=mtgStateTurnColor,runtime=mtgStateRuntime}
end

function mtgCardStateLoad(saved)
    mtgStateRuntime={}
    mtgStateCount=0
    mtgStateTurn=0
    mtgStateTurnColor=nil
    mtgStatePickups={}
    if type(saved)~="table" then return end
    mtgStateTurn=tonumber(saved.turn) or 0
    mtgStateTurnColor=mtgStateColor(saved.turnColor)
    if type(saved.runtime)=="table" then
        for guid, rec in pairs(saved.runtime) do
            if type(guid)=="string" and #guid==6 and type(rec)=="table"
                and mtgStateCount<MTG_STATE_MAX then
                mtgStateRuntime[guid]=rec
                mtgStateCount=mtgStateCount+1
            end
        end
    end
end

-- Unique Global callbacks: existing onObjectDropped/zone handlers dispatch
-- to this module rather than being replaced.
function onObjectPickUp(playerColor, obj)
    mtgCardStateOnPickUp(playerColor, obj)
end

function onObjectDestroy(obj)
    mtgCardStateOnDestroy(obj)
end

-- New TTS drop callback (existing legacy onObjectDropped also forwards here).
function onObjectDrop(playerColor, obj)
    mtgCardStateOnDrop(playerColor, obj)
end
