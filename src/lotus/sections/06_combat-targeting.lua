-- =============================================================
-- MODULE 7: COMBAT TARGETING (DRAW / UNDO / CLEAR MY ARROWS)
--
-- TTS does not let Lua assign C (or any default key) programmatically.
-- Players bind "MTG: Declare Combat Target" to C in Options > Game Keys.
-- DRAW: hold over defender and release over attacker to add a visual arrow.
-- REMOVE: press once to clear all of your own arrows, anywhere on the table.
-- UNDO: press once to remove your latest still-existing arrow.
-- Arrows are visual-only and session-only; no MTG rules are enforced.
-- =============================================================

Combat = {
    HOTKEY = "MTG: Declare Combat Target",
    -- Keep the previous hotkey name so players retain their existing binding.
    -- This key now clears all arrows owned by the pressing player.
    REMOVE_HOTKEY = "MTG: Remove Combat Target",
    UNDO_HOTKEY = "MTG: Undo Combat Target",
    OWNERS = {White = true, Red = true, Yellow = true, Blue = true},
    COLOR = {
        White = {0.95, 0.94, 0.83},
        Red = {0.96, 0.33, 0.27},
        Yellow = {1.0, 0.83, 0.19},
        Blue = {0.30, 0.64, 1.0}
    },
    pending = {}, -- color -> defender GUID during DRAW
    history = {}, -- color -> created pairs in order
    links = {},   -- attacker GUID -> {defenders = { [defenderGUID] = playerColor }, by = color}
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

-- Declaring a pairing is idempotent. Repeating it MUST NOT delete an
-- earlier arrow, including when an input event is received more than once.
-- Each defender stores the color of the player who added that arrow.
function Combat.addDefender(attackerGUID, defenderGUID, color)
    if attackerGUID == defenderGUID or not Combat.OWNERS[color] then return false end
    local link = Combat.links[attackerGUID]
    if link == nil then
        link = {defenders = {}, by = color}
        Combat.links[attackerGUID] = link
    end
    if link.defenders[defenderGUID] ~= nil then return false end
    link.defenders[defenderGUID] = color
    Combat.history[color] = Combat.history[color] or {}
    table.insert(Combat.history[color], {attacker = attackerGUID, defender = defenderGUID})
    Combat.updated()
    return true
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
            for defenderGUID, declaredBy in pairs(link.defenders) do
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
                        local tint = Combat.COLOR[declaredBy] or Combat.COLOR[link.by] or {1, 1, 1}
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
    Combat.history[color] = {}
    local changed = false
    for attackerGUID, link in pairs(Combat.links) do
        for defenderGUID, owner in pairs(link.defenders) do
            if owner == color or (owner == true and link.by == color) then
                link.defenders[defenderGUID] = nil
                changed = true
            end
        end
        if next(link.defenders) == nil then
            Combat.links[attackerGUID] = nil
        end
    end
    if changed then Combat.updated() end
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

-- The drawing key never performs a removal. Same-card release simply cancels.
function Combat.hotkey(color, hovered, pointerPosition, isKeyUp)
    if not Combat.OWNERS[color] then return end
    if not isKeyUp then
        Combat.pending[color] = (Combat.enabled(color) and combatCard(hovered))
            and hovered.getGUID() or nil
        return
    end
    local defender = Combat.pending[color]
    Combat.pending[color] = nil
    if not Combat.enabled(color) or not defender
        or not combatCard(getObjectFromGUID(defender))
        or not combatCard(hovered) then return end
    local attacker = hovered.getGUID()
    if attacker ~= defender then Combat.addDefender(attacker, defender, color) end
end

-- Removing a single arrow requires an entirely separate key gesture.
-- Ownership is checked on the exact attacker/defender pair.
function Combat.removePair(attacker, defender, color)
    local link = Combat.links[attacker]
    if not link or link.defenders[defender] ~= color then return false end
    link.defenders[defender] = nil
    if next(link.defenders) == nil then Combat.links[attacker] = nil end
    Combat.updated()
    return true
end

-- This action is deliberately press-only and independent of the pointer.
-- Retaining the registered key name preserves existing client bindings.
function Combat.removeHotkey(color, hovered, pointerPosition, isKeyUp)
    if isKeyUp or not Combat.enabled(color) then return end
    Combat.clear(color)
end

function Combat.undo(color)
    if not Combat.enabled(color) then return false end
    local history = Combat.history[color] or {}
    while #history > 0 do
        local entry = table.remove(history)
        if Combat.removePair(entry.attacker, entry.defender, color) then return true end
    end
    return false
end

function Combat.undoHotkey(color, hovered, pointerPosition, isKeyUp)
    if not isKeyUp then Combat.undo(color) end
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
    Combat.history = {}
    Combat.links = {}
    Combat.baseLines = self.getVectorLines() or {}
    Combat.loopActive = false
    Combat.loopGeneration = 0
    addHotkey(Combat.HOTKEY, Combat.hotkey, true)
    addHotkey(Combat.REMOVE_HOTKEY, Combat.removeHotkey, false)
    addHotkey(Combat.UNDO_HOTKEY, Combat.undoHotkey, false)
    -- TTS may restore old spawned anchors when loading a saved table.
    -- Clean them after all objects have spawned.
    Wait.frames(Combat.cleanupLegacyFight, 30)
end
