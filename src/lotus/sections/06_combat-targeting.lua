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
    Combat.syncButtons()
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
        -- The cursor starts on the DEFENDER (usually the blocking creature).
        Combat.pending[color] = Combat.enabled(color)
            and combatCard(hovered) and hovered.getGUID() or nil
        return
    end

    local defenderGUID = Combat.pending[color]
    Combat.pending[color] = nil
    if not Combat.enabled(color) or not defenderGUID then return end
    local defender = getObjectFromGUID(defenderGUID)
    if not combatCard(defender) then return end

    if not combatCard(hovered) then
        printToColor("Combat: release over the attacking card (or tap an attacker to clear its arrow).",
            color, {0.9, 0.72, 0.35})
        return
    end

    local attackerGUID = hovered.getGUID()
    local current = Combat.links[attackerGUID]

    -- Press/release on the same attacker: delete its own arrow, if present.
    if defenderGUID == attackerGUID then
        if current ~= nil then
            Combat.links[attackerGUID] = nil
            Combat.updated()
        end
        return
    end

    -- Repeating defender -> same attacker toggles off the connection.
    -- A new defender for this attacker replaces the old connection.
    if current ~= nil and current.target == defenderGUID then
        Combat.links[attackerGUID] = nil
    else
        Combat.links[attackerGUID] = {target = defenderGUID, by = color}
    end
    Combat.updated()
end

function Combat.load()
    Combat.pending = {}
    Combat.links = {}
    Combat.baseLines = self.getVectorLines() or {}
    Combat.loopActive = false
    Combat.loopGeneration = 0
    addHotkey(Combat.HOTKEY, Combat.hotkey, true)
    Combat.buttonPositions = {}
    Combat.reportPanelsInstalled = false
end


-- =============================================================
-- FIGHT BUTTONS + READ-ONLY COMBAT ESTIMATE
-- Built entirely into Lotus; existing Encoder modules remain untouched.
-- =============================================================

Combat.BUTTON_PREFIX = "MTG_COMBAT_FIGHT:"
Combat.FIGHT_PROP_ID = "_MTG_Simplified_UNIFIED"
Combat.REPORT_PREFIX = "MTG_Combat_Fight_Result_"

local function combatButtonName(guid)
    return "combatFight_" .. tostring(guid):gsub("[^%w_]", "_")
end

-- A combat button belongs to the Lotus object, but is positioned at the
-- arrow midpoint in world space. Scan by an owned tooltip prefix instead of
-- keeping hardcoded button indices (other Lotus modules also create buttons).
function Combat.syncButtons()
    if not self.getButtons or not self.createButton then return end
    local owned = {}
    local buttons = self.getButtons() or {}
    for _, button in ipairs(buttons) do
        local tooltip = button.tooltip
        if type(tooltip) == "string"
            and tooltip:sub(1, #Combat.BUTTON_PREFIX) == Combat.BUTTON_PREFIX then
            local guid = tooltip:sub(#Combat.BUTTON_PREFIX + 1)
            owned[guid] = button
        end
    end

    local needed = {}
    for attackerGUID, link in pairs(Combat.links) do
        local attacker = getObjectFromGUID(attackerGUID)
        local defender = getObjectFromGUID(link.target)
        if combatCard(attacker) and combatCard(defender) then
            local a, d = attacker.getPosition(), defender.getPosition()
            local dx, dz = d.x - a.x, d.z - a.z
            if dx * dx + dz * dz > 0.14 then
                local worldMid = {
                    x = (a.x + d.x) * 0.5,
                    y = math.max(a.y, d.y) + 0.57,
                    z = (a.z + d.z) * 0.5
                }
                local localPos = self.positionToLocal(worldMid)
                local point = {localPos.x, localPos.y, localPos.z}
                needed[attackerGUID] = true
                local fn = combatButtonName(attackerGUID)
                -- Give every attack its own valid TTS click callback.
                local capturedGuid = attackerGUID
                _G[fn] = function(buttonObj, color, altClick)
                    Combat.fightClick(capturedGuid, color)
                end
                local existing = owned[attackerGUID]
                if existing then
                    local last = Combat.buttonPositions[attackerGUID]
                    if last == nil
                        or math.abs(last[1] - point[1]) > 0.04
                        or math.abs(last[2] - point[2]) > 0.04
                        or math.abs(last[3] - point[3]) > 0.04 then
                        self.editButton({index = existing.index, position = point})
                    end
                else
                    self.createButton({
                        click_function = fn,
                        function_owner = self,
                        label = "FIGHT",
                        position = point,
                        rotation = {0, 0, 0},
                        width = 480, height = 200, font_size = 135,
                        scale = {0.65, 0.65, 0.65},
                        color = {0.13, 0.17, 0.23, 0.94},
                        font_color = {1, 0.91, 0.75, 1},
                        hover_color = {0.24, 0.36, 0.49, 1},
                        tooltip = Combat.BUTTON_PREFIX .. attackerGUID
                    })
                end
                Combat.buttonPositions[attackerGUID] = point
            end
        end
    end

    -- Remove only our marker buttons, descending by current actual index.
    local removals = {}
    for guid, button in pairs(owned) do
        if not needed[guid] then
            removals[#removals + 1] = {index = button.index, guid = guid}
        end
    end
    table.sort(removals, function(a, b) return a.index > b.index end)
    for _, row in ipairs(removals) do
        self.removeButton(row.index)
        Combat.buttonPositions[row.guid] = nil
        _G[combatButtonName(row.guid)] = nil
    end
end

-- Encoder and TyrantNomad's module expose actual recorded values. Button
-- labels are merely presentation and must never be parsed as game state.
local function combatNumber(value)
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

local function combatName(card)
    local name = tostring(card.getName() or ""):match("^[^\r\n]*") or "Card"
    name = name:gsub("%[.-%]", ""):gsub("[<>]", "")
    if #name > 34 then name = name:sub(1, 31) .. "..." end
    return name
end

local function combatReadKeywords(encoder, card)
    local ok, values = pcall(function()
        return encoder.call("APIobjGetPropData", {obj = card, propID = "πKeywords"})
    end)
    if not ok or type(values) ~= "table" then return {} end
    local list = {}
    if type(values.activeIcons) == "table" then
        for _, key in pairs(values.activeIcons) do
            if type(key) == "string" then list[#list + 1] = key end
        end
    end
    return list
end

function Combat.readStats(card)
    local result = {
        name = combatName(card), known = false, keywords = {},
        error = "Encoder statistics are unavailable for this card."
    }
    local encoder = Global.getVar("Encoder")
    if encoder == nil then
        result.error = "Encoder not found."
        return result
    end
    local ok, props = pcall(function()
        return encoder.call("APIobjGetPropData", {
            obj = card, propID = Combat.FIGHT_PROP_ID
        })
    end)
    if not ok or type(props) ~= "table"
        or type(props.tyrantUnified) ~= "table" then
        return result
    end

    local data = props.tyrantUnified
    local face = type(data.cardFaces) == "table"
        and data.cardFaces[tonumber(data.activeFace) or 1]
    if type(face) ~= "table" then
        result.error = "No active card face statistics."
        return result
    end
    local baseP = combatNumber(face.basePower)
    local baseT = combatNumber(face.baseToughness)
    if baseP == nil or baseT == nil then
        result.error = "Variable or nonnumeric power/toughness needs manual input."
        return result
    end
    local modP = combatNumber(data.power or 0)
    local modT = combatNumber(data.toughness or 0)
    local counters = combatNumber(data.plusOneCounters or 0)
    if modP == nil or modT == nil or counters == nil then
        result.error = "Invalid modifier/counter value."
        return result
    end

    result.known = true
    result.basePower, result.baseToughness = baseP, baseT
    result.powerModifier, result.toughnessModifier = modP, modT
    result.plusOneCounters = counters
    result.power = baseP + modP + counters
    result.toughness = baseT + modT + counters
    result.keywords = combatReadKeywords(encoder, card)
    result.error = nil
    return result
end

local function combatStatText(s)
    if not s.known then return "?/?" end
    return tostring(s.power) .. "/" .. tostring(s.toughness)
end

function Combat.evaluate(attacker, defender)
    local a, d = Combat.readStats(attacker), Combat.readStats(defender)
    local result = {
        attacker = a, defender = d, known = a.known and d.known,
        notes = {}, attackerDamage = nil, defenderDamage = nil
    }
    if result.known then
        -- One attacker and one blocker, simultaneous regular combat damage.
        result.attackerDamage = math.max(0, a.power)
        result.defenderDamage = math.max(0, d.power)
        result.attackerLethal = result.defenderDamage >= a.toughness
        result.defenderLethal = result.attackerDamage >= d.toughness
    end
    local flagged = {
        mtg_deathtouchcounter = true,
        mtg_firststrikecounter = true,
        mtg_doublestrikecounter = true,
        mtg_indestructiblecounter = true,
        mtg_tramplecounter = true,
        mtg_lifelinkcounter = true,
        mtg_protectioncounter = true,
        mtg_stuncounter = true
    }
    for _, s in ipairs({a, d}) do
        for _, keyword in ipairs(s.keywords) do
            if flagged[keyword] then
                result.notes[#result.notes + 1] =
                    s.name .. ": " .. keyword:gsub("^mtg_", ""):gsub("counter$", "")
            end
        end
    end
    if not a.known then
        result.notes[#result.notes + 1] = "Attacker: " .. a.error
    end
    if not d.known then
        result.notes[#result.notes + 1] = "Defender: " .. d.error
    end

    local lines = {
        "ATTACKER: " .. a.name .. "  [" .. combatStatText(a) .. "]",
        "DEFENDER: " .. d.name .. "  [" .. combatStatText(d) .. "]"
    }
    if result.known then
        lines[#lines + 1] = "Attacker deals " .. result.attackerDamage ..
            "  |  Defender deals " .. result.defenderDamage
        lines[#lines + 1] = "Attacker: " ..
            (result.attackerLethal and "lethal damage" or "not lethal") ..
            "  |  Defender: " ..
            (result.defenderLethal and "lethal damage" or "not lethal")
    else
        lines[#lines + 1] = "Cannot calculate a numeric damage exchange."
    end
    if #result.notes > 0 then
        lines[#lines + 1] = "Check: " .. table.concat(result.notes, "; ")
    end
    lines[#lines + 1] = "Estimate only. No damage is applied."
    lines[#lines + 1] = "Assumes 1 attacker / 1 blocker, simultaneous normal damage."
    lines[#lines + 1] = "Check existing damage, abilities and other effects."
    result.text = table.concat(lines, "\n")
    return result
end

local function combatReportPanel(color)
    local id = Combat.REPORT_PREFIX .. color
    return {tag = "Panel", attributes = {
        id = id, rectAlignment = "UpperRight", offsetXY = "-18 -80",
        width = "512", height = "278", color = "rgba(0.11,0.12,0.15,0.98)",
        outline = "#607487", outlineSize = "1 -1",
        visibility = color, active = "false",
        raycastTarget = "true"
    }, children = {
        {tag = "Text", attributes = {
            rectAlignment = "UpperLeft", offsetXY = "15 -10",
            width = "455", height = "30", text = "COMBAT ESTIMATE",
            fontSize = "19", fontStyle = "Bold", color = "#8AB9E8",
            alignment = "MiddleLeft"
        }},
        {tag = "Button", attributes = {
            rectAlignment = "UpperRight", offsetXY = "-9 -8",
            width = "28", height = "28", text = "X",
            fontSize = "16", color = "#8B2929", textColor = "#FFFFFF",
            onClick = self.getGUID() .. "/combatCloseEstimate"
        }},
        {tag = "Text", attributes = {
            id = id .. "_body", rectAlignment = "UpperLeft",
            offsetXY = "15 -49", width = "484", height = "215",
            fontSize = "15", color = "#EDF2F7",
            alignment = "UpperLeft", text = "",
            horizontalOverflow = "Wrap", verticalOverflow = "Truncate",
            raycastTarget = "false"
        }}
    }}
end

function Combat.ensureResultPanels()
    if Combat.reportPanelsInstalled then return false end
    local xml = UI.getXmlTable() or {}
    local found = {}
    for _, node in ipairs(xml) do
        if type(node.attributes) == "table" then
            for color in pairs(Combat.OWNERS) do
                if node.attributes.id == Combat.REPORT_PREFIX .. color then
                    found[color] = true
                end
            end
        end
    end
    local changed = false
    for _, color in ipairs({"White", "Red", "Yellow", "Blue"}) do
        if not found[color] then
            xml[#xml + 1] = combatReportPanel(color)
            changed = true
        end
    end
    if changed then UI.setXmlTable(xml) end
    Combat.reportPanelsInstalled = true
    return changed
end

function Combat.showResult(color, text)
    local function display()
        local ok = pcall(function()
            local id = Combat.REPORT_PREFIX .. color
            UI.setAttribute(id .. "_body", "text", text)
            UI.setAttribute(id, "active", "true")
        end)
        if not ok then
            -- Readable fallback if a mod replaces Global UI unexpectedly.
            printToColor("COMBAT ESTIMATE\n" .. text, color, {0.75, 0.88, 1})
        end
    end
    local ok, newlyInstalled = pcall(Combat.ensureResultPanels)
    if not ok then
        printToColor("COMBAT ESTIMATE\n" .. text, color, {0.75, 0.88, 1})
    elseif newlyInstalled then
        -- setXmlTable recreates UI asynchronously; wait for the new elements.
        Wait.frames(display, 4)
    else
        display()
    end
end

function Combat.closeEstimate(player)
    local color = Settings.playerColor(player)
    if not Combat.OWNERS[color] then return end
    UI.setAttribute(Combat.REPORT_PREFIX .. color, "active", "false")
end

function Combat.fightClick(attackerGUID, playerColor)
    if not Combat.OWNERS[playerColor] then return end
    local link = Combat.links[attackerGUID]
    if link == nil then return end
    local attacker = getObjectFromGUID(attackerGUID)
    local defender = getObjectFromGUID(link.target)
    if not combatCard(attacker) or not combatCard(defender) then
        Combat.links[attackerGUID] = nil
        Combat.updated()
        return
    end
    local outcome = Combat.evaluate(attacker, defender)
    Combat.showResult(playerColor, outcome.text)
end
