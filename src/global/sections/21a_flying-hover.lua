-- Flying visual effect: subtle, slow, low-cost motion of the actual card.
-- No clones, no locks, no new UI. Only an enabled πKeywords/Flying value
-- on a face-up card resting in a tracked battlefield scripting zone qualifies.
-- Physical stacking, pickup, leaving play and keyword removal stop the effect.
local mtgFlyActive, mtgFlyHeld, mtgFlyPending = {}, {}, {}
local mtgFlyRunning, mtgFlyEnabled = false, true
local FLY_H, FLY_BOB, FLY_DRIFT = 0.11, 0.035, 0.018
local FLY_STEP = 0.65

local function mtgFlyAlive(obj)
    if obj == nil or obj.type ~= "Card" then return false end
    local ok, dead = pcall(function() return obj.isDestroyed() end)
    return ok and not dead
end

local function mtgFlyZone(obj)
    for _, color in ipairs(mtgPlayerColors) do
        local p = data and data[color]
        if p and p.playmat and zoneContains(p.playmat, obj) then
            return p.playmat
        end
    end
    return nil
end

local function mtgFlyHasKeyword(obj)
    local enc = Global.getVar("Encoder")
    if enc == nil then return false end
    local ok, result = pcall(function()
        if enc.call("APIobjIsPropEnabled", {
            obj=obj, propID="πKeywords"
        }) ~= true then return false end
        local d = enc.call("APIobjGetPropData", {
            obj=obj, propID="πKeywords"
        })
        return type(d) == "table"
            and (tonumber(d.mtg_flyingcounter) or 0) > 0
    end)
    return ok and result == true
end

-- Avoid separating stacked cards and decks. Rare raycasts only, never per frame.
local function mtgFlyStacked(obj)
    local p = obj.getPosition()
    local ok, hits = pcall(function()
        return Physics.cast({
            origin={p.x, p.y + 0.32, p.z},
            direction={0, -1, 0}, type=1, max_distance=0.70
        })
    end)
    if not ok then return true end
    for _, hit in ipairs(hits or {}) do
        local other = hit.hit_object
        if other and other ~= obj
            and (other.type == "Card" or other.type == "Deck") then
            return true
        end
    end
    return false
end

function mtgFlyingHoverStop(target, cancelMotion)
    local obj = type(target) == "string" and getObjectFromGUID(target) or target
    local guid = type(target) == "string" and target
        or (obj and obj.getGUID())
    if not guid or not mtgFlyActive[guid] then return end
    mtgFlyActive[guid] = nil
    if mtgFlyAlive(obj) then
        if cancelMotion then
            pcall(function() obj.setPosition(obj.getPosition()) end)
        end
        pcall(function() obj.use_gravity = true end)
    end
end

local function mtgFlyStart(obj)
    if not mtgFlyEnabled or not mtgFlyAlive(obj)
        or obj.is_face_down then return end
    local guid = obj.getGUID()
    if not guid or mtgFlyHeld[guid] or mtgFlyActive[guid]
        or obj.hasTag("FetchPreview")
        or obj.hasTag("MTG_Lotus_RevealTop_VisualOnly") then return end
    local ok, locked = pcall(function() return obj.getLock() end)
    if not ok or locked then return end
    local zone = mtgFlyZone(obj)
    if not zone or not mtgFlyHasKeyword(obj) then return end
    local savedHover = obj.use_gravity == false
    if not savedHover and not obj.resting then return end
    if mtgFlyStacked(obj) then return end
    local pos = obj.getPosition()
    mtgFlyActive[guid] = {
        anchor={x=pos.x, y=pos.y - (savedHover and FLY_H or 0), z=pos.z},
        zone=zone, phase=(tonumber(guid:sub(-2), 16) or 0)*0.15,
        checkAt=Time.time+2.5
    }
    -- Intentionally leave interactable/locked/hand settings untouched.
    obj.use_gravity = false
end

-- Called by the Keywords module when the encoder's Flying state changes.
-- A single deferred check, not a new permanent timer for every card.
function mtgFlyingHoverRequest(params)
    local guid = type(params) == "table" and params.guid or params
    if type(guid) ~= "string" or guid == "" then return end
    local obj = getObjectFromGUID(guid)
    if not mtgFlyAlive(obj) then
        mtgFlyingHoverStop(guid, false)
        return
    end
    if not mtgFlyHasKeyword(obj) then
        mtgFlyingHoverStop(obj, false)
        return
    end
    if mtgFlyActive[guid] or mtgFlyHeld[guid]
        or mtgFlyPending[guid] then return end
    if obj.resting or obj.use_gravity == false then
        mtgFlyStart(obj)
        return
    end
    mtgFlyPending[guid] = true
    Wait.condition(function()
        mtgFlyPending[guid] = nil
        local current = getObjectFromGUID(guid)
        if mtgFlyAlive(current) and not mtgFlyHeld[guid] then
            mtgFlyStart(current)
        end
    end, function()
        local current = getObjectFromGUID(guid)
        return not mtgFlyAlive(current) or mtgFlyHeld[guid]
            or current.resting or current.use_gravity == false
    end, 3, function()
        mtgFlyPending[guid] = nil
    end)
end

local function mtgFlyTick()
    local now = Time.time
    for guid, s in pairs(mtgFlyActive) do
        local obj = getObjectFromGUID(guid)
        local stop = not mtgFlyAlive(obj)
        if not stop then
            local p, a = obj.getPosition(), s.anchor
            if obj.is_face_down or mtgFlyHeld[guid] or obj.getLock()
                or obj.use_gravity ~= false
                or math.abs(p.x-a.x) > 0.38
                or math.abs(p.y-a.y) > 0.40
                or math.abs(p.z-a.z) > 0.38 then
                stop = true
            elseif now >= s.checkAt then
                s.checkAt = now + 2.5
                if not mtgFlyHasKeyword(obj)
                    or not zoneContains(s.zone, obj)
                    or mtgFlyStacked(obj) then stop = true end
            end
        end
        if stop then
            mtgFlyingHoverStop(guid, false)
        else
            local a, phase = s.anchor, s.phase
            local target = {
                x=a.x + FLY_DRIFT*math.sin(now*0.9+phase),
                y=a.y + FLY_H + FLY_BOB*math.sin(now*1.4+phase),
                z=a.z + FLY_DRIFT*math.cos(now*0.75+phase)
            }
            local ok = pcall(function()
                obj.setPositionSmooth(target, false, false)
            end)
            if not ok then mtgFlyingHoverStop(guid, false) end
        end
    end
end

function mtgFlyingHoverEnter(zone, obj)
    if not mtgFlyAlive(obj) then return end
    for _, color in ipairs(mtgPlayerColors) do
        if data[color] and data[color].playmat == zone then
            mtgFlyingHoverRequest({guid=obj.getGUID()})
            return
        end
    end
end

function mtgFlyingHoverLeave(zone, obj)
    if not mtgFlyAlive(obj) then return end
    local state = mtgFlyActive[obj.getGUID()]
    if state and state.zone == zone then
        mtgFlyingHoverStop(obj, false)
    end
end

-- Existing Global.onObjectDropped (keyword token actions) is not replaced.
function onObjectPickUp(color, obj)
    if not mtgFlyAlive(obj) then return end
    local guid = obj.getGUID()
    mtgFlyHeld[guid] = true
    mtgFlyingHoverStop(obj, true)
end

function onObjectDrop(color, obj)
    if not mtgFlyAlive(obj) then return end
    local guid = obj.getGUID()
    mtgFlyHeld[guid] = nil
    mtgFlyingHoverRequest({guid=guid})
end

function onObjectDestroy(obj)
    if not obj then return end
    local ok, guid = pcall(function() return obj.getGUID() end)
    if not ok or not guid then return end
    mtgFlyActive[guid], mtgFlyHeld[guid], mtgFlyPending[guid] = nil, nil, nil
end

-- Emergency console command: Global.call("mtgFlyingHoverDisable").
function mtgFlyingHoverDisable()
    mtgFlyEnabled = false
    for guid, _ in pairs(mtgFlyActive) do
        mtgFlyingHoverStop(guid, false)
    end
end

function mtgFlyingHoverInit()
    if mtgFlyRunning then return end
    mtgFlyRunning = true
    Wait.time(mtgFlyTick, FLY_STEP, -1)
    for _, color in ipairs(mtgPlayerColors) do
        local p = data and data[color]
        if p and p.playmat then
            for _, obj in ipairs(mtgZoneObjects(p.playmat)) do
                if obj.type == "Card" then
                    mtgQueuePrintedKeywordEquip(p.playmat, obj)
                    mtgFlyingHoverRequest({guid=obj.getGUID()})
                end
            end
        end
    end
end
