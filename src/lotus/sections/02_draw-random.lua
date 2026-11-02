-- =============================================================
-- MODULE 3/4: DRAW RANDOM
--
-- Right-click Deck -> Draw Random when it is inside a scripting
-- zone tagged Graveyard, Library or Exile (any player color).
-- A deck never needs its own zone/player tag.
--
-- Important: TTS cannot remove one individual context-menu item.
-- Do not clearContextMenu(): that would erase Global/other scripts'
-- menu entries. Keep one registration per live deck; validate its
-- CURRENT zone when the item is used. The menu may remain visible
-- outside enabled zones, but clicking it cannot draw there.
-- =============================================================

local DrawRandom = {
    ZONE_TAGS = { "Graveyard", "Library", "Exile" },
    SCAN_INTERVAL = 1.0,
    registered = {}  -- deck GUID -> menu registered (until deck is destroyed)
}

function DrawRandom.isSupportedZone(zone)
    if zone == nil or zone.type ~= "Scripting" then return false end
    for _, tag in ipairs(DrawRandom.ZONE_TAGS) do
        if zone.hasTag(tag) then return true end
    end
    return false
end

function DrawRandom.getZones()
    local zones = {}
    local seen = {}

    for _, tag in ipairs(DrawRandom.ZONE_TAGS) do
        for _, zone in ipairs(getObjectsWithTag(tag) or {}) do
            if zone.type == "Scripting" then
                local guid = zone.getGUID()
                if guid ~= nil and not seen[guid] then
                    seen[guid] = true
                    table.insert(zones, zone)
                end
            end
        end
    end
    return zones
end

-- Check live occupancy, NOT the deck's tags and NOT a stale scan result.
function DrawRandom.isEligible(deck)
    if deck == nil or deck.type ~= "Deck" or deck.isDestroyed() then
        return false
    end

    local deckGuid = deck.getGUID()
    if deckGuid == nil then return false end
    for _, zone in ipairs(DrawRandom.getZones()) do
        for _, obj in ipairs(zone.getObjects(true)) do
            if obj == deck or obj.getGUID() == deckGuid then
                return true
            end
        end
    end
    return false
end

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

    local cards = deck.getObjects()
    if cards == nil or #cards == 0 then return end

    local selected = cards[math.random(1, #cards)]
    -- Select by GUID whenever available; index is a safe fallback.
    -- Never pass both index and guid to takeObject().
    local takeParameters = {
        smooth = false,
        callback_function = function(card)
            if card == nil then return end
            Wait.condition(
                function()
                    if card.isDestroyed() then return end
                    card.use_hands = true
                    local ok, err = pcall(function()
                        card.deal(1, playerColor, 1)
                    end)
                    if not ok then
                        print("MTG Draw Random: deal failed: " .. tostring(err))
                    end
                end,
                function()
                    return card.isDestroyed() or not card.spawning
                end,
                3,
                function()
                    print("MTG Draw Random: timed out waiting for card to spawn.")
                end
            )
        end
    }
    if selected.guid ~= nil then
        takeParameters.guid = selected.guid
    else
        takeParameters.index = selected.index
    end

    local ok, err = pcall(function()
        deck.takeObject(takeParameters)
    end)
    if not ok then
        print("MTG Draw Random: takeObject failed: " .. tostring(err))
        broadcastToColor("Draw Random failed.", playerColor, {1, 0.4, 0.4})
    end
end

function DrawRandom.registerDeck(deck)
    if deck == nil or deck.type ~= "Deck" or deck.isDestroyed() then
        return
    end
    local guid = deck.getGUID()
    if guid == nil or DrawRandom.registered[guid] then return end
    if not DrawRandom.isEligible(deck) then return end

    local ok, err = pcall(function()
        deck.addContextMenuItem("Draw Random", DrawRandom.draw)
    end)
    if ok then
        DrawRandom.registered[guid] = true
    else
        print("MTG Draw Random: menu registration failed: " .. tostring(err))
    end
end

function DrawRandom.scan()
    -- Periodic polling is required because tagged TTS scripting zones do
    -- not emit enter/leave events for every untagged Deck.
    for _, zone in ipairs(DrawRandom.getZones()) do
        for _, obj in ipairs(zone.getObjects(true)) do
            if obj.type == "Deck" then
                DrawRandom.registerDeck(obj)
            end
        end
    end
    -- Do NOT reset registered when a deck leaves; Global now preserves
    -- its context menu, so re-registering would duplicate the item.
end

function DrawRandom.onEnterZone(zone, obj)
    if obj == nil or obj.type ~= "Deck" then return end
    if not DrawRandom.isSupportedZone(zone) then return end

    -- Where an enter event does fire, register sooner than the next scan.
    Wait.frames(function()
        if not obj.isDestroyed() then
            DrawRandom.registerDeck(obj)
        end
    end, 3)
end

function DrawRandom.onDestroy(obj)
    if obj == nil or obj.type ~= "Deck" then return end
    local guid = obj.getGUID()
    if guid ~= nil then DrawRandom.registered[guid] = nil end
end

function DrawRandom.load()
    DrawRandom.registered = {}
    Wait.frames(DrawRandom.scan, 5)
    Wait.time(DrawRandom.scan, DrawRandom.SCAN_INTERVAL, -1)
    print("MTG Portable Helper: Draw Random module ready.")
end

