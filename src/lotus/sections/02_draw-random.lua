-- Random draw works on real decks in eligible zones. A deck merge can invalidate TTS references, so recheck them around asynchronous moves.

-- =============================================================
-- MODULE 3/4: DRAW RANDOM
--
-- Right-click Deck -> Draw Random inside a Library, Graveyard or Exile
-- scripting zone (the deck itself does not need any tags).
--
-- TTS merges and destroys Decks during draws/mills/shuffles. Zone snapshots
-- may briefly contain invalid Unity object references. Never trust a
-- reference from getObjects(true) without validating it inside pcall.
--
-- Register a context menu only after seeing the same live Deck GUID in two
-- CONSECUTIVE complete scans. Event callbacks must not bypass this buffer.
-- Once registered, preserve the menu when the deck moves: TTS cannot remove
-- an individual context-menu item without clearing other scripts' menus.
-- At click time, always recheck the deck's CURRENT zone.
-- =============================================================

local DrawRandom = {
    ZONE_TAGS = { "Graveyard", "Library", "Exile" },
    SCAN_INTERVAL = 2.0,
    registered = {}, -- deck GUID -> context menu installed
    candidates = {}, -- deck GUID -> {scan=N, count=N}
    scanNumber = 0,
}

-- A reference may be destroyed between returning from zone.getObjects(true)
-- and reading its type/GUID. Guard both access and isDestroyed() itself.
function DrawRandom.isAlive(obj, expectedType)
    if obj == nil then return false end
    local ok, alive = pcall(function()
        return obj.isDestroyed() == false
            and (expectedType == nil or obj.type == expectedType)
    end)
    return ok and alive == true
end

-- Read a GUID without assuming the TTS object still exists.
function DrawRandom.safeGuid(obj)
    if not DrawRandom.isAlive(obj) then return nil end
    local ok, guid = pcall(function() return obj.getGUID() end)
    if ok and type(guid) == "string" and guid ~= "" then
        return guid
    end
    return nil
end

function DrawRandom.isSupportedZone(zone)
    if not DrawRandom.isAlive(zone, "Scripting") then return false end
    local ok, supported = pcall(function()
        for _, tag in ipairs(DrawRandom.ZONE_TAGS) do
            if zone.hasTag(tag) then return true end
        end
        return false
    end)
    return ok and supported == true
end

function DrawRandom.getZones()
    local zones, seen = {}, {}
    for _, tag in ipairs(DrawRandom.ZONE_TAGS) do
        local ok, candidates = pcall(function()
            return getObjectsWithTag(tag) or {}
        end)
        if ok and type(candidates) == "table" then
            for _, zone in ipairs(candidates) do
                if DrawRandom.isAlive(zone, "Scripting") then
                    local guid = DrawRandom.safeGuid(zone)
                    if guid and not seen[guid] then
                        seen[guid] = true
                        zones[#zones + 1] = zone
                    end
                end
            end
        end
    end
    return zones
end

-- Scripting zones need ignore-tags=true: decks without matching tags must
-- still be discoverable. A failed call is not evidence that a zone is empty.
function DrawRandom.safeZoneObjects(zone)
    if not DrawRandom.isAlive(zone, "Scripting") then return nil end
    local ok, objects = pcall(function() return zone.getObjects(true) end)
    if ok and type(objects) == "table" then return objects end
    return nil
end

-- Click-time eligibility is deliberately live, not cached. No menu action
-- is allowed after the deck has left its Library/Graveyard/Exile zone.
function DrawRandom.isEligible(deck)
    if not DrawRandom.isAlive(deck, "Deck") then return false end
    local guid = DrawRandom.safeGuid(deck)
    if guid == nil then return false end
    for _, zone in ipairs(DrawRandom.getZones()) do
        for _, obj in ipairs(DrawRandom.safeZoneObjects(zone) or {}) do
            if DrawRandom.isAlive(obj, "Deck") then
                if obj == deck or DrawRandom.safeGuid(obj) == guid then
                    return DrawRandom.isAlive(deck, "Deck")
                end
            end
        end
    end
    return false
end

-- Choose one entry from the real deck and deal it to the requesting player.
function DrawRandom.draw(playerColor, position, deck)
    if not DrawRandom.isEligible(deck) then
        broadcastToColor(
            "Draw Random: deck is outside a Graveyard, Library or Exile zone.",
            playerColor, {1, 0.5, 0.3}
        )
        return
    end

    local player = Player[playerColor]
    if player == nil or player.getHandCount() < 1 then
        broadcastToColor(
            "Draw Random: no hand zone available.",
            playerColor, {1, 0.5, 0.3}
        )
        return
    end

    -- Decks may vanish while the player opens the context menu.
    local ok, cards = pcall(function()
        if not DrawRandom.isAlive(deck, "Deck") then return nil end
        return deck.getObjects()
    end)
    if not ok or type(cards) ~= "table" or #cards == 0 then return end

    local selected = cards[math.random(1, #cards)]
    if type(selected) ~= "table" then return end

    -- Reveal Top uses a physical visual-only clone above the library.
    -- Remove it and pause its refresh while the deck splits/replaces itself.
    -- This prevents duplicate-looking top cards and visual/deck merge races.
    if RevealTop and type(RevealTop.suspendDuringDraw) == "function" then
        local pauseOK, pauseErr = pcall(RevealTop.suspendDuringDraw, deck)
        if not pauseOK then
            print("[MTG Draw Random] Reveal Top pause failed: " .. tostring(pauseErr))
        end
    end

    -- takeObject's default spawn point is deck position +2 on world X.
    -- That short-lived physical Card can nudge a nearby library. Extract it
    -- well above the original deck, then deal it straight into the hand.
    local posOK, drawPosition = pcall(function()
        local p = deck.getPosition()
        return {x = p.x, y = p.y + 6, z = p.z}
    end)
    if not posOK or type(drawPosition) ~= "table"
        or type(drawPosition.x) ~= "number"
        or type(drawPosition.y) ~= "number"
        or type(drawPosition.z) ~= "number" then
        drawPosition = nil
    end

    -- Freeze only an originally-unlocked deck for a few frames while its
    -- internal Card is extracted; never change an already-locked deck.
    local lockedByDraw = false
    local lockOK, wasLocked = pcall(function() return deck.locked end)
    if lockOK and wasLocked == false and #cards > 2 then
        lockedByDraw = pcall(function() deck.setLock(true) end)
    end

    local takeParameters = {
        smooth = false,
        callback_function = function(card)
            if not DrawRandom.isAlive(card, "Card") then return end
            Wait.condition(
                function()
                    if not DrawRandom.isAlive(card, "Card") then return end
                    local dealt, err = pcall(function()
                        if card.isDestroyed() then return end
                        card.use_hands = true
                        card.deal(1, playerColor, 1)
                    end)
                    if not dealt then
                        print("MTG Draw Random: deal failed: " .. tostring(err))
                    end
                end,
                function()
                    if not DrawRandom.isAlive(card, "Card") then return true end
                    local ready, spawning = pcall(function()
                        return card.spawning
                    end)
                    return not ready or not spawning
                end,
                3,
                function()
                    print("MTG Draw Random: timed out waiting for card to spawn.")
                end
            )
        end
    }

    if drawPosition then takeParameters.position = drawPosition end

    -- Select by GUID whenever available; never pass both index and GUID.
    if type(selected.guid) == "string" and selected.guid ~= "" then
        takeParameters.guid = selected.guid
    else
        takeParameters.index = selected.index
    end

    local taken, err = pcall(function()
        if not DrawRandom.isAlive(deck, "Deck") then return end
        deck.takeObject(takeParameters)
    end)
    if lockedByDraw then
        local function releaseDeck()
            if DrawRandom.isAlive(deck, "Deck") then
                pcall(function() deck.setLock(false) end)
            end
        end
        local scheduled = pcall(function() Wait.frames(releaseDeck, 8) end)
        if not scheduled then releaseDeck() end
    end
    if not taken then
        print("MTG Draw Random: takeObject failed: " .. tostring(err))
        broadcastToColor("Draw Random failed.", playerColor, {1, 0.4, 0.4})
    end
end

-- Called only by scan() after the two-scan stability buffer. No redundant
-- nested search through every zone. Keep existing context menus untouched.
function DrawRandom.registerDeck(deck)
    if not DrawRandom.isAlive(deck, "Deck") then return false end
    local guid = DrawRandom.safeGuid(deck)
    if guid == nil or DrawRandom.registered[guid] then return false end

    local ok, added = pcall(function()
        if deck.isDestroyed() or deck.type ~= "Deck" then return false end
        deck.addContextMenuItem("Draw Random", DrawRandom.draw)
        return true
    end)
    if ok and added then
        DrawRandom.registered[guid] = true
        DrawRandom.candidates[guid] = nil
        return true
    end
    return false -- transient/invalidation: retry only if seen in later scans
end

function DrawRandom.scan()
    -- Scripting-zone tag filtering suppresses some native enter events,
    -- so event-only discovery is not sufficient.
    DrawRandom.scanNumber = DrawRandom.scanNumber + 1
    local scan = DrawRandom.scanNumber
    local found = {} -- once per GUID even if zones overlap

    for _, zone in ipairs(DrawRandom.getZones()) do
        local objects = DrawRandom.safeZoneObjects(zone)
        if objects ~= nil then
            for _, obj in ipairs(objects) do
                if DrawRandom.isAlive(obj, "Deck") then
                    local guid = DrawRandom.safeGuid(obj)
                    if guid and not found[guid] then
                        found[guid] = true
                        if not DrawRandom.registered[guid] then
                            local previous = DrawRandom.candidates[guid]
                            local count = 1
                            if previous and previous.scan == scan - 1 then
                                count = previous.count + 1
                            end
                            DrawRandom.candidates[guid] = {
                                scan = scan, count = count
                            }
                            if count >= 2 then
                                DrawRandom.registerDeck(obj)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Break the consecutive-scan streak when a deck disappears. Do not
    -- erase 'registered': context menus must never be duplicated on reentry.
    for guid in pairs(DrawRandom.candidates) do
        if not found[guid] then DrawRandom.candidates[guid] = nil end
    end
end

function DrawRandom.onEnterZone(zone, obj)
    -- Deliberately do not register or schedule a callback here.
    -- An immediate onEnterZone would bypass the two-scan safety buffer.
end

-- Forget the registration for a destroyed deck.
function DrawRandom.onDestroy(obj)
    -- onObjectDestroy may deliver a reference already invalidated by Unity.
    if obj == nil then return end
    local ok, guid = pcall(function()
        if obj.type == "Deck" then return obj.getGUID() end
    end)
    if ok and guid then
        DrawRandom.registered[guid] = nil
        DrawRandom.candidates[guid] = nil
    end
end

-- Start the initial scan and periodic context-menu refresh.
function DrawRandom.load()
    DrawRandom.registered = {}
    DrawRandom.candidates = {}
    DrawRandom.scanNumber = 0
    Wait.frames(DrawRandom.scan, 5)
    Wait.time(DrawRandom.scan, DrawRandom.SCAN_INTERVAL, -1)
    log("MTG Portable Helper: Draw Random module ready.")
end

