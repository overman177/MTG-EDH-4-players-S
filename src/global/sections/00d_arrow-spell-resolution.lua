-- MTG ARROW SPELL RESOLUTION | four-player opt-in prototype (NO STACK)
-- The Lotus Resolve button calls Global.call("mtgResolveArrowSpell", params).
-- Only explicit allowlisted effects execute. Never interpret arbitrary rules text.
-- No spell card movement; the players handle mana, timing, priority and stack.
-- Never scan the entire table, never mutate objects unrelated to arrow targets.
local MTG_SPELL_SUPPORTED = {
    ["swords to plowshares"] = {type="instant", effect="exile_life", count=1},
    ["oblivion strike"] = {type="sorcery", effect="exile", count=1},
    ["lightning bolt"] = {type="instant", effect="creature_damage3", count=1}
}
local MTG_SPELL_COLORS = {White=true,Red=true,Blue=true,Yellow=true}
local mtgSpellResolving = {}

local function mtgSpellResult(ok, message)
    return {ok=ok, message=message}
end

local function mtgSpellFirstLine(name)
    return (tostring(name or ""):match("^[^\r\n]*") or "")
        :gsub("^%s+", ""):gsub("%s+$", "")
end

local function mtgSpellType(metadata, wanted)
    if type(metadata)~="table" or type(metadata.types)~="table" then return false end
    for _, value in ipairs(metadata.types) do
        if value == wanted then return true end
    end
    return false
end

function mtgSupportedArrowSpell(params)
    local guid=type(params)=="table" and params.guid or params
    if type(guid)~="string" then return {supported=false} end
    local obj=getObjectFromGUID(guid)
    if obj==nil or obj.type~="Card" or obj.is_face_down or obj.isDestroyed() then
        return {supported=false}
    end
    local name=mtgSpellFirstLine(obj.getName())
    local kind=MTG_SPELL_SUPPORTED[name:lower()]
    if kind==nil then return {supported=false} end
    local ok, meta=pcall(mtgCardMetadata,{guid=guid})
    if not ok or not mtgSpellType(meta,kind.type) then
        return {supported=false}
    end
    return {supported=true, name=name, type=kind.type, targetCount=kind.count}
end

local function mtgSpellCard(guid)
    if type(guid)~="string" then return nil end
    local card=getObjectFromGUID(guid)
    if card==nil or card.type~="Card" or card.is_face_down or card.isDestroyed() then
        return nil
    end
    return card
end

local function mtgSpellTargetState(guid,caster)
    local card=mtgSpellCard(guid)
    if card==nil then return nil, "Target card is unavailable or face-down." end
    local ok, state=pcall(mtgCardState,{guid=guid})
    if not ok or type(state)~="table" or state.status~="ready" then
        return nil, "Unable to inspect target game state."
    end
    if state.zone~="Battlefield" then
        return nil, "The target is no longer on a battlefield."
    end
    if not mtgSpellType(state,"creature") then
        return nil, "This supported spell handler requires a creature target."
    end
    if state.controller==nil or state.owner==nil then
        return nil, "Owner or controller is unknown; resolve manually."
    end
    local kw=type(state.encodedKeywords)=="table" and state.encodedKeywords or {}
    local raw=tostring(card.getDescription() or ""):lower()
    if (kw.hexproof or 0) > 0 and caster~=state.controller then
        return nil, "Target has hexproof from your spell; resolve manually."
    end
    -- Conservative blockers where current metadata cannot establish actual
    -- legality: protection, ward, shroud, or complex continuous effects.
    if raw:find("shroud",1,true)
        or raw:find("protection from",1,true)
        or raw:find("ward ",1,true)
        or raw:find("can't be the target",1,true)
        or raw:find("can't be targeted",1,true) then
        return nil, "Potential targeting restriction; resolve manually."
    end
    return {card=card,state=state}
end

local function mtgSpellExile(target, withLife)
    local state=target.state
    local owner=state.owner
    local pd=data and data[owner]
    if pd==nil or pd.exileZone==nil then
        return mtgSpellResult(false,"Owner's exile zone is unavailable.")
    end
    -- Do not take over commander replacement decisions or mutate the command zone.
    local obj=target.card
    if (obj.hasTag and (obj.hasTag("Commander") or obj.hasTag("commander"))) or
        (type(state.typeLine)=="string" and
            state.typeLine:lower():find("legendary creature",1,true)) then
        return mtgSpellResult(false,
            "Possible commander/replacement effect. Exile manually.")
    end
    local pos,rot=mtgGetZonePlacement(owner,"exileZone",3,false)
    if pos==nil or rot==nil then
        return mtgSpellResult(false,"Cannot determine owner's exile placement.")
    end
    local amount=0
    local tracker
    if withLife then
        if type(state.currentPower)~="number" then
            return mtgSpellResult(false,
                "Target power is unknown (variable P/T); resolve manually.")
        end
        amount=math.max(0,state.currentPower)
        tracker=data[state.controller] and data[state.controller].lifeTracker
        if tracker==nil then
            return mtgSpellResult(false,"Target controller's life tracker is unavailable.")
        end
        -- Confirm the life API is installed BEFORE any action is applied.
        local ok, result=pcall(function() return tracker.call("mtgLifeReady",{}) end)
        if not ok or type(result)~="table" or result.ok~=true
            or result.color~=state.controller then
            return mtgSpellResult(false,"Life tracker not ready; update/import all scripts.")
        end
    end
    local origPos=obj.getPosition()
    local origRot=obj.getRotation()
    local ok=pcall(function()
        obj.setRotationSmooth(rot,false,true)
        obj.setPositionSmooth(pos,false,true)
    end)
    if not ok then
        return mtgSpellResult(false,"Could not move target to exile.")
    end
    if withLife and amount>0 then
        local success, result=pcall(function()
            return tracker.call("mtgGainLife",{amount=amount})
        end)
        if not success or type(result)~="table" or result.ok~=true then
            -- Best-effort restore on a life API failure to avoid a silent
            -- partial Swords resolution.
            pcall(function()
                obj.setRotationSmooth(origRot,false,true)
                obj.setPositionSmooth(origPos,false,true)
            end)
            return mtgSpellResult(false,
                "Life gain failed; target movement reverted. Resolve manually.")
        end
    end
    if withLife then
        return mtgSpellResult(true,
            mtgSpellFirstLine(obj.getName()).." exiled to "..owner..
            "'s exile; "..state.controller.." gains "..tostring(amount).." life.")
    end
    return mtgSpellResult(true,
        mtgSpellFirstLine(obj.getName()).." exiled to "..owner.."'s exile.")
end

local function mtgSpellBolt(target,sourceGUID)
    local state=target.state
    local old=type(state.damageMarked)=="number" and state.damageMarked or 0
    local effectId="arrow-bolt:"..sourceGUID..":"..target.card.getGUID()
    local ok,response=pcall(mtgSetCardDamage,{
        guid=target.card.getGUID(),damage=old+3,effectId=effectId
    })
    if not ok or type(response)~="table" or response.ok~=true then
        return mtgSpellResult(false,
            "Failed to register damage. Resolve manually.")
    end
    return mtgSpellResult(true,
        "Marked "..tostring(old+3).." damage on "..
        mtgSpellFirstLine(target.card.getName())..
        " (3 from Lightning Bolt). Players handle damage prevention and lethal-damage cleanup.")
end

-- One card GUID as source, and ONLY the player-owned outgoing arrows as targets.
-- Callers cannot ask to affect another card without explicitly including its GUID.
function mtgResolveArrowSpell(params)
    if type(params)~="table" then return mtgSpellResult(false,"Invalid request.") end
    local guid=params.sourceGUID
    local caster=params.caster
    if not MTG_SPELL_COLORS[caster] then return mtgSpellResult(false,"Invalid caster.") end
    if mtgSpellResolving[guid] then
        return mtgSpellResult(false,"Already resolving this spell.")
    end
    local info=mtgSupportedArrowSpell({guid=guid})
    if not info.supported then
        return mtgSpellResult(false,"Unsupported instant/sorcery. Resolve manually.")
    end
    local rule=MTG_SPELL_SUPPORTED[info.name:lower()]
    local targets=params.targets
    if type(targets)~="table" or #targets~=rule.count then
        return mtgSpellResult(false,
            "Expected "..tostring(rule.count).." card target(s).")
    end
    -- Independently verify LIVE arrow endpoints. A direct Global.call with
    -- arbitrary GUIDs cannot bypass the Lotus visual-arrow contract.
    local lotus=getObjectFromGUID("185063")
    if lotus==nil or type(lotus.call)~="function" then
        return mtgSpellResult(false,"Lotus arrow helper is unavailable.")
    end
    local arrowOk,arrows=pcall(function()
        return lotus.call("mtgReadSpellArrows",{
            sourceGUID=guid,color=caster
        })
    end)
    if not arrowOk or type(arrows)~="table" or arrows.ok~=true then
        return mtgSpellResult(false,
            "Cannot verify spell arrows: "..
            (type(arrows)=="table" and tostring(arrows.reason) or "helper unavailable"))
    end
    if arrows.count~=#targets then
        return mtgSpellResult(false,"Arrow target count changed; draw targets again.")
    end
    local expected={}
    for _,dest in ipairs(arrows.targets or {}) do expected[dest]=true end
    for _,dest in ipairs(targets) do
        if expected[dest]~=true then
            return mtgSpellResult(false,
                "A requested target does not have an outgoing arrow from this spell.")
        end
    end
    local seen={}
    local resolved={}
    for _,targetGUID in ipairs(targets) do
        if type(targetGUID)~="string" or targetGUID==guid
            or seen[targetGUID] then
            return mtgSpellResult(false,"Invalid or duplicate target.")
        end
        seen[targetGUID]=true
        local target,errorText=mtgSpellTargetState(targetGUID,caster)
        if target==nil then return mtgSpellResult(false,errorText) end
        resolved[#resolved+1]=target
    end
    -- Incoming targets, different spell-source arrows and unrelated permanents
    -- are never inspected or altered.
    mtgSpellResolving[guid]=true
    local ok, result=pcall(function()
        if rule.effect=="exile_life" then return mtgSpellExile(resolved[1],true) end
        if rule.effect=="exile" then return mtgSpellExile(resolved[1],false) end
        if rule.effect=="creature_damage3" then return mtgSpellBolt(resolved[1],guid) end
        return mtgSpellResult(false,"Effect not implemented.")
    end)
    mtgSpellResolving[guid]=nil
    if not ok then
        return mtgSpellResult(false,"Effect handler error; resolve manually.")
    end
    return result
end
