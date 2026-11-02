-- =============================================================
-- MODULE 7: COMBAT TARGETING (CUSTOM GAME KEY, NOT NATIVE TAB)
--
-- TTS does not let Lua assign C (or any default key) programmatically.
-- Players bind "MTG: Declare Combat Target" to C in Options > Game Keys.
-- Holding the bound key on DEFENDER and releasing on ATTACKER creates
-- a persistent, purely visual arrow. No MTG rules are enforced.
-- Arrows are session-only; each player can clear their own arrows.
-- =============================================================

Combat = {
    HOTKEY = "MTG: Declare Combat Target",
    OWNERS = {White = true, Red = true, Yellow = true, Blue = true},
    COLOR = {
        White = {0.95, 0.94, 0.83},
        Red = {0.96, 0.33, 0.27},
        Yellow = {1.0, 0.83, 0.19},
        Blue = {0.30, 0.64, 1.0}
    },
    pending = {}, -- initiator color -> defender GUID while key held
    links = {},   -- attacker GUID -> {defenders = { [defenderGUID] = true }, by = color}
    baseLines = {},
    -- Used only to remove AUTOFIGHT objects from older table saves.
    LEGACY_ANCHOR_TAG = "MTG_Lotus_AutoFightAnchor",
    loopActive = false,
    loopGeneration = 0,
    REFRESH_SECONDS = 0.30
}

local function combatCard(obj)
    return obj ~= nil and obj.tag == "Card"
        and not obj.isDestroyed() and type(obj.getGUID) == "function"
end

function Combat.enabled(color)
    return Combat.OWNERS[color] == true
        and Settings.combatEnabledByColor[color] ~= false
end

local function combatLocal(world)
    local v = self.positionToLocal(world)
    return {v.x, v.y, v.z}
end

-- Each attacker can have several defenders, with independent arrows. One
-- defender may be selected for multiple attacking creatures.
function Combat.countDefenders(link)
    local n, only = 0, nil
    if not link then return 0, nil end
    for guid in pairs(link.defenders or {}) do
        n = n + 1
        only = guid
    end
    return n, n == 1 and only or nil
end

function Combat.singleDefender(attackerGUID)
    local link = Combat.links[attackerGUID]
    local count, guid = Combat.countDefenders(link)
    if count == 1 then return guid end
    return nil
end

function Combat.toggleDefender(attackerGUID, defenderGUID, color)
    local link = Combat.links[attackerGUID]
    if link == nil then
        link = {defenders = {}, by = color}
        Combat.links[attackerGUID] = link
    end
    if link.defenders[defenderGUID] then
        link.defenders[defenderGUID] = nil
        if next(link.defenders) == nil then
            Combat.links[attackerGUID] = nil
        end
    else
        link.defenders[defenderGUID] = true
        link.by = color
    end
    Combat.updated()
end

function Combat.render()
    local lines = {}
    for _, existing in ipairs(Combat.baseLines) do
        lines[#lines + 1] = existing
    end
    for attackerGUID, link in pairs(Combat.links) do
        local attacker = getObjectFromGUID(attackerGUID)
        if not combatCard(attacker) then
            Combat.links[attackerGUID] = nil
        else
            local a = attacker.getPosition()
            for defenderGUID in pairs(link.defenders) do
                local defender = getObjectFromGUID(defenderGUID)
                if not combatCard(defender) then
                    link.defenders[defenderGUID] = nil
                else
                    local b = defender.getPosition()
                    local dx, dz = b.x - a.x, b.z - a.z
                    local distance = math.sqrt(dx * dx + dz * dz)
                    if distance > 0.35 then
                        local ux, uz = dx / distance, dz / distance
                        local lift = math.max(a.y, b.y) + 0.45
                        local start = {a.x + ux * 0.33, lift, a.z + uz * 0.33}
                        local finish = {b.x - ux * 0.35, lift, b.z - uz * 0.35}
                        local wing = 0.32
                        local left = {finish[1] - ux * 0.57 - uz * wing,
                                      lift, finish[3] - uz * 0.57 + ux * wing}
                        local right = {finish[1] - ux * 0.57 + uz * wing,
                                       lift, finish[3] - uz * 0.57 - ux * wing}
                        local tint = Combat.COLOR[link.by] or {1, 1, 1}
                        lines[#lines + 1] = {
                            points = {combatLocal(start), combatLocal(finish)},
                            color = tint, thickness = 0.10
                        }
                        lines[#lines + 1] = {
                            points = {combatLocal(left), combatLocal(finish),
                                      combatLocal(right)},
                            color = tint, thickness = 0.10
                        }
                    end
                end
            end
            if next(link.defenders) == nil then Combat.links[attackerGUID] = nil end
        end
    end
    self.setVectorLines(lines)
end

function Combat.loop(generation)
    if generation ~= Combat.loopGeneration then return end
    Combat.render()
    if next(Combat.links) then
        Wait.time(function() Combat.loop(generation) end, Combat.REFRESH_SECONDS)
    else
        Combat.loopActive = false
    end
end

function Combat.updated()
    Combat.render()
    if next(Combat.links) and not Combat.loopActive then
        Combat.loopActive = true
        Combat.loopGeneration = Combat.loopGeneration + 1
        local gen = Combat.loopGeneration
        Wait.time(function() Combat.loop(gen) end, Combat.REFRESH_SECONDS)
    elseif not next(Combat.links) then
        Combat.loopGeneration = Combat.loopGeneration + 1
        Combat.loopActive = false
    end
end

function Combat.clear(color)
    if not Combat.OWNERS[color] then return end
    Combat.pending[color] = nil
    for attackerGUID, link in pairs(Combat.links) do
        if link.by == color then Combat.links[attackerGUID] = nil end
    end
    Combat.updated()
end

function Combat.onDestroy(obj)
    if obj == nil then return end
    local guid = obj.getGUID()
    local dirty = Combat.links[guid] ~= nil
    Combat.links[guid] = nil
    for attackerGUID, link in pairs(Combat.links) do
        if link.defenders[guid] then
            link.defenders[guid] = nil
            dirty = true
            if next(link.defenders) == nil then
                Combat.links[attackerGUID] = nil
            end
        end
    end
    if dirty then Combat.updated() end
end

function Combat.hotkey(color, hovered, pointerPosition, isKeyUp)
    if not Combat.OWNERS[color] then return end
    if not isKeyUp then
        Combat.pending[color] = Combat.enabled(color)
            and combatCard(hovered) and hovered.getGUID() or nil
        return
    end
    local defenderGUID = Combat.pending[color]
    Combat.pending[color] = nil
    if not Combat.enabled(color) or not defenderGUID then return end
    if not combatCard(getObjectFromGUID(defenderGUID)) then return end
    if not combatCard(hovered) then
        printToColor("Combat: release over an attacking card.", color, {0.9, 0.72, 0.35})
        return
    end
    local attackerGUID = hovered.getGUID()
    if attackerGUID == defenderGUID then
        -- Tap on attacker removes its complete declaration, including multiple blockers.
        local link = Combat.links[attackerGUID]
        if link then
            Combat.links[attackerGUID] = nil
            Combat.updated()
        end
        return
    end
    -- DEFENDER first, ATTACKER second: add or remove just this defender.
    Combat.toggleDefender(attackerGUID, defenderGUID, color)
end

-- Remove obsolete AUTOFIGHT world objects and old Lotus-mounted FIGHT
-- buttons left behind by an earlier saved version. All other table buttons,
-- objects and vector lines are preserved.
function Combat.cleanupLegacyFight()
    if type(getObjectsWithTag) == "function" then
        for _, obj in ipairs(getObjectsWithTag(Combat.LEGACY_ANCHOR_TAG) or {}) do
            obj.destruct()
        end
    end
    if self.getButtons and self.removeButton then
        local indices = {}
        for _, button in ipairs(self.getButtons() or {}) do
            if type(button.tooltip) == "string"
                and button.tooltip:sub(1, 17) == "MTG_COMBAT_FIGHT:"
                and type(button.index) == "number" then
                indices[#indices + 1] = button.index
            end
        end
        table.sort(indices, function(a, b) return a > b end)
        for _, index in ipairs(indices) do self.removeButton(index) end
    end
    -- Earlier versions added private combat estimate panels to the Global UI.
    -- Remove only these obsolete top-level panels, leaving all other UI alone.
    if UI and UI.getXmlTable and UI.setXmlTable then
        local ok, xml = pcall(UI.getXmlTable)
        if ok and type(xml) == "table" then
            local changed = false
            for i = #xml, 1, -1 do
                local id = type(xml[i]) == "table"
                    and type(xml[i].attributes) == "table"
                    and xml[i].attributes.id
                if type(id) == "string"
                    and id:sub(1, 24) == "MTG_Combat_Fight_Result_" then
                    table.remove(xml, i)
                    changed = true
                end
            end
            if changed then UI.setXmlTable(xml) end
        end
    end
end

function Combat.load()
    Combat.pending = {}
    Combat.links = {}
    Combat.baseLines = self.getVectorLines() or {}
    Combat.loopActive = false
    Combat.loopGeneration = 0
    addHotkey(Combat.HOTKEY, Combat.hotkey, true)
    -- TTS may restore old spawned anchors when loading a saved table.
    -- Clean them after all objects have spawned.
    Wait.frames(Combat.cleanupLegacyFight, 30)
end
