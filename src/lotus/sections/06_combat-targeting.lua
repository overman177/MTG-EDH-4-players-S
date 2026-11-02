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
    links = {},   -- attacker GUID -> {defenders = { [defenderGUID] = playerColor }, by = color}
    baseLines = {},
    -- Used only to remove AUTOFIGHT objects from older table saves.
    LEGACY_ANCHOR_TAG = "MTG_Lotus_AutoFightAnchor",
    loopActive = false,
    loopGeneration = 0,
    REFRESH_SECONDS = 0.30,
    -- A valid remove gesture must be a genuine stationary key tap.
    -- Pointer data comes from TTS' addHotkey callback (world coordinates).
    TAP_MAX_MOVEMENT = 0.24
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
    Combat.updated()
    return true
end

-- Tap a defender card to remove only the arrows that this player declared
-- pointing at that defender. Other defenders and players are unaffected.
function Combat.removeDefender(defenderGUID, color)
    local changed = false
    for attackerGUID, link in pairs(Combat.links) do
        local owner = link.defenders[defenderGUID]
        if owner == color or (owner == true and link.by == color) then
            link.defenders[defenderGUID] = nil
            changed = true
            if next(link.defenders) == nil then
                Combat.links[attackerGUID] = nil
            end
        end
    end
    if changed then Combat.updated() end
    return changed
end

-- Tapping the attacker clears all arrows starting at that attacker.
function Combat.clearAttacker(attackerGUID)
    if Combat.links[attackerGUID] == nil then return false end
    Combat.links[attackerGUID] = nil
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

-- TTS provides pointerPosition on both hotkey events. Require the
-- world-space cursor to stay almost stationary for a REMOVE gesture.
-- This protects existing arrows if TTS resolves both hovered objects
-- to the same card during a real drag between overlapping card regions.
local function combatPointerXZ(position)
    if position == nil then return nil end
    local ok, x, z = pcall(function()
        return tonumber(position.x or position[1]),
               tonumber(position.z or position[3])
    end)
    if not ok or x == nil or z == nil then return nil end
    return {x = x, z = z}
end

function Combat.isStationaryTap(startXZ, endPosition)
    local finishXZ = combatPointerXZ(endPosition)
    if startXZ == nil or finishXZ == nil then
        -- Missing pointer data must not trigger a destructive operation.
        return false
    end
    local dx, dz = finishXZ.x - startXZ.x, finishXZ.z - startXZ.z
    return dx * dx + dz * dz <= Combat.TAP_MAX_MOVEMENT ^ 2
end

function Combat.hotkey(color, hovered, pointerPosition, isKeyUp)
    if not Combat.OWNERS[color] then return end
    if not isKeyUp then
        if Combat.enabled(color) and combatCard(hovered) then
            Combat.pending[color] = {
                guid = hovered.getGUID(),
                position = combatPointerXZ(pointerPosition)
            }
        else
            Combat.pending[color] = nil
        end
        return
    end
    local pending = Combat.pending[color]
    Combat.pending[color] = nil
    if not Combat.enabled(color) or not pending then return end
    local defenderGUID = pending.guid
    if not combatCard(getObjectFromGUID(defenderGUID)) then return end
    if not combatCard(hovered) then
        printToColor("Combat: release over an attacking card.", color, {0.9, 0.72, 0.35})
        return
    end
    local attackerGUID = hovered.getGUID()
    if attackerGUID == defenderGUID then
        -- Merely receiving the same card on both callback events is NOT
        -- enough to remove its arrows. TTS can still report the same hover
        -- after a moved cursor. Require a stationary physical key tap.
        if Combat.isStationaryTap(pending.position, pointerPosition) then
            if not Combat.clearAttacker(attackerGUID) then
                Combat.removeDefender(defenderGUID, color)
            end
        end
        return
    end
    -- DEFENDER first, ATTACKER second: ADD ONLY, even if an earlier
    -- arrow uses this attacker or the declaration is repeated.
    Combat.addDefender(attackerGUID, defenderGUID, color)
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
