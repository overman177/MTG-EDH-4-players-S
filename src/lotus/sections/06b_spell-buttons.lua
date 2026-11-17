-- ARROW SPELL BUTTONS | 4-player, NO stack, NO automatic casts.
-- A supported instant/sorcery is a source only if outgoing arrows exist.
-- Uses card.createButton WITHOUT clearing or overwriting Encoder buttons.
SpellButtons = {
    BUTTON_PREFIX="MTG_ARROW_RESOLVE:",
    MAX_SOURCES=30,
    visible={},
    pending={}
}

local function spellButtonCard(obj)
    return obj~=nil and obj.type=="Card" and not obj.is_face_down
        and not obj.isDestroyed() and type(obj.getGUID)=="function"
end

local function spellButtonTell(color,message)
    if Combat.OWNERS[color] then
        printToColor("[MTG Resolve] "..tostring(message),color,{0.85,0.94,0.72})
    end
end

local function spellButtonFind(obj,guid)
    if not obj or type(obj.getButtons)~="function" then return nil end
    local ok,buttons=pcall(function() return obj.getButtons() end)
    if not ok or type(buttons)~="table" then return nil end
    for _,b in ipairs(buttons) do
        if b.click_function=="spellResolveButtonClick"
            and type(b.tooltip)=="string"
            and b.tooltip:sub(1,#SpellButtons.BUTTON_PREFIX)==SpellButtons.BUTTON_PREFIX
            and b.tooltip:find(guid,1,true) then
            return b.index
        end
    end
    return nil
end

local function spellButtonRemove(guid)
    local obj=getObjectFromGUID(guid)
    if obj~=nil and type(obj.getButtons)=="function" then
        -- Find our unique button by tooltip, never by a remembered shifting index.
        local index=spellButtonFind(obj,guid)
        if index~=nil then pcall(function() obj.removeButton(index) end) end
    end
    SpellButtons.visible[guid]=nil
end

local function spellButtonAdd(guid)
    local obj=getObjectFromGUID(guid)
    if not spellButtonCard(obj) then return false end
    if spellButtonFind(obj,guid)==nil then
        local ok=pcall(function()
            obj.createButton({
                click_function="spellResolveButtonClick",
                function_owner=self,
                label="RESOLVE",
                tooltip=SpellButtons.BUTTON_PREFIX..guid..
                    " | Apply supported effect to this spell's arrow targets",
                -- Placed just past the lower edge of the card in local space.
                -- Doesn't cover the artwork, existing Encoder controls or table.
                position={0,0.27,-1.62},
                rotation={0,0,0},
                width=1050,height=240,font_size=170,
                scale={0.50,0.50,0.50},
                color={0.13,0.19,0.14,0.92},
                font_color={0.94,1.0,0.91,1},
                hover_color={0.24,0.38,0.27,1},
                press_color={0.09,0.29,0.12,1}
            })
        end)
        if not ok then return false end
    end
    SpellButtons.visible[guid]=true
    return true
end

-- Strictly a read of live visual arrows; target registry/chat sessions are
-- unrelated. Only this color's outgoing links may be resolved by that color.
function SpellButtons.readArrows(params)
    local source=type(params)=="table" and params.sourceGUID or nil
    local color=type(params)=="table" and params.color or nil
    if type(source)~="string" or not Combat.OWNERS[color] then
        return {ok=false,reason="invalid request",targets={}}
    end
    local link=Combat.links[source]
    if link==nil or type(link.defenders)~="table" then
        return {ok=false,reason="no outgoing arrows",targets={}}
    end
    local allowed, foreign, targets, found={},false,{},{}
    for dest, by in pairs(link.defenders) do
        if by==color then
            if not spellButtonCard(getObjectFromGUID(dest)) then
                return {ok=false,reason="invalid arrow destination",targets={}}
            end
            allowed[dest]=true
        else
            foreign=true
        end
    end
    if foreign then
        return {ok=false,reason="different players' arrows share this source; clear those first",targets={}}
    end
    -- Stable user-gesture order. A link cannot be targetable without a history
    -- entry created by Combat.addDefender; detect broken linkage explicitly.
    for _,pair in ipairs(Combat.history[color] or {}) do
        if pair.attacker==source and allowed[pair.defender]
            and not found[pair.defender] then
            found[pair.defender]=true
            targets[#targets+1]=pair.defender
        end
    end
    for guid in pairs(allowed) do
        if not found[guid] then
            return {ok=false,reason="arrow history out of sync; redraw targets",targets={}}
        end
    end
    if #targets==0 then
        return {ok=false,reason="no arrows from this spell for your color",targets={}}
    end
    return {ok=true,sourceGUID=source,color=color,count=#targets,targets=targets}
end

local function spellButtonEligible(guid,obj)
    if not spellButtonCard(obj) then return false end
    local ok,info=pcall(function()
        return Global.call("mtgSupportedArrowSpell",{guid=guid})
    end)
    return ok and type(info)=="table" and info.supported==true
end

-- Called on Combat.updated() and in the existing arrow loop (no new poll).
-- Reconcile missing buttons that Encoder may have regenerated.
function SpellButtons.refresh()
    local wanted,number={},0
    for guid,link in pairs(Combat.links) do
        if number>=SpellButtons.MAX_SOURCES then break end
        if type(link.defenders)=="table" and next(link.defenders) then
            local obj=getObjectFromGUID(guid)
            if spellButtonEligible(guid,obj) then
                wanted[guid]=true
                number=number+1
                if not SpellButtons.visible[guid]
                    or spellButtonFind(obj,guid)==nil then
                    spellButtonAdd(guid)
                end
            end
        end
    end
    for guid in pairs(SpellButtons.visible) do
        if not wanted[guid] then spellButtonRemove(guid) end
    end
end

function SpellButtons.onClick(obj,color)
    if not Combat.OWNERS[color] or not spellButtonCard(obj) then return end
    local guid=obj.getGUID()
    if SpellButtons.pending[guid] then return end
    local arrows=SpellButtons.readArrows({sourceGUID=guid,color=color})
    if not arrows.ok then
        spellButtonTell(color,arrows.reason)
        return
    end
    SpellButtons.pending[guid]=true
    local ok,result=pcall(function()
        return Global.call("mtgResolveArrowSpell",{
            sourceGUID=guid,caster=color,targets=arrows.targets
        })
    end)
    SpellButtons.pending[guid]=nil
    if not ok or type(result)~="table" then
        spellButtonTell(color,"Resolution failed; cards were not intentionally changed.")
        return
    end
    spellButtonTell(color,result.message or "No resolution result.")
    if result.ok==true then
        -- On success, discard ONLY the resolving player's outgoing arrows
        -- for THIS source; other arrows from other sources remain untouched.
        Combat.clearSource(color,guid)
    end
end

function SpellButtons.load()
    SpellButtons.visible={}
    SpellButtons.pending={}
    -- Buttons can survive save/load while Combat's ephemeral links do not.
    -- One bounded, delayed startup cleanup; no repeated getAllObjects scan.
    Wait.frames(function()
        local seen=0
        for _,obj in ipairs(getAllObjects() or {}) do
            if obj and obj.type=="Card" and type(obj.getButtons)=="function" then
                local guid=obj.getGUID()
                if spellButtonFind(obj,guid)~=nil then spellButtonRemove(guid) end
            end
            seen=seen+1
            if seen>=1800 then break end
        end
    end,40)
end

function spellResolveButtonClick(obj,color,alt)
    SpellButtons.onClick(obj,color)
end

-- Exposed to Global to independently validate supplied targets against the
-- CURRENT visual arrows; prevents arbitrary target GUIDs in direct API calls.
function mtgReadSpellArrows(params)
    return SpellButtons.readArrows(params)
end
