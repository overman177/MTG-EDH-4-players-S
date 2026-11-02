-- =============================================================
-- MODULE 7: COMBAT TARGETING (CUSTOM GAME KEY, NOT NATIVE TAB)
--
-- TTS does not let Lua assign C (or any default key) programmatically.
-- Players bind "MTG: Declare Combat Target" to C in Options > Game Keys.
-- Holding the bound key on a card and releasing on another card creates
-- a persistent, purely visual arrow. No MTG rules are enforced.
-- Arrows are session-only; each player can clear their own arrows.
-- =============================================================

local Combat = {
    HOTKEY = "MTG: Declare Combat Target",
    OWNERS = {White = true, Red = true, Yellow = true, Blue = true},
    COLOR = {
        White = {0.95, 0.94, 0.83},
        Red = {0.96, 0.33, 0.27},
        Yellow = {1.0, 0.83, 0.19},
        Blue = {0.30, 0.64, 1.0}
    },
    pending = {}, -- initiator color -> attacker GUID while key held
    links = {},   -- attacker GUID -> {target = GUID, by = playerColor}
    baseLines = {},
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

function Combat.render()
    local lines = {}
    for _, existing in ipairs(Combat.baseLines) do
        lines[#lines + 1] = existing
    end
    for attackerGUID, link in pairs(Combat.links) do
        local attacker = getObjectFromGUID(attackerGUID)
        local defender = getObjectFromGUID(link.target)
        if not combatCard(attacker) or not combatCard(defender) then
            Combat.links[attackerGUID] = nil
        else
            local a, b = attacker.getPosition(), defender.getPosition()
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
    -- Only Lotus' own vector lines are replaced, never Global/table drawings.
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
        if link.target == guid then
            Combat.links[attackerGUID] = nil
            dirty = true
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
    local attackerGUID = Combat.pending[color]
    Combat.pending[color] = nil
    if not Combat.enabled(color) or not attackerGUID then return end
    local attacker = getObjectFromGUID(attackerGUID)
    if not combatCard(attacker) then return end
    if not combatCard(hovered) or hovered.getGUID() == attackerGUID then
        printToColor("Combat: release the key over another card.", color,
            {0.9, 0.72, 0.35})
        return
    end
    Combat.links[attackerGUID] = {target = hovered.getGUID(), by = color}
    Combat.updated()
end

function Combat.load()
    Combat.pending = {}
    Combat.links = {}
    Combat.baseLines = self.getVectorLines() or {}
    Combat.loopActive = false
    Combat.loopGeneration = 0
    addHotkey(Combat.HOTKEY, Combat.hotkey, true)
end

