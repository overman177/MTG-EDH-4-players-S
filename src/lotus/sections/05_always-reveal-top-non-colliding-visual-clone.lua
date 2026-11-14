-- =============================================================
-- MODULE 6: ALWAYS REVEAL TOP (NON-COLLIDING VISUAL CLONE)
--
-- The ORIGINAL deck is never modified. The visible face is a separately
-- spawned copy of the top card's serialized data (NOT takeObject()).
-- Using the original card data also preserves its exact printing / sheet
-- without Scryfall or a 3D UI image loader.
--
-- The clone is locked, non-interactable, gravity-free, non-colliding,
-- and tagged. Global's
-- getCardFromZone() ignores it because that function specifically skips
-- Card objects with use_gravity=false. Never use the clone for game actions.
-- =============================================================
RevealTop = {
    COLORS = {"White", "Red", "Yellow", "Blue"},
    LIBRARY_GUIDS = {
        White = "166036", Red = "2365d0", Yellow = "033b34", Blue = "c04462"
    },
    VISUAL_TAG = "MTG_Lotus_RevealTop_VisualOnly",
    OLD_ANCHOR_TAG = "MTG_Lotus_RevealTop_Anchor",
    enabled = {}, registered = {}, signatures = {}, versions = {},
    visualGuids = {}, visuals = {}, spawning = {}, errors = {}, retryAt = {},
    cleanedDecks = {},
    POLL_SECONDS = 0.65,
    -- Vertical clearance above the upper face of the real library. A visible
    -- gap reduces the risk of TTS merging the decorative card with the deck.
    HEIGHT_ABOVE_DECK = 0.22,
}

local function rtName(raw)
    local name = tostring(raw or ""):match("^([^\r\n]*)") or ""
    return name:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Decks and loose Cards can disappear while TTS merges a library stack.
-- Deferred callbacks must not dereference the original Unity object.
local function rtAlive(obj)
    if obj == nil then return false end
    local ok, destroyed = pcall(function() return obj.isDestroyed() end)
    return ok and destroyed == false
end

local function rtIsVisual(obj)
    if obj == nil then return false end
    local ok, visual = pcall(function()
        return obj.hasTag ~= nil and obj.hasTag(RevealTop.VISUAL_TAG)
    end)
    return ok and visual == true
end

function RevealTop.findZone(color)
    local original = getObjectFromGUID(RevealTop.LIBRARY_GUIDS[color])
    if original and original.type == "Scripting"
        and original.hasTag("Library") and original.hasTag(color) then return original end
    for _, zone in ipairs(getObjectsWithTag("Library") or {}) do
        if zone.type == "Scripting" and zone.hasTag(color) then return zone end
    end
    if original and original.type == "Scripting" then return original end
    return nil
end

function RevealTop.findLibrary(color)
    local zone = RevealTop.findZone(color)
    if not zone then return nil end
    local nearestDeck, nearestCard = nil, nil
    local deckDist, cardDist = math.huge, math.huge
    for _, obj in ipairs(zone.getObjects(true) or {}) do
        if obj and not rtIsVisual(obj)
            and (obj.type == "Deck" or obj.type == "Card") then
            local localPos = zone.positionToLocal(obj.getPosition())
            local d = localPos.x * localPos.x + localPos.z * localPos.z
            if obj.type == "Deck" and d < deckDist then
                nearestDeck, deckDist = obj, d
            elseif obj.type == "Card" and d < cardDist then
                nearestCard, cardDist = obj, d
            end
        end
    end
    -- A library can become a single Card after drawing its second-last card.
    -- Prefer an actual Deck when both types are in the zone.
    if nearestDeck and deckDist < 1.0 then return nearestDeck end
    if nearestCard and cardDist < 1.0 then return nearestCard end
    return nearestDeck or nearestCard
end

function RevealTop.addMenu(obj, confirmedLibrary)
    if not obj or (obj.type ~= "Deck" and obj.type ~= "Card")
        or rtIsVisual(obj) or obj.isDestroyed() then return end
    -- The periodic seat poll has already established library residency.
    -- Calls from spawn still validate the object's current location.
    if not confirmedLibrary then
        local isLibrary = false
        for _, color in ipairs(RevealTop.COLORS) do
            if RevealTop.findLibrary(color) == obj then isLibrary = true; break end
        end
        if not isLibrary then return end
    end
    local guid = obj.getGUID()
    if not guid or RevealTop.registered[guid] then return end
    local ok, err = pcall(function()
        -- One concise entry that fits the default TTS context menu.
        -- Refresh and diagnostics remain available as Lua functions, but
        -- are intentionally not exposed as extra right-click entries.
        obj.addContextMenuItem("Always Reveal Top", function(playerColor, pos, cardOrDeck)
            RevealTop.toggle(playerColor, cardOrDeck)
        end)
    end)
    if ok then RevealTop.registered[guid] = true end
end

-- Clean only artifacts left by the previous UI-based reveal builds.
function RevealTop.cleanOldUI()
    local xml = UI.getXmlTable() or {}
    local changed = false
    for i = #xml, 1, -1 do
        if xml[i].attributes and xml[i].attributes.id == "LotusRTContainer" then
            table.remove(xml, i)
            changed = true
        end
    end
    if changed then UI.setXmlTable(xml) end
    for _, anchor in ipairs(getObjectsWithTag(RevealTop.OLD_ANCHOR_TAG) or {}) do
        pcall(function() anchor.destruct() end)
    end
end

function RevealTop.cleanOldDeckUI(deck)
    if not deck or deck.isDestroyed() then return end
    local guid = deck.getGUID()
    if RevealTop.cleanedDecks[guid] then return end
    RevealTop.cleanedDecks[guid] = true
    pcall(function()
        local xml = deck.UI.getXmlTable() or {}
        local changed = false
        for i = #xml, 1, -1 do
            if xml[i].attributes and xml[i].attributes.id == "LotusRTWorldImage" then
                table.remove(xml, i)
                changed = true
            end
        end
        if changed then deck.UI.setXmlTable(xml) end
    end)
end

-- Inspect the library without taking or modifying its cards. A GUID lookup
-- avoids assuming getData().ContainedObjects uses the same order as getObjects().
function RevealTop.inspect(color, includeData)
    local library = RevealTop.findLibrary(color)
    if not library or library.isDestroyed() then return nil, "No library" end
    local info = {library=library}
    if library.type == "Card" then
        info.name = rtName(library.getName())
        if info.name == "" then return nil, "Card has no name" end
        info.signature = "single:" .. library.getGUID() .. ":" .. info.name
        if includeData then
            local ok, data = pcall(function() return library.getData() end)
            if not ok or type(data) ~= "table" then
                return nil, "Could not read single-card data: " .. tostring(data)
            end
            info.cardData = data
        end
        return info
    end

    local cards = library.getObjects() or {}
    if #cards == 0 then return nil, "Library is empty" end
    local top = cards[1]
    info.name = rtName(top.name)
    if info.name == "" then return nil, "Top card has no name" end
    info.signature = library.getGUID() .. ":" .. #cards .. ":"
        .. tostring(top.guid) .. ":" .. info.name
    if not includeData then return info end

    local ok, deckData = pcall(function() return library.getData() end)
    if not ok or type(deckData) ~= "table" then
        return nil, "Could not read deck data: " .. tostring(deckData)
    end
    for _, cardData in ipairs(deckData.ContainedObjects or {}) do
        if tostring(cardData.GUID or "") == tostring(top.guid or "") then
            info.cardData = cardData
            info.deckData = deckData
            return info
        end
    end
    -- Fail closed: spawning a different card would leak wrong information.
    return nil, "Top GUID missing from deck data (" .. tostring(top.guid) .. ")"
end

function RevealTop.visualFor(color)
    local obj = RevealTop.visuals[color]
    if rtAlive(obj) and rtIsVisual(obj) then return obj end
    local guid = RevealTop.visualGuids[color]
    if guid then
        obj = getObjectFromGUID(guid)
        if rtAlive(obj) and rtIsVisual(obj) then
            RevealTop.visuals[color] = obj
            return obj
        end
    end
    RevealTop.visuals[color] = nil
    RevealTop.visualGuids[color] = nil
    return nil
end

function RevealTop.removeVisual(color)
    local obj = RevealTop.visualFor(color)
    RevealTop.visuals[color] = nil
    RevealTop.visualGuids[color] = nil
    if obj then pcall(function() obj.destruct() end) end
end

function RevealTop.topPosition(library)
    local pos = library.getPosition()
    local topY = pos.y + 0.25
    local ok, bounds = pcall(function() return library.getBounds() end)
    if ok and bounds and bounds.center and bounds.size then
        topY = bounds.center.y + 0.5 * bounds.size.y
    end
    return {x=pos.x, y=topY + RevealTop.HEIGHT_ABOVE_DECK, z=pos.z}
end

function RevealTop.faceUpRotation(library)
    local rot = library.getRotation()
    -- Same convention as Global.revealFanRot: z=0 means card face up.
    return {x=0, y=rot.y, z=0}
end

function RevealTop.follow(color, library)
    local obj = RevealTop.visualFor(color)
    if not rtAlive(obj) or not rtAlive(library) then return end
    local newPos = RevealTop.topPosition(library)
    local oldPos = obj.getPosition()
    if math.abs(newPos.x - oldPos.x) > 0.035
        or math.abs(newPos.y - oldPos.y) > 0.035
        or math.abs(newPos.z - oldPos.z) > 0.035 then
        obj.setPosition(newPos)
    end
    local wanted = RevealTop.faceUpRotation(library)
    local current = obj.getRotation()
    if math.abs((current.y - wanted.y + 180) % 360 - 180) > 1
        or math.abs(current.x) > 1 or math.abs(current.z) > 1 then
        obj.setRotation(wanted)
    end
end

-- Data from deck.getData() is a new Lua table. Modify ONLY that copy.
-- In particular GUID must not be copied: TTS needs a fresh object identity.
function RevealTop.prepareClone(info, color)
    local card = info.cardData
    if not card or type(card) ~= "table" then return nil, "Missing card data" end
    card.GUID = nil
    card.Name = card.Name or "Card"
    card.Transform = card.Transform or {}
    card.Tags = {RevealTop.VISUAL_TAG, "LotusRT_" .. color}
    card.LuaScript = ""
    card.LuaScriptState = ""
    card.XmlUI = ""
    card.GMNotes = ""
    card.Locked = true
    card.Sticky = false
    card.Hands = false
    card.Tooltip = false
    card.Grid = false
    card.Snap = false
    card.Autoraise = false
    card.DragSelectable = false
    card.HideWhenFaceDown = false

    -- Some deck containers keep their card-sheet definitions on the parent.
    -- Preserve original CardID and all texture definitions (also for shared
    -- multi-card sheets). No external network request or image remapping.
    if info.deckData and type(info.deckData.CustomDeck) == "table" then
        card.CustomDeck = card.CustomDeck or {}
        for key, sheet in pairs(info.deckData.CustomDeck) do
            if card.CustomDeck[key] == nil then card.CustomDeck[key] = sheet end
        end
    end
    return card
end

-- Disable the visual card's PHYSICAL Unity colliders, not the real Deck's.
-- Locking, interactable=false, and use_gravity=false do not remove colliders.
-- Cards normally use BoxCollider; search children too in case an importer
-- supplies extra collider components. Leave the visible MeshRenderer intact.
function RevealTop.disableVisualColliders(obj)
    if obj == nil or obj.isDestroyed() or not rtIsVisual(obj) then return 0 end
    local disabled, seen = 0, {}
    for _, kind in ipairs({"BoxCollider", "MeshCollider", "SphereCollider", "CapsuleCollider"}) do
        local components = {}
        -- getComponentsInChildren searches the object and its children.
        local ok, found = pcall(function()
            return obj.getComponentsInChildren(kind)
        end)
        if ok and type(found) == "table" then
            for _, component in ipairs(found) do
                components[#components + 1] = component
            end
        end
        -- Fallback for objects/versions that only expose a root component.
        if #components == 0 then
            local rootOK, root = pcall(function() return obj.getComponent(kind) end)
            if rootOK and root ~= nil then components[1] = root end
        end
        for _, component in ipairs(components) do
            if component ~= nil and not seen[component] then
                seen[component] = true
                local setOK = pcall(function() component.set("enabled", false) end)
                if setOK then disabled = disabled + 1 end
            end
        end
    end
    return disabled
end

function RevealTop.spawnVisual(color, info)
    local version = RevealTop.versions[color] or 0
    local card, err = RevealTop.prepareClone(info, color)
    if not card then
        RevealTop.errors[color] = err
        return
    end
    RevealTop.spawning[color] = version
    RevealTop.retryAt[color] = os.time()
    local ok, why = pcall(function()
        spawnObjectData({
            data = card,
            position = RevealTop.topPosition(info.library),
            rotation = RevealTop.faceUpRotation(info.library),
            callback_function = function(obj)
                if RevealTop.spawning[color] == version then
                    RevealTop.spawning[color] = nil
                end
                if not obj then
                    RevealTop.errors[color] = "Spawn callback returned no object"
                    return
                end
                if not RevealTop.enabled[color] or RevealTop.versions[color] ~= version then
                    pcall(function() obj.destruct() end)
                    return
                end
                -- Re-resolve the library after the async spawn. A group of
                -- loose cards can replace the Deck before this callback runs.
                local freshOK, fresh = pcall(function()
                    return RevealTop.inspect(color, false)
                end)
                if not freshOK or not fresh
                    or fresh.signature ~= info.signature
                    or not rtAlive(fresh.library) then
                    RevealTop.signatures[color] = nil
                    RevealTop.errors[color] = "Library changed while visual spawned"
                    pcall(function() obj.destruct() end)
                    return
                end
                local success, setupErr = pcall(function()
                    obj.addTag(RevealTop.VISUAL_TAG)
                    obj.addTag("LotusRT_" .. color)
                    obj.use_gravity = false
                    obj.use_hands = false
                    obj.interactable = false
                    obj.tooltip = false
                    obj.sticky = false
                    obj.setLock(true)
                    obj.setPosition(RevealTop.topPosition(fresh.library))
                    obj.setRotation(RevealTop.faceUpRotation(fresh.library))
                    -- Components can be available immediately, but some TTS
                    -- spawns initialize physics in the following frame.
                    RevealTop.disableVisualColliders(obj)
                end)
                if not success then
                    RevealTop.errors[color] = "Clone setup: " .. tostring(setupErr)
                    pcall(function() obj.destruct() end)
                    return
                end
                RevealTop.visuals[color] = obj
                -- Newly created objects receive their final GUID after spawning.
                -- Reapply collider removal after physics initialization; no
                -- effect on the real library or any other card.
                Wait.frames(function()
                    if RevealTop.visuals[color] == obj and rtAlive(obj) then
                        RevealTop.visualGuids[color] = obj.getGUID()
                        local count = RevealTop.disableVisualColliders(obj)
                        if count == 0 then
                            RevealTop.errors[color] = "Visual clone collider could not be disabled"
                        end
                    end
                end, 2)
                RevealTop.errors[color] = nil
            end
        })
    end)
    if not ok then
        if RevealTop.spawning[color] == version then
            RevealTop.spawning[color] = nil
        end
        RevealTop.errors[color] = "spawnObjectData: " .. tostring(why)
    end
end

-- Isolate each seat when physics replaces a library Deck mid-poll.
function RevealTop.pollOne(color)
        local library = RevealTop.findLibrary(color)
        if library then
            RevealTop.addMenu(library, true)
            RevealTop.cleanOldDeckUI(library)
        end
        if RevealTop.enabled[color] then
            local current, err = RevealTop.inspect(color, false)
            local sig = current and current.signature or "missing:" .. tostring(err)
            if RevealTop.signatures[color] ~= sig then
                RevealTop.signatures[color] = sig
                RevealTop.versions[color] = (RevealTop.versions[color] or 0) + 1
                RevealTop.removeVisual(color)
                RevealTop.errors[color] = err
                if current then
                    local full, dataErr = RevealTop.inspect(color, true)
                    if full and full.signature == sig then
                        RevealTop.spawnVisual(color, full)
                    else
                        RevealTop.errors[color] = dataErr or "Library changed during read"
                    end
                end
            elseif current then
                local visual = RevealTop.visualFor(color)
                if visual then
                    RevealTop.follow(color, current.library)
                elseif not RevealTop.spawning[color]
                    and os.time() - (RevealTop.retryAt[color] or 0) >= 5 then
                    local full, dataErr = RevealTop.inspect(color, true)
                    if full and full.signature == sig then
                        RevealTop.spawnVisual(color, full)
                    else
                        RevealTop.errors[color] = dataErr or "Library changed during read"
                    end
                end
            end
        end
end

function RevealTop.poll()
    for _, color in ipairs(RevealTop.COLORS) do
        local ok, err = pcall(RevealTop.pollOne, color)
        if not ok then
            RevealTop.errors[color] = "Transient library change: " .. tostring(err)
            RevealTop.signatures[color] = nil -- retry on the next poll
        end
    end
end

function RevealTop.ownerOf(obj)
    for _, color in ipairs(RevealTop.COLORS) do
        if RevealTop.findLibrary(color) == obj then return color end
    end
    return nil
end

function RevealTop.refresh(playerColor, obj)
    local owner = RevealTop.ownerOf(obj)
    if not owner then return end
    if playerColor ~= owner and playerColor ~= "Black" then return end
    RevealTop.signatures[owner] = nil
    RevealTop.poll()
end

function RevealTop.toggle(playerColor, obj)
    local owner = RevealTop.ownerOf(obj)
    if not owner then
        return
    end
    if playerColor ~= owner and playerColor ~= "Black" then
        return
    end
    RevealTop.enabled[owner] = not RevealTop.enabled[owner]
    RevealTop.versions[owner] = (RevealTop.versions[owner] or 0) + 1
    RevealTop.signatures[owner] = nil
    if RevealTop.enabled[owner] then
        RevealTop.poll()
    else
        RevealTop.removeVisual(owner)
    end
    Playmats.persist()
end

function RevealTop.debug(playerColor, obj)
    local owner = RevealTop.ownerOf(obj)
    if not owner then return end
    local info, err = RevealTop.inspect(owner, false)
    local visual = RevealTop.visualFor(owner)
    local msg = string.format(
        "[Lotus RT debug] owner=%s enabled=%s top=%s clone=%s spawning=%s error=%s",
        owner, tostring(RevealTop.enabled[owner] == true),
        info and info.name or "none", visual and visual.getGUID() or "none",
        tostring(RevealTop.spawning[owner] == true),
        tostring(RevealTop.errors[owner] or err or "none"))
    return msg
end

-- Emergency fallback if a world-space clone obstructs the deck context menu.
-- Players can type `revealtop off` or `revealtop on` in TTS chat.
function RevealTop.onChat(message, player)
    if type(message) ~= "string" or not player then return nil end
    local action = message:lower():match("^%s*revealtop%s+(on)%s*$")
        or message:lower():match("^%s*revealtop%s+(off)%s*$")
        or message:lower():match("^%s*revealtop%s+(refresh)%s*$")
    if not action then return nil end
    local color = player.color
    if not RevealTop.LIBRARY_GUIDS[color] then return false end
    if action == "refresh" then
        RevealTop.signatures[color] = nil
        RevealTop.poll()
    else
        local desired = action == "on"
        if RevealTop.enabled[color] ~= desired then
            RevealTop.enabled[color] = desired
            RevealTop.versions[color] = (RevealTop.versions[color] or 0) + 1
            RevealTop.signatures[color] = nil
            if desired then RevealTop.poll() else RevealTop.removeVisual(color) end
            Playmats.persist()
        end
    end
    return false
end

function RevealTop.load(saved)
    RevealTop.enabled, RevealTop.registered, RevealTop.signatures = {}, {}, {}
    RevealTop.versions, RevealTop.visuals, RevealTop.visualGuids = {}, {}, {}
    RevealTop.spawning, RevealTop.errors, RevealTop.retryAt = {}, {}, {}
    RevealTop.cleanedDecks = {}
    if type(saved) == "string" and saved ~= "" then
        local ok, data = pcall(JSON.decode, saved)
        if ok and type(data) == "table" and type(data.revealTopEnabled) == "table" then
            for _, color in ipairs(RevealTop.COLORS) do
                RevealTop.enabled[color] = data.revealTopEnabled[color] == true
            end
        end
    end
    RevealTop.cleanOldUI()
    -- Proxies/anchors are transient. Destroy any saved copies from this feature
    -- before recreating a single clean visual from the live deck.
    for _, obj in ipairs(getObjectsWithTag(RevealTop.VISUAL_TAG) or {}) do
        pcall(function() obj.destruct() end)
    end
    Wait.frames(RevealTop.poll, 15)
    Wait.time(RevealTop.poll, RevealTop.POLL_SECONDS, -1)
end

function RevealTop.onSpawn(obj)
    if not rtAlive(obj) or (obj.type ~= "Deck" and obj.type ~= "Card")
        or rtIsVisual(obj) then return end
    local guid = obj.getGUID()
    Wait.frames(function()
        -- Re-resolve instead of retaining an object consumed by a new Deck.
        local current = guid and getObjectFromGUID(guid) or nil
        if rtAlive(current) then RevealTop.addMenu(current) end
    end, 3)
end

function RevealTop.onDestroy(obj)
    if not obj then return end
    local guid = obj.getGUID()
    if obj.type == "Deck" or obj.type == "Card" then
        RevealTop.registered[guid] = nil
    end
    if rtIsVisual(obj) then
        for _, color in ipairs(RevealTop.COLORS) do
            if RevealTop.visualGuids[color] == guid
                or RevealTop.visuals[color] == obj then
                RevealTop.visuals[color] = nil
                RevealTop.visualGuids[color] = nil
            end
        end
    end
end

