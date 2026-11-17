-- TARGET REGISTRY | 4P experimental semantic layer above Lotus combat arrows
-- Visual arrows remain unrestricted and do not automatically become MTG targets.
-- A player must explicitly begin a selection. Committed targets survive arrow undo.
-- API (Lotus.call): mtgBeginTargetSelection, mtgFinishTargetSelection,
--                   mtgCancelTargetSelection, mtgReadTargetSelection.
TargetRegistry = {
    active = {}, committed = {}, order = {}, latest = {},
    hovered = {}, sequence = 0, MAX_HISTORY = 64, MAX_TARGETS = 20
}

local function targetCard(obj)
    return obj ~= nil and obj.tag == "Card"
        and not obj.isDestroyed() and type(obj.getGUID) == "function"
end

local function targetName(obj)
    if not targetCard(obj) then return "(missing card)" end
    local raw = tostring(obj.getName() or "")
    return (raw:match("^([^\r\n]*)") or ""):sub(1, 100)
end

local function targetTell(color, message)
    if Combat.OWNERS[color] then
        printToColor("[MTG Targets] " .. message, color, {0.85, 0.8, 1})
    end
end

local function targetRemove(record, guid)
    if not record or not record.index[guid] then return false end
    record.index[guid] = nil
    for i, value in ipairs(record.targets) do
        if value == guid then table.remove(record.targets, i); break end
    end
    return true
end

local function targetSnapshot(record, state)
    if record == nil then return {status = "none", targets = {}, count = 0} end
    local values = {}
    for _, guid in ipairs(record.targets) do
        local card = getObjectFromGUID(guid)
        values[#values + 1] = {
            guid = guid,
            valid = targetCard(card),
            name = targetName(card)
        }
    end
    return {
        status = state, id = record.id, color = record.color,
        sourceGUID = record.sourceGUID,
        sourceValid = targetCard(getObjectFromGUID(record.sourceGUID)),
        count = #values, targets = values
    }
end

function TargetRegistry.begin(params)
    local color = type(params) == "table" and params.color or nil
    local sourceGUID = type(params) == "table" and params.sourceGUID or nil
    if not Combat.OWNERS[color] or not Combat.enabled(color) then
        return {status = "invalid", reason = "targeting disabled or invalid seat"}
    end
    if type(sourceGUID) ~= "string"
        or not targetCard(getObjectFromGUID(sourceGUID)) then
        return {status = "invalid", reason = "source must be a live card"}
    end
    if TargetRegistry.active[color] then
        return {status = "invalid", reason = "finish or cancel current selection first"}
    end
    TargetRegistry.sequence = TargetRegistry.sequence + 1
    local record = {
        id = "target-" .. tostring(TargetRegistry.sequence),
        color = color, sourceGUID = sourceGUID, targets = {}, index = {}
    }
    TargetRegistry.active[color] = record
    return targetSnapshot(record, "active")
end

-- Called only after a deliberate successful key-down/source, key-up/destination
-- gesture. This also allows the user to select a pre-existing visual arrow.
function TargetRegistry.onDraw(color, sourceGUID, destinationGUID)
    local record = TargetRegistry.active[color]
    if record == nil or record.sourceGUID ~= sourceGUID then return false end
    if sourceGUID == destinationGUID or record.index[destinationGUID]
        or #record.targets >= TargetRegistry.MAX_TARGETS
        or not targetCard(getObjectFromGUID(destinationGUID)) then return false end
    record.targets[#record.targets + 1] = destinationGUID
    record.index[destinationGUID] = true
    return true
end

-- Only draft selections follow Undo/Clear. A committed choice has its own
-- identity and is never silently retargeted when a visual arrow disappears.
function TargetRegistry.onArrowRemoved(color, sourceGUID, destinationGUID)
    local record = TargetRegistry.active[color]
    if record ~= nil and record.sourceGUID == sourceGUID then
        targetRemove(record, destinationGUID)
    end
end

function TargetRegistry.finish(params)
    local color = type(params) == "table" and params.color or nil
    local record = TargetRegistry.active[color]
    if not record then return {status = "none", count = 0, targets = {}} end
    TargetRegistry.active[color] = nil
    TargetRegistry.committed[record.id] = record
    TargetRegistry.latest[color] = record.id
    TargetRegistry.order[#TargetRegistry.order + 1] = record.id
    if #TargetRegistry.order > TargetRegistry.MAX_HISTORY then
        local evicted = table.remove(TargetRegistry.order, 1)
        TargetRegistry.committed[evicted] = nil
    end
    return targetSnapshot(record, "committed")
end

function TargetRegistry.cancel(params)
    local color = type(params) == "table" and params.color or nil
    if not Combat.OWNERS[color] then return {status = "invalid"} end
    if not TargetRegistry.active[color] then return {status = "none"} end
    TargetRegistry.active[color] = nil
    return {status = "cancelled"}
end

function TargetRegistry.read(params)
    local id = type(params) == "table" and params.id or nil
    local color = type(params) == "table" and params.color or nil
    if type(id) == "string" then
        return targetSnapshot(TargetRegistry.committed[id],
            TargetRegistry.committed[id] and "committed" or "none")
    end
    if Combat.OWNERS[color] then
        if TargetRegistry.active[color] then
            return targetSnapshot(TargetRegistry.active[color], "active")
        end
        local latest = TargetRegistry.latest[color]
        return targetSnapshot(latest and TargetRegistry.committed[latest],
            latest and TargetRegistry.committed[latest] and "committed" or "none")
    end
    return {status = "invalid"}
end

function TargetRegistry.onDestroy(obj)
    if obj == nil or type(obj.getGUID) ~= "function" then return end
    local guid = obj.getGUID()
    for color, record in pairs(TargetRegistry.active) do
        if record.sourceGUID == guid then
            TargetRegistry.active[color] = nil
        else
            targetRemove(record, guid)
        end
    end
    -- Committed records deliberately retain identity; read() reports valid=false.
end

function TargetRegistry.onHover(color, obj)
    if not Combat.OWNERS[color] then return end
    -- Preserve last visible card while the player moves the cursor to chat.
    -- A nil hover event must not make chat-based inspect/target impossible.
    if targetCard(obj) then TargetRegistry.hovered[color] = obj.getGUID() end
end

function TargetRegistry.load()
    TargetRegistry.active = {}
    TargetRegistry.committed = {}
    TargetRegistry.order = {}
    TargetRegistry.latest = {}
    TargetRegistry.hovered = {}
    TargetRegistry.sequence = 0
end

local function targetDescribe(color, result)
    if result.status == "none" then
        targetTell(color, "No active or committed target selection.")
        return
    end
    if result.status == "invalid" then
        targetTell(color, result.reason or "Invalid target selection.")
        return
    end
    targetTell(color, result.status .. " " .. tostring(result.id) ..
        " | " .. tostring(result.count or 0) .. " target(s)")
    for i, value in ipairs(result.targets or {}) do
        targetTell(color, tostring(i) .. ". " .. value.name .. " [" ..
            value.guid .. "]" .. (value.valid and "" or " (missing)"))
    end
end

-- Small test interface; no new hotkeys or modal menus. Each command is hidden
-- from public chat. This is a prototype interface, not automatic resolution.
function TargetRegistry.onChat(message, player)
    if type(message) ~= "string" or player == nil then return nil end
    local command = message:lower():gsub("^%s+", ""):gsub("%s+$", "")
    local recognized = {
        ["mtg inspect"] = true, ["mtg target"] = true,
        ["mtg done"] = true, ["mtg cancel"] = true,
        ["mtg targets"] = true, ["mtg help"] = true
    }
    if not recognized[command] then return nil end
    local color = player.color
    if not Combat.OWNERS[color] then return false end
    if command == "mtg help" then
        targetTell(color, "Hover a face-up card: mtg inspect = catalog lookup; " ..
            "mtg target = start a selection. Draw arrows normally, " ..
            "mtg done = commit, mtg targets = inspect, mtg cancel = discard draft.")
    elseif command == "mtg inspect" then
        local guid = TargetRegistry.hovered[color]
        if not guid then
            targetTell(color, "Hover over a face-up card first.")
        else
            local ok, result = pcall(function()
                return Global.call("mtgCardCatalogRequest", {guid = guid, color = color})
            end)
            if not ok or type(result) ~= "table" then
                targetTell(color, "Catalog lookup failed to start.")
            elseif result.status == "pending" then
                local localData = result.localData or {}
                targetTell(color, "Looking up " ..
                    tostring(localData.name or guid) .. " (MTGA, then Scryfall).")
            elseif result.status == "invalid" then
                targetTell(color, result.reason or "Not a visible card.")
            end
            -- Ready/missing cached results are sent directly by Global.
        end
    elseif command == "mtg target" then
        local result = TargetRegistry.begin({
            color = color, sourceGUID = TargetRegistry.hovered[color]
        })
        if result.status == "active" then
            targetTell(color, "Selecting targets for " ..
                targetName(getObjectFromGUID(result.sourceGUID)) ..
                ". Draw arrows from THIS card, then type mtg done.")
        else
            targetTell(color, result.reason or "Hover over the source card.")
        end
    elseif command == "mtg done" then
        targetDescribe(color, TargetRegistry.finish({color = color}))
    elseif command == "mtg cancel" then
        local result = TargetRegistry.cancel({color = color})
        targetTell(color, result.status == "cancelled" and
            "Selection discarded (visual arrows unchanged)." or "No active selection.")
    elseif command == "mtg targets" then
        targetDescribe(color, TargetRegistry.read({color = color}))
    end
    return false
end
