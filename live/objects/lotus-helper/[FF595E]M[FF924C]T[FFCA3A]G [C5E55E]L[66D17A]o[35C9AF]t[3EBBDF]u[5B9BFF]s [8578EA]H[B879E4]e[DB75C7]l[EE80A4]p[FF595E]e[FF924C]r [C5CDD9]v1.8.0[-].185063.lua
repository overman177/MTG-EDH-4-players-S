--[[==========================================================================
    MTG LOTUS HELPER  |  v1.9.0  |  Tabletop Simulator Object Script

    MODULES
      1. Card Preview  - Hand plays and first CommanderZone battlefield entry
      2. Playmats      - Personal artwork via "playmat <URL>" / "playmat none"
      3. Draw Random   - Draw a random card from tagged Library/GY/Exile decks
      4. EDH Settings  - Counter visibility, personal preview options, UI
      5. Equipment     - Encoder equipment with hover-only Equip/Unequip buttons
      6. Reveal Top    - Non-interactive visual clone above each library



==========================================================================]]

local HELPER_NAME = "MTG Lotus Helper"
local HELPER_VERSION = "1.9.0"

-- Patch notes are stored outside Lua in a TTS Notebook page named
-- LOTUS_PATCH_NOTES, assigned to the Black (GM) seat. The Notes API reads
-- the page for the Settings UI, where it is displayed read-only to everyone.
-- Edit the Black Notebook page, then save the TABLE (not just Save & Play).


local NAME_RAINBOW = {
    "FF595E", "FF924C", "FFCA3A", "C5E55E", "66D17A",
    "35C9AF", "3EBBDF", "5B9BFF", "8578EA", "B879E4",
    "DB75C7", "EE80A4"
}

local function makeRainbowName(name)
    local parts = {}
    local colorIndex = 1

    for i = 1, #name do
        local char = name:sub(i, i)
        if char == " " then
            parts[#parts + 1] = char
        else
            parts[#parts + 1] = "[" .. NAME_RAINBOW[colorIndex] .. "]" .. char
            colorIndex = colorIndex % #NAME_RAINBOW + 1
        end
    end

    return table.concat(parts)
end


local Settings
local RevealTop
local Combat

local Preview = {
    DISPLAY_TIME = 7,
    NEW_IMAGE_GRACE = 3, -- extra display time for remote clients
    ASSET_CACHE_LIMIT = 24,
    DROP_RETRY_FRAMES = 3,
    DROP_RETRY_ATTEMPTS = 20,
    DEBUG = false,
    dropSerialByGUID = {},
    HAND_TAG = "MTG_Preview_InHand",
    PREVIEW_TAG = "MTG_PlayedCardPreview_Controller",
    SETTINGS_TAG = "MTG_EDH_Settings_Controller",
    BATTLEFIELD_TAG = "Battlefield",
    BATTLEFIELD_COLOR_TAGS = {"Blue", "Yellow", "Red", "White"},
    ALL_UI_COLORS = {
        "White", "Brown", "Red", "Orange", "Yellow", "Green",
        "Teal", "Blue", "Purple", "Pink", "Grey", "Black"
    },
    EDH_COLORS = {"Red", "Blue", "White", "Yellow"},
    ownEnabledByColor = {},
    opponentsEnabledByColor = {},
    hideOwnLandsByColor = {},
    hideOpponentsLandsByColor = {},
    firstCommanderOwnByColor = {},
    firstCommanderOpponentsByColor = {},
    sizeByColor = {}, -- viewer-specific preview size (percent)
    commanderPending = {},     -- GUID -> CommanderZone owner color (transient)
    commanderFirstShown = {},  -- GUID -> true, saved across reloads
    currentPreviewKind = "played",  -- "played" or "commander"
    currentSourceColor = nil,  -- player who dropped the currently shown card
    visibleViewerCount = 0,
    isPreviewActive = false,
    imageReady = false,
    cardTypeCache = {},       -- card name -> true (land), false, or "unknown"
    pendingLookups = {},     -- one Scryfall request per distinct name
    currentLandStatus = nil, -- nil = not yet classified
    currentPreviewID = 0,    -- ignore late responses for old previews
    timerID = nil
}


function Preview.isBattlefieldMarker(marker)
    if marker == nil or not marker.hasTag(Preview.BATTLEFIELD_TAG) then
        return false
    end
    for _, color in ipairs(Preview.BATTLEFIELD_COLOR_TAGS) do
        if marker.hasTag(color) then
            return true
        end
    end
    return false
end


function Preview.isOnBattlefield(card)
    if card == nil then return false end
    local cardPosition = card.getPosition()

    for _, marker in ipairs(getObjectsWithTag(Preview.BATTLEFIELD_TAG)) do
        if Preview.isBattlefieldMarker(marker) then
            if marker.type == "Scripting" then
                for _, contained in ipairs(marker.getObjects(true)) do
                    if contained == card then
                        return true
                    end
                end
            else
                local localPos = marker.positionToLocal(cardPosition)
                if math.abs(localPos.x) <= 0.5
                   and math.abs(localPos.z) <= 0.5 then
                    return true
                end
            end
        end
    end
    return false
end

-- Global UI attributes are shared, so each seat needs a distinct,
-- color-restricted viewport to support independent preview scaling.
function Preview.panelID(color)
    return "MTG_CastDisplay_" .. color
end

function Preview.imageID(color)
    return "MTG_CastImage_" .. color
end

function Preview.makeDisplay(id, imageID, visibility)
    return {tag = "Panel", attributes = {
        id = id, width = "400", height = "560",
        rectAlignment = "MiddleRight", offsetXY = "-50 0",
        visibility = visibility, active = "false",
        color = "rgba(0,0,0,0.85)", outline = "White",
        outlineSize = "2 2", ignoreLayout = "true"
    }, children = {{tag = "Image", attributes = {
        id = imageID, width = "380", height = "540",
        preserveAspect = "true"
    }}}}
end

function Preview.createDisplay()
    local xml = UI.getXmlTable() or {}
    local existing = {}
    for _, node in ipairs(xml) do
        if node.attributes and node.attributes.id then
            existing[node.attributes.id] = true
        end
    end
    local changed = false
    if not existing.MTG_CastDisplay then
        table.insert(xml, Preview.makeDisplay(
            "MTG_CastDisplay", "MTG_CastImage", "Black"))
        changed = true
    end
    for _, color in ipairs(Preview.EDH_COLORS) do
        if not existing[Preview.panelID(color)] then
            table.insert(xml, Preview.makeDisplay(
                Preview.panelID(color), Preview.imageID(color), color))
            changed = true
        end
    end
    if changed then UI.setXmlTable(xml) end
end

function Preview.hideAll()
    UI.setAttribute("MTG_CastDisplay", "active", "false")
    for _, color in ipairs(Preview.EDH_COLORS) do
        UI.setAttribute(Preview.panelID(color), "active", "false")
    end
end

function Preview.setImage(assetName)
    UI.setAttribute("MTG_CastImage", "image", assetName)
    for _, color in ipairs(Preview.EDH_COLORS) do
        UI.setAttribute(Preview.imageID(color), "image", assetName)
    end
end

-- Color-specific panel IDs prevent one player's sizing from
-- changing another player's screen. The original aspect ratio is kept.
function Preview.setSize(color, percent)
    local n = tonumber(percent) or 100
    n = math.max(50, math.min(150, math.floor(n + 0.5)))
    Preview.sizeByColor[color] = n
    local factor = n / 100
    UI.setAttribute(Preview.panelID(color), "width",
        tostring(math.floor(400 * factor + 0.5)))
    UI.setAttribute(Preview.panelID(color), "height",
        tostring(math.floor(560 * factor + 0.5)))
    UI.setAttribute(Preview.imageID(color), "width",
        tostring(math.floor(380 * factor + 0.5)))
    UI.setAttribute(Preview.imageID(color), "height",
        tostring(math.floor(540 * factor + 0.5)))
end

-- Viewers see only their own viewport; spectators retain the old
-- default-size viewport. All enable/hide/commander flags remain per viewer.
function Preview.updateVisibility(isLand)
    if isLand == nil then isLand = Preview.currentLandStatus end
    local source = Preview.currentSourceColor
    local spectators = {}
    local seated = {}
    local count = 0
    for _, color in ipairs(Preview.EDH_COLORS) do seated[color] = true end
    for _, viewer in ipairs(Preview.ALL_UI_COLORS) do
        local ownCard = (source ~= nil and source == viewer)
        local allowed, hideLands
        if Preview.currentPreviewKind == "commander" then
            allowed = (ownCard and
                Preview.firstCommanderOwnByColor[viewer] ~= false)
                or (not ownCard and
                Preview.firstCommanderOpponentsByColor[viewer] ~= false)
        else
            if ownCard then
                allowed = Preview.ownEnabledByColor[viewer] ~= false
                hideLands = Preview.hideOwnLandsByColor[viewer] == true
            else
                allowed = Preview.opponentsEnabledByColor[viewer] ~= false
                hideLands = Preview.hideOpponentsLandsByColor[viewer] == true
            end
            if isLand == true and hideLands then allowed = false end
        end
        if allowed then count = count + 1 end
        if seated[viewer] then
            UI.setAttribute(Preview.panelID(viewer), "active",
                allowed and Preview.isPreviewActive and Preview.imageReady
                    and "true" or "false")
        elseif allowed then
            table.insert(spectators, viewer)
        end
    end
    Preview.visibleViewerCount = count
    UI.setAttribute("MTG_CastDisplay", "visibility",
        #spectators > 0 and table.concat(spectators, "|") or "Black")
    UI.setAttribute("MTG_CastDisplay", "active",
        #spectators > 0 and Preview.isPreviewActive and Preview.imageReady
            and "true" or "false")
end

function Preview.setPreferences(params)
    if type(params) ~= "table" then return end
    -- Accept old external API payloads as a compatibility fallback.
    local own = params.ownEnabledByColor or params.enabledByColor or params
    local opponents = params.opponentsEnabledByColor or params.enabledByColor or params
    local oldLandFilter = params.hideLandsByColor or {}
    local hideOwn = params.hideOwnLandsByColor or oldLandFilter
    local hideOpponents = params.hideOpponentsLandsByColor or oldLandFilter
    local commanderOwn = params.firstCommanderOwnByColor or {}
    local commanderOpponents = params.firstCommanderOpponentsByColor or {}
    local sizes = params.sizeByColor or {}
    if type(own) ~= "table" or type(opponents) ~= "table" then return end

    for _, color in ipairs(Preview.EDH_COLORS) do
        Preview.ownEnabledByColor[color] = own[color] ~= false
        Preview.opponentsEnabledByColor[color] = opponents[color] ~= false
        Preview.hideOwnLandsByColor[color] = hideOwn[color] == true
        Preview.hideOpponentsLandsByColor[color] = hideOpponents[color] == true
        Preview.firstCommanderOwnByColor[color] = commanderOwn[color] ~= false
        Preview.firstCommanderOpponentsByColor[color] =
            commanderOpponents[color] ~= false
        Preview.setSize(color, sizes[color] or 100)
    end
    Preview.updateVisibility()
end

-- Only trust explicit card-type information: avoid searching Oracle text
-- for the word "land" (which would misclassify cards such as Cultivate).
local function typeLineIsLand(line)
    return type(line) == "string"
        and line:lower():find("%f[%a]land%f[%A]") ~= nil
end

local function typeLineFromMetadata(data)
    if type(data) ~= "table" then return nil end
    if type(data.type_line) == "string" then
        return typeLineIsLand(data.type_line)
    end
    if type(data.typeLine) == "string" then
        return typeLineIsLand(data.typeLine)
    end
    if type(data.card) == "table" then
        local result = typeLineFromMetadata(data.card)
        if result ~= nil then return result end
    end
    if type(data.card_faces) == "table" then
        local recognized = false
        for _, face in ipairs(data.card_faces) do
            if type(face) == "table" and type(face.type_line) == "string" then
                recognized = true
                if typeLineIsLand(face.type_line) then return true end
            end
        end
        if recognized then return false end
    end
    return nil
end

-- The tabletop's imported cards store their printed name and their
-- type line together in the TTS object name, for example:
--   Plains\nBasic Land — Plains 0CMC
-- Read that type locally, before making any Scryfall request.
local CARD_TYPE_WORDS = {
    artifact = true, creature = true, enchantment = true,
    instant = true, sorcery = true, land = true,
    planeswalker = true, battle = true, kindred = true, tribal = true
}
local CARD_SUPERTYPE_WORDS = {
    basic = true, legendary = true, snow = true, world = true, ongoing = true
}

local function beforeSubtype(line)
    local pos = line:find("—", 1, true) or line:find("–", 1, true)
        or line:find("%s+%-%s+")
    return pos and line:sub(1, pos - 1) or line
end

local function classifyPrintedTypeLine(line)
    if type(line) ~= "string" then return nil end
    line = beforeSubtype(line:lower()
        :gsub("^%s*card%s+type%s*:%s*", "")
        :gsub("^%s*type%s*:%s*", ""))
        :gsub("%s*%d+%s*cmc%s*$", "")

    local hasType, land = false, false
    for word in line:gmatch("[%a]+") do
        if CARD_TYPE_WORDS[word] then
            hasType = true
            if word == "land" then land = true end
        elseif not CARD_SUPERTYPE_WORDS[word] then
            return nil
        end
    end
    if hasType then return land end
    return nil
end

-- Also support importers that put the name + type + CMC on ONE line.
-- For these only, find the recognised type words at the very end of the
-- pre-subtype text, rather than matching 'Land' anywhere in a card name.
local function classifyInlinePrintedName(line)
    if not line:lower():match("%d+%s*cmc%s*$") then return nil end
    local head = beforeSubtype(line:lower())
    head = head:gsub("%s*%d+%s*cmc%s*$", "")
    local words = {}
    for word in head:gmatch("[%a]+") do words[#words + 1] = word end
    local hasType, land = false, false
    for i = #words, 1, -1 do
        local word = words[i]
        if CARD_TYPE_WORDS[word] then
            hasType = true
            if word == "land" then land = true end
        elseif not CARD_SUPERTYPE_WORDS[word] then
            break
        end
    end
    if hasType then return land end
    return nil
end

local function typeFromObjectName(raw)
    if type(raw) ~= "string" then return nil end
    raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
    local first = true
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        if first then
            first = false   -- First line is the card name, not its type.
        else
            local result = classifyPrintedTypeLine(line)
            if result ~= nil then return result end
        end
    end
    return classifyInlinePrintedName(raw)
end

local function previewName(card)
    -- Scryfall searches use ONLY the first (printed name) line.
    local raw = tostring(card.getName() or "")
    local name = raw:match("^([^\r\n]*)") or ""
    return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function previewNameKey(name)
    return name:lower():gsub("%s+", " ")
end

-- Optional manual overrides for cards with unusual names or no metadata:
-- tag a physical card "MTG_Land" or "MTG_NonLand".
function Preview.isLand(card)
    -- The central metadata cache handles known card types; preserve the
    -- existing local/Scryfall fallbacks for portable use on other tables.
    local ok, meta = pcall(function()
        return Global.call("mtgCardMetadata", {guid = card.getGUID()})
    end)
    if ok and type(meta) == "table" and meta.isLand ~= nil then
        return meta.isLand
    end
    if card.hasTag("MTG_Land") or card.hasTag("Land") then return true end
    if card.hasTag("MTG_NonLand") then return false end

    -- Prefer the type printed in the imported object's own name. This
    -- works for lands AND nonlands, without any network delay or lookup.
    local embeddedType = typeFromObjectName(card.getName())
    if embeddedType ~= nil then return embeddedType end

    local name = previewName(card)
    local key = previewNameKey(name)
    local cached = Preview.cardTypeCache[key]
    if cached == true or cached == false then return cached end

    local basics = {
        forest = true, island = true, mountain = true,
        plains = true, swamp = true, wastes = true,
        ["snow-covered forest"] = true,
        ["snow-covered island"] = true,
        ["snow-covered mountain"] = true,
        ["snow-covered plains"] = true,
        ["snow-covered swamp"] = true
    }
    if basics[key] then
        Preview.cardTypeCache[key] = true
        return true
    end

    -- Importers may already store Scryfall type_line in GM Notes.
    local notes = card.getGMNotes()
    if type(notes) == "string" and notes:match("^%s*{") then
        local ok, data = pcall(JSON.decode, notes)
        if ok then
            local result = typeLineFromMetadata(data)
            if result ~= nil then
                Preview.cardTypeCache[key] = result
                return result
            end
        end
    end

    -- Some importers put the type in the DESCRIPTION instead of the
    -- name. Only read an explicit type line, never the ability text.
    local desc = card.getDescription()
    if type(desc) == "string" then
        local line = desc:match("^([^\r\n]+)") or ""
        local result = classifyPrintedTypeLine(line)
        if result ~= nil then
            Preview.cardTypeCache[key] = result
            return result
        end
    end

    return nil
end

local function previewUrlEncode(value)
    return (value:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

-- Lookups are optional, on demand, and deduplicated by card name.
-- Unidentified cards remain visible; only confirmed lands are hidden.
function Preview.lookupLand(card, callback)
    local name = previewName(card)
    local key = previewNameKey(name)
    if name == "" or name == "Card" or Preview.cardTypeCache[key] == "unknown" then
        return
    end
    local queued = Preview.pendingLookups[key]
    if queued ~= nil then
        table.insert(queued, callback)
        return
    end
    Preview.pendingLookups[key] = {callback}

    local url = "https://api.scryfall.com/cards/named?exact=" .. previewUrlEncode(name)
    local headers = {
        ["User-Agent"] = "MTG-Lotus-Helper/1.2.0 (TTS)",
        ["Accept"] = "application/json;q=0.9,*/*;q=0.8"
    }
    local function finish(result)
        Preview.cardTypeCache[key] = result == nil and "unknown" or result
        local callbacks = Preview.pendingLookups[key] or {}
        Preview.pendingLookups[key] = nil
        for _, notify in ipairs(callbacks) do notify(result) end
    end
    local ok = pcall(function()
        WebRequest.custom(url, "GET", true, "", headers, function(response)
            if response.is_error or response.response_code ~= 200 then
                finish(nil)
                return
            end
            local decodedOK, data = pcall(JSON.decode, response.text)
            if not decodedOK then finish(nil); return end
            finish(typeLineFromMetadata(data))
        end)
    end)
    if not ok then finish(nil) end
end

function Preview.landFilteringActive()
    local source = Preview.currentSourceColor
    for _, viewer in ipairs(Preview.EDH_COLORS) do
        local ownCard = source == viewer
        if ownCard then
            if Preview.ownEnabledByColor[viewer] ~= false
                and Preview.hideOwnLandsByColor[viewer] == true then
                return true
            end
        elseif Preview.opponentsEnabledByColor[viewer] ~= false
            and Preview.hideOpponentsLandsByColor[viewer] == true then
            return true
        end
    end
    return false
end

function Preview.loadPreferences()
    -- Settings is now part of THIS object. Avoid reading preferences
    -- from a legacy controller that may still exist during migration.
    if Settings ~= nil then
        Preview.setPreferences(Settings.getPreviewPreferences())
    end
end

-- Only a CommanderZone with exactly one of our four player-color tags
-- identifies the commander owner. Avoid matching other zones whose tags
-- happen to contain a player color.
function Preview.commanderZoneOwner(zone)
    if zone == nil or zone.type ~= "Scripting"
        or not zone.hasTag("CommanderZone") then return nil end
    local owner = nil
    for _, color in ipairs(Preview.EDH_COLORS) do
        if zone.hasTag(color) then
            if owner ~= nil then return nil end -- ambiguous owner
            owner = color
        end
    end
    return owner
end

function Preview.rememberCommanderOrigin(zone, card)
    if card == nil or card.tag ~= "Card" or card.isDestroyed() then return end
    local owner = Preview.commanderZoneOwner(zone)
    if owner == nil then return end
    local guid = card.getGUID()
    if guid ~= nil and not Preview.commanderFirstShown[guid] then
        Preview.commanderPending[guid] = owner
    end
end

function Preview.onPickUp(playerColor, card)
    if card == nil or card.tag ~= "Card" then return end
    -- Capture the zone before it may disappear from getZones() during drag.
    for _, zone in ipairs(card.getZones() or {}) do
        if zone.type == "Hand" and not card.hasTag(Preview.HAND_TAG) then
            card.addTag(Preview.HAND_TAG)
        end
        Preview.rememberCommanderOrigin(zone, card)
    end
    -- Fallback for a missed Hand-enter event if the card remains in the hand list.
    if not card.hasTag(Preview.HAND_TAG) then
        local player = Player and Player[playerColor]
        if player ~= nil then
            local ok, cards = pcall(function() return player.getHandObjects(1) end)
            if ok and type(cards) == "table" then
                for _, inHand in ipairs(cards) do
                    if inHand == card then
                        card.addTag(Preview.HAND_TAG)
                        break
                    end
                end
            end
        end
    end

    -- Tagged scripting zones can filter untagged cards out of getZones().
    -- Check their actual occupants with ignore_tags=true on pickup; this
    -- matters for commanders without the color tag of their zone.
    local guid = card.getGUID()
    if guid == nil or Preview.commanderPending[guid] ~= nil
        or Preview.commanderFirstShown[guid] then return end
    for _, zone in ipairs(getObjectsWithTag("CommanderZone") or {}) do
        if Preview.commanderZoneOwner(zone) ~= nil then
            for _, occupant in ipairs(zone.getObjects(true) or {}) do
                if occupant == card then
                    Preview.rememberCommanderOrigin(zone, card)
                    return
                end
            end
        end
    end
end

function Preview.onLeaveZone(zone, card)
    if zone ~= nil and zone.type == "Hand" and card ~= nil
        and card.tag == "Card" and not card.isDestroyed()
        and not card.hasTag(Preview.HAND_TAG) then
        card.addTag(Preview.HAND_TAG)
    end
    -- Fallback for scripted moves, or when a zone-leave event occurs before
    -- onObjectPickUp. We only act after a subsequent valid battlefield drop.
    Preview.rememberCommanderOrigin(zone, card)
end

function Preview.onEnterZone(zone, obj)
    if obj == nil or obj.tag ~= "Card" then return end
    if zone.type == "Hand" then
        if not obj.hasTag(Preview.HAND_TAG) then
            obj.addTag(Preview.HAND_TAG)
        end
        local guid = obj.getGUID()
        Preview.dropSerialByGUID[guid] = (Preview.dropSerialByGUID[guid] or 0) + 1
    end
    -- Returning to the command zone invalidates an unfinished entry check.
    if Preview.commanderZoneOwner(zone) ~= nil then
        local guid = obj.getGUID()
        Preview.commanderPending[guid] = nil
        Preview.dropSerialByGUID[guid] = (Preview.dropSerialByGUID[guid] or 0) + 1
    end
end

-- Distinct, stable names avoid rewriting the same image for every preview.
-- Preserve unrelated Global UI assets and limit our preview-only cache.
function Preview.assetForFace(faceURL)
    local assets = UI.getCustomAssets() or {}
    local maxID, count = 0, 0
    for _, asset in ipairs(assets) do
        local id = type(asset.name) == "string"
            and tonumber(asset.name:match("^MTG_CAST_PREVIEW_(%d+)$")) or nil
        if id ~= nil then
            if id > maxID then maxID = id end
            count = count + 1
            if asset.url == faceURL then return asset.name, false end
        end
    end

    -- One-time cleanup of the old mutable asset.
    for i = #assets, 1, -1 do
        if assets[i].name == "MTG_CAST_PREVIEW" then
            table.remove(assets, i)
        end
    end
    if count >= Preview.ASSET_CACHE_LIMIT then
        for i, asset in ipairs(assets) do
            if type(asset.name) == "string"
                and asset.name:match("^MTG_CAST_PREVIEW_%d+$") then
                table.remove(assets, i)
                break
            end
        end
    end
    local name = "MTG_CAST_PREVIEW_" .. tostring(maxID + 1)
    table.insert(assets, {name = name, url = faceURL})
    UI.setCustomAssets(assets)
    return name, true
end

function Preview.debugLog(message)
    if Preview.DEBUG then print("MTG Preview: " .. tostring(message)) end
end

function Preview.showCard(card, playerColor, kind)
    if card == nil or card.isDestroyed() then return end

    local custom = card.getCustomObject()
    if custom == nil or custom.face == nil or custom.face == "" then
        print("MTG Preview: card has no custom face image.")
        return
    end

    kind = kind == "commander" and "commander" or "played"
    -- Commander entry bypasses the ordinary land filter and does not need
    -- Scryfall. It is governed by its own two personal settings.
    local isLand = kind == "commander" and false or Preview.isLand(card)
    Preview.currentPreviewKind = kind
    Preview.currentPreviewID = Preview.currentPreviewID + 1
    local previewID = Preview.currentPreviewID
    Preview.currentSourceColor = playerColor
    Preview.currentLandStatus = isLand
    Preview.isPreviewActive = false
    Preview.imageReady = false
    Preview.hideAll()
    Preview.updateVisibility()

    if Preview.timerID ~= nil then
        Wait.stop(Preview.timerID)
        Preview.timerID = nil
    end

    -- Only cards without local type information need a lookup; they stay
    -- visible unless that lookup positively identifies them as lands.
    if kind == "played" and isLand == nil and Preview.landFilteringActive() then
        Preview.lookupLand(card, function(result)
            if previewID ~= Preview.currentPreviewID then return end
            Preview.currentLandStatus = result
            Preview.updateVisibility()
        end)
    end

    local assetName, isNew = Preview.assetForFace(custom.face)
    Preview.debugLog((isNew and "registered " or "reused ") .. assetName)
    local function activate()
        if previewID ~= Preview.currentPreviewID then return end
        Preview.setImage(assetName)
        UI.setAttribute("MTG_CastDisplay", "outline", playerColor)
        for _, color in ipairs(Preview.EDH_COLORS) do
            UI.setAttribute(Preview.panelID(color), "outline", playerColor)
        end
        Preview.imageReady = true
        Preview.isPreviewActive = true
        Preview.updateVisibility()

        -- UI.loading reports SERVER readiness, not each client's readiness.
        local duration = Preview.DISPLAY_TIME
            + (isNew and Preview.NEW_IMAGE_GRACE or 0)
        Preview.timerID = Wait.time(function()
            if previewID ~= Preview.currentPreviewID then return end
            Preview.isPreviewActive = false
            Preview.hideAll()
            Preview.timerID = nil
        end, duration)
    end

    if not isNew then
        activate()
    else
        Wait.condition(
            activate,
            function() return not UI.loading end,
            10,
            function()
                if previewID ~= Preview.currentPreviewID then return end
                -- Unrelated server assets must not permanently suppress previews.
                print("MTG Preview: server UI load timed out for " .. assetName)
                activate()
            end
        )
    end
end

function Preview.onDrop(playerColor, card)
    if card == nil or card.tag ~= "Card" or card.isDestroyed() then return end
    local guid = card.getGUID()
    if guid == nil then return end
    local commanderOwner = Preview.commanderPending[guid]

    for _, zone in ipairs(card.getZones() or {}) do
        if zone.type == "Hand" then
            if not card.hasTag(Preview.HAND_TAG) then
                card.addTag(Preview.HAND_TAG)
            end
            return
        end
    end

    local fromHand = card.hasTag(Preview.HAND_TAG)
    if not fromHand and commanderOwner == nil then return end

    -- Keep origin state until the card is confirmed on a battlefield.
    -- A single five-frame check could lose the preview permanently.
    local serial = (Preview.dropSerialByGUID[guid] or 0) + 1
    Preview.dropSerialByGUID[guid] = serial
    local attempts = 0
    local function checkBattlefield()
        if Preview.dropSerialByGUID[guid] ~= serial then return end
        if card.isDestroyed() or card.is_face_down then return end
        if not Preview.isOnBattlefield(card) then
            attempts = attempts + 1
            if attempts < Preview.DROP_RETRY_ATTEMPTS then
                Wait.frames(checkBattlefield, Preview.DROP_RETRY_FRAMES)
            else
                Preview.debugLog("not on battlefield: " .. guid .. " (origin retained)")
            end
            return
        end

        if fromHand and card.hasTag(Preview.HAND_TAG) then
            card.removeTag(Preview.HAND_TAG)
        end
        Preview.commanderPending[guid] = nil
        Preview.debugLog("confirmed battlefield: " .. guid)
        if commanderOwner ~= nil and not Preview.commanderFirstShown[guid] then
            Preview.commanderFirstShown[guid] = true
            Preview.showCard(card, commanderOwner, "commander")
        elseif fromHand then
            Preview.showCard(card, playerColor, "played")
        end
    end
    Wait.frames(checkBattlefield, Preview.DROP_RETRY_FRAMES)
end

function Preview.load(savedData)
    Preview.commanderPending = {}
    Preview.dropSerialByGUID = {}
    Preview.commanderFirstShown = {}
    if type(savedData) == "string" and savedData ~= "" then
        local ok, data = pcall(JSON.decode, savedData)
        if ok and type(data) == "table" and type(data.commanderFirstShown) == "table" then
            for guid, shown in pairs(data.commanderFirstShown) do
                if type(guid) == "string" and shown == true then
                    Preview.commanderFirstShown[guid] = true
                end
            end
        end
    end
    self.setName(makeRainbowName(HELPER_NAME) .. " [C5CDD9]v" .. HELPER_VERSION .. "[-]")
    self.addTag(Preview.PREVIEW_TAG)
    Preview.createDisplay()

    Wait.frames(function()
        Preview.hideAll()
        Preview.updateVisibility()
        Preview.loadPreferences()
    end, 12)

    log(HELPER_NAME .. " " .. HELPER_VERSION .. " loaded (Card Preview).")
end

-- =============================================================
-- MODULE 2/4: PLAYMATS
--
-- Chat:  playmat https://example.com/picture.png
--        playmat none
--

-- =============================================================

local Playmats = {
    CONFIG = {
        scaleX = 2.30,
        scaleY = 0.01,
        scaleZ = 2.70,
        forwardOffset = 24.50,
        sideOffset = 4.5,
        height = 0.96,
        rotationY = 0,
        locked = true,
        interactable = false,
        meshURL = "https://steamusercontent-a.akamaihd.net/ugc/1661229755220411391/27AA7C44FB7D2F2E20F96618E6CD9671C5EE8341/"
    },
    ART_TAG = "MTG_Portable_ArtPlaymat",
    guids = {},            -- player color -> spawned playmat GUID
    generations = {},      -- cancel overlapping replacement requests
    PLAYER_COLORS = {"White", "Red", "Yellow", "Blue"}
}


-- Battlefield scripting zones, rather than player hands, define the exact
-- position, rotation and footprint of each artwork playmat.
function Playmats.getBattlefieldZone(color)
    local matches = {}
    for _, zone in ipairs(getObjectsWithTag("Battlefield") or {}) do
        if zone.type == "Scripting" and zone.hasTag(color) then
            matches[#matches + 1] = zone
        end
    end
    -- Ambiguous zones must never cause a mat to land on the wrong board.
    if #matches ~= 1 then return nil end
    return matches[1]
end

function Playmats.fitToBattlefield(mat, color)
    local zone = Playmats.getBattlefieldZone(color)
    if zone == nil or mat == nil or mat.isDestroyed() then return false end

    local zoneScale = zone.getScale()
    local bounds = mat.getBoundsNormalized()
    if bounds == nil or bounds.size == nil
        or bounds.size.x <= 0.001 or bounds.size.z <= 0.001 then
        return false
    end

    local current = mat.getScale()
    mat.setScale({
        x = current.x * zoneScale.x / bounds.size.x,
        y = current.y,
        z = current.z * zoneScale.z / bounds.size.z
    })

    -- Scripting zones are volumes: use their x/z center, not their y center.
    -- Keep the artwork on the tabletop, below cards and counters.
    local position = zone.getPosition()
    mat.setPosition({position.x, Playmats.CONFIG.height, position.z})
    local rot = zone.getRotation()
    mat.setRotation({0, rot.y + Playmats.CONFIG.rotationY, 0})
    mat.setLock(Playmats.CONFIG.locked)
    mat.interactable = Playmats.CONFIG.interactable
    return true
end

function Playmats.alignExisting()
    for _, color in ipairs(Playmats.PLAYER_COLORS) do
        local mat = Playmats.getOwnedMat(color)
        if mat ~= nil then
            pcall(function() Playmats.fitToBattlefield(mat, color) end)
        end
    end
end


function Playmats.load(savedData)
    Playmats.guids = {}
    Playmats.generations = {}

    if type(savedData) ~= "string" or savedData == "" then
        return
    end

    local ok, decoded = pcall(JSON.decode, savedData)
    if not ok or type(decoded) ~= "table" then
        return
    end

    local savedGuids = decoded.playmats or decoded
    if type(savedGuids) ~= "table" then
        return
    end

    for color, guid in pairs(savedGuids) do
        if type(color) == "string" and type(guid) == "string" then
            Playmats.guids[color] = guid
        end
    end
end

function Playmats.save()
    return JSON.encode({
        version = HELPER_VERSION,
        playmats = Playmats.guids,
        settings = Settings and Settings.export() or nil,
        commanderFirstShown = Preview.commanderFirstShown,
        revealTopEnabled = RevealTop and RevealTop.enabled or {}
    })
end


function Playmats.persist()
    self.script_state = Playmats.save()
end

function Playmats.getOwnedMat(color)
    local guid = Playmats.guids[color]
    if type(guid) ~= "string" then return nil end
    local obj = getObjectFromGUID(guid)
    if obj == nil then return nil end

    if obj.hasTag(Playmats.ART_TAG) or obj.getName() == "Art Playmat" then
        return obj
    end
    -- A stale GUID should never delete a non-playmat object.
    return nil
end

function Playmats.remove(color)
    -- Invalidate any spawn callback from an earlier playmat command.
    Playmats.generations[color] = (Playmats.generations[color] or 0) + 1

    local existing = Playmats.getOwnedMat(color)
    Playmats.guids[color] = nil
    Playmats.persist()

    if existing ~= nil then
        existing.destruct()
    end
end

function Playmats.makeJSON(imageURL)
    local c = Playmats.CONFIG
    -- JSON.encode escapes unusual characters in URLs correctly.
    return JSON.encode({
        Name = "Custom_Model",
        Transform = {
            posX = 0, posY = 0, posZ = 0,
            rotX = 0, rotY = 0, rotZ = 0,
            scaleX = c.scaleX,
            scaleY = c.scaleY,
            scaleZ = c.scaleZ
        },
        Nickname = "Art Playmat",
        ColorDiffuse = {r = 1, g = 1, b = 1},
        Locked = c.locked,
        CustomMesh = {
            MeshURL = c.meshURL,
            DiffuseURL = imageURL,
            MaterialIndex = 3,
            TypeIndex = 4,
            CustomShader = {
                SpecularColor = {r = 1, g = 1, b = 1},
                SpecularIntensity = 0,
                SpecularSharpness = 2,
                FresnelStrength = 0
            }
        }
    })
end

function Playmats.create(color, imageURL)
    local player = Player[color]
    if player == nil then return end

    local zone = Playmats.getBattlefieldZone(color)
    if zone == nil then
        player.broadcast("[FF0000]Playmat: exactly one Battlefield zone tagged "
            .. color .. " is required.")
        return
    end

    local c = Playmats.CONFIG
    local center = zone.getPosition()
    local matPos = {center.x, c.height, center.z}
    local zoneRot = zone.getRotation()
    local matRot = {0, zoneRot.y + c.rotationY, 0}
    local json = Playmats.makeJSON(imageURL)

    -- Don't delete the current mat until a replacement was spawned.
    Playmats.generations[color] = (Playmats.generations[color] or 0) + 1
    local generation = Playmats.generations[color]

    local okSpawn, err = pcall(function()
        spawnObjectJSON({
            json = json,
            position = matPos,
            rotation = matRot,
            callback_function = function(obj)
                if obj == nil then return end
                if Playmats.generations[color] ~= generation then
                    obj.destruct() -- superseded by a newer command
                    return
                end

                local old = Playmats.getOwnedMat(color)
                -- Make the new mat safe to delete / find by this module.
                obj.setName("Art Playmat")
                obj.addTag(Playmats.ART_TAG)
                obj.interactable = c.interactable
                obj.setLock(c.locked)

                -- Wait for TTS to instantiate the custom mesh before measuring
                -- its actual world-size. Bounds, not scale, determine the fit.
                Wait.frames(function()
                    if obj == nil or obj.isDestroyed()
                        or Playmats.generations[color] ~= generation then return end
                    local ok, fitted = pcall(function()
                        return Playmats.fitToBattlefield(obj, color)
                    end)
                    if not ok or not fitted then
                        player.broadcast("[FF0000]Playmat: unable to measure artwork mesh.")
                    end
                end, 15)

                -- Save the new GUID BEFORE destroying the old mat.
                Playmats.guids[color] = obj.getGUID()
                Playmats.persist()
                if old ~= nil and old ~= obj then
                    old.destruct()
                end
            end
        })
    end)

    if not okSpawn then
        player.broadcast("[FF0000]Playmat spawn failed: " .. tostring(err))
        return
    end
    player.broadcast(
        "[FFFFFF]Setting playmat image:\n[3366CC]" .. imageURL ..
        "\n[999999]Type [i]playmat none[/i] to remove it."
    )
end

function Playmats.onChat(message, player)
    if type(message) ~= "string" or player == nil then return end
    local imageURL = message:match("^[Pp]laymat%s+(.+)$")
    if imageURL == nil then return end

    -- Trim only leading/trailing whitespace; no recursive non-greedy Lua pattern.
    imageURL = imageURL:gsub("^%s+", ""):gsub("%s+$", "")
    local color = player.color

    if imageURL:lower() == "none" then
        Playmats.remove(color)
        player.broadcast("[999999]Art playmat removed.")
    elseif imageURL ~= "" then
        Playmats.create(color, imageURL)
    end

    -- Hide commands from ordinary game chat.
    return false
end

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

function DrawRandom.load()
    DrawRandom.registered = {}
    DrawRandom.candidates = {}
    DrawRandom.scanNumber = 0
    Wait.frames(DrawRandom.scan, 5)
    Wait.time(DrawRandom.scan, DrawRandom.SCAN_INTERVAL, -1)
    log("MTG Portable Helper: Draw Random module ready.")
end

-- =============================================================
-- MODULE 4/4: EDH SETTINGS
-- =============================================================

Settings = {
    TAG = "MTG_EDH_Settings_Controller",
    OLD_CONTROLLER_GUID = "777766",  -- migration only (can be removed later)
    OWNERS = {"Red", "Blue", "White", "Yellow"},
    TYPES = {"energy", "poison", "experience", "rad", "mana"},
    TAGS = {
        energy = "Counter_Energy",
        poison = "Counter_Poison",
        experience = "Counter_Experience",
        rad = "Counter_Rad",
        mana = "Counter_Mana"
    },
    state = {},
    previewOwnEnabled = {},
    previewOpponentsEnabled = {},
    previewHideOwnLands = {},
    previewHideOpponentsLands = {},
    previewFirstCommanderOwn = {},
    previewFirstCommanderOpponents = {},
    previewSizeByColor = {}, -- per-seat scale percentage
    showShortcutsByColor = {}, -- personal HUD visibility, keyed by TTS seat color
    combatEnabledByColor = {}, -- per-seat combat targeting preference
    combatUndoHoldSecondsByColor = {}, -- per-seat long-press threshold, 1-10 seconds
    menuOpen = false,
    menuOwner = nil,
    uiSyncing = false,
    hasSavedState = false,
    lastApplied = {},
    activeTab = "notes",
    notesPages = {},
    notesIndex = 1,
    notesRaw = nil
}

-- Clamp saved/client values to whole seconds. Invalid/old saves default to 5.
function Settings.normalizeUndoHold(value)
    local n = tonumber(value)
    if not n or n ~= n then return 5 end
    return math.max(1, math.min(10, math.floor(n + 0.5)))
end

function Settings.getUndoHold(color)
    if type(Settings.combatUndoHoldSecondsByColor) ~= "table" then return 5 end
    return Settings.normalizeUndoHold(Settings.combatUndoHoldSecondsByColor[color])
end

function Settings.normalizePreviewSize(value)
    local n = tonumber(value)
    if not n or n ~= n then return 100 end
    return math.max(50, math.min(150, math.floor(n / 5 + 0.5) * 5))
end

function Settings.getPreviewSize(color)
    return Settings.normalizePreviewSize(Settings.previewSizeByColor[color])
end

function Settings.normalize()
    for _, kind in ipairs(Settings.TYPES) do
        if type(Settings.state[kind]) ~= "table" then
            Settings.state[kind] = {}
        end
        local state = Settings.state[kind]
        if type(state.owners) ~= "table" then
            state.owners = type(state.ownerVisible) == "table" and state.ownerVisible or {}
        end
        -- Legacy saves used "everyone" as a hard global gate. If that gate
        -- was off, every counter of this type was effectively invisible,
        -- even if all of the individual owner flags were still checked.
        -- Migrate that state once, then store only per-owner visibility.
        if state.everyone == false then
            for _, color in ipairs(Settings.OWNERS) do
                state.owners[color] = false
            end
        end
        state.everyone = nil
        for _, color in ipairs(Settings.OWNERS) do
            if state.owners[color] == nil then state.owners[color] = true end
        end
    end
    for _, color in ipairs(Settings.OWNERS) do
        if Settings.previewOwnEnabled[color] == nil then
            Settings.previewOwnEnabled[color] = true
        end
        if Settings.previewOpponentsEnabled[color] == nil then
            Settings.previewOpponentsEnabled[color] = true
        end
        if Settings.previewHideOwnLands[color] == nil then
            Settings.previewHideOwnLands[color] = false
        end
        if Settings.previewHideOpponentsLands[color] == nil then
            Settings.previewHideOpponentsLands[color] = false
        end
        if Settings.previewFirstCommanderOwn[color] == nil then
            Settings.previewFirstCommanderOwn[color] = true
        end
        if Settings.previewFirstCommanderOpponents[color] == nil then
            Settings.previewFirstCommanderOpponents[color] = true
        end
        Settings.previewSizeByColor[color] =
            Settings.normalizePreviewSize(Settings.previewSizeByColor[color])
        if Settings.showShortcutsByColor[color] == nil then
            Settings.showShortcutsByColor[color] = true
        end
        if Settings.combatEnabledByColor[color] == nil then
            Settings.combatEnabledByColor[color] = true
        end
        Settings.combatUndoHoldSecondsByColor[color] =
            Settings.normalizeUndoHold(Settings.combatUndoHoldSecondsByColor[color])
    end
end

-- Older saves used "MY VIEW / MY CARDS". Only the MY VIEW flags have a
-- meaningful replacement: they apply equally to both new viewer categories.
-- The old MY CARDS publishing restriction is intentionally not migrated,
-- because the new settings cannot control other players' screens.
local function copyPreviewColors(saved)
    local result = {}
    for _, color in ipairs(Settings.OWNERS) do result[color] = saved[color] end
    return result
end

function Settings.import(data)
    if type(data) ~= "table" then return false end
    if type(data.state) ~= "table"
        and type(data.previewOwnEnabled) ~= "table"
        and type(data.previewOpponentsEnabled) ~= "table"
        and type(data.previewHideOwnLands) ~= "table"
        and type(data.previewHideOpponentsLands) ~= "table"
        and type(data.previewFirstCommanderOwn) ~= "table"
        and type(data.previewFirstCommanderOpponents) ~= "table"
        and type(data.previewSizeByColor) ~= "table"
        and type(data.previewEnabled) ~= "table"
        and type(data.previewHideLands) ~= "table"
        and type(data.previewShareEnabled) ~= "table"
        and type(data.previewHideOwnLandsForOthers) ~= "table"
        and type(data.showShortcutsByColor) ~= "table"
        and type(data.combatEnabledByColor) ~= "table"
        and type(data.combatUndoHoldSecondsByColor) ~= "table" then
        return false
    end
    if type(data.state) == "table" then Settings.state = data.state end
    if type(data.previewOwnEnabled) == "table" then
        Settings.previewOwnEnabled = data.previewOwnEnabled
    elseif type(data.previewEnabled) == "table" then
        Settings.previewOwnEnabled = copyPreviewColors(data.previewEnabled)
    end
    if type(data.previewOpponentsEnabled) == "table" then
        Settings.previewOpponentsEnabled = data.previewOpponentsEnabled
    elseif type(data.previewEnabled) == "table" then
        Settings.previewOpponentsEnabled = copyPreviewColors(data.previewEnabled)
    end
    if type(data.previewHideOwnLands) == "table" then
        Settings.previewHideOwnLands = data.previewHideOwnLands
    elseif type(data.previewHideLands) == "table" then
        Settings.previewHideOwnLands = copyPreviewColors(data.previewHideLands)
    end
    if type(data.previewHideOpponentsLands) == "table" then
        Settings.previewHideOpponentsLands = data.previewHideOpponentsLands
    elseif type(data.previewHideLands) == "table" then
        Settings.previewHideOpponentsLands = copyPreviewColors(data.previewHideLands)
    end
    if type(data.previewFirstCommanderOwn) == "table" then
        Settings.previewFirstCommanderOwn = data.previewFirstCommanderOwn
    end
    if type(data.previewFirstCommanderOpponents) == "table" then
        Settings.previewFirstCommanderOpponents = data.previewFirstCommanderOpponents
    end
    if type(data.previewSizeByColor) == "table" then
        Settings.previewSizeByColor = data.previewSizeByColor
    end
    if type(data.showShortcutsByColor) == "table" then
        Settings.showShortcutsByColor = data.showShortcutsByColor
    end
    if type(data.combatEnabledByColor) == "table" then
        Settings.combatEnabledByColor = data.combatEnabledByColor
    end
    if type(data.combatUndoHoldSecondsByColor) == "table" then
        Settings.combatUndoHoldSecondsByColor = data.combatUndoHoldSecondsByColor
    end
    Settings.hasSavedState = true
    Settings.normalize()
    return true
end

function Settings.load(savedData)
    Settings.state = {}
    Settings.previewOwnEnabled = {}
    Settings.previewOpponentsEnabled = {}
    Settings.previewHideOwnLands = {}
    Settings.previewHideOpponentsLands = {}
    Settings.previewFirstCommanderOwn = {}
    Settings.previewFirstCommanderOpponents = {}
    Settings.previewSizeByColor = {}
    Settings.showShortcutsByColor = {}
    Settings.combatEnabledByColor = {}
    Settings.combatUndoHoldSecondsByColor = {}
    Settings.menuOpen = false
    Settings.menuOwner = nil
    Settings.uiSyncing = false
    Settings.lastApplied = {}
    Settings.activeTab = "general"
    Settings.notesPages = {}
    Settings.notesIndex = 1
    Settings.notesRaw = nil
    Settings.hasSavedState = false

    if type(savedData) == "string" and savedData ~= "" then
        local ok, data = pcall(JSON.decode, savedData)
        if ok and type(data) == "table" then
            -- Integrated v0.4 save; also allow direct old controller JSON.
            Settings.import(data.settings or data)
        end
    end

    -- One-time copy from the old Settings Controller, if still on the table.
    -- After successful migration remove its script/object to avoid duplicate menus.
    if not Settings.hasSavedState then
        local old = getObjectFromGUID(Settings.OLD_CONTROLLER_GUID)
        if old ~= nil and old ~= self then
            local ok, stored = pcall(function() return old.script_state end)
            if ok and type(stored) == "string" and stored ~= "" then
                local decodedOK, decoded = pcall(JSON.decode, stored)
                if decodedOK and Settings.import(decoded) then
                    log("MTG Helper: previous EDH settings imported from old controller.")
                end
            end
        end
    end
    Settings.normalize()
    self.addTag(Settings.TAG)
    if Settings.hasSavedState then Playmats.persist() end
end

function Settings.export()
    return {
        state = Settings.state,
        previewOwnEnabled = Settings.previewOwnEnabled,
        previewOpponentsEnabled = Settings.previewOpponentsEnabled,
        previewHideOwnLands = Settings.previewHideOwnLands,
        previewHideOpponentsLands = Settings.previewHideOpponentsLands,
        previewFirstCommanderOwn = Settings.previewFirstCommanderOwn,
        previewFirstCommanderOpponents = Settings.previewFirstCommanderOpponents,
        previewSizeByColor = Settings.previewSizeByColor,
        showShortcutsByColor = Settings.showShortcutsByColor,
        combatEnabledByColor = Settings.combatEnabledByColor,
        combatUndoHoldSecondsByColor = Settings.combatUndoHoldSecondsByColor
    }
end

function Settings.persist()
    Playmats.persist()  -- saves playmats AND settings together
end

function Settings.getPreviewPreferences()
    local own, opponents, hideOwn, hideOpponents = {}, {}, {}, {}
    local commanderOwn, commanderOpponents = {}, {}
    local sizeByColor = {}
    for _, color in ipairs(Settings.OWNERS) do
        own[color] = Settings.previewOwnEnabled[color] ~= false
        opponents[color] = Settings.previewOpponentsEnabled[color] ~= false
        hideOwn[color] = Settings.previewHideOwnLands[color] == true
        hideOpponents[color] = Settings.previewHideOpponentsLands[color] == true
        commanderOwn[color] = Settings.previewFirstCommanderOwn[color] ~= false
        commanderOpponents[color] =
            Settings.previewFirstCommanderOpponents[color] ~= false
        sizeByColor[color] = Settings.getPreviewSize(color)
    end
    return {
        ownEnabledByColor = own,
        opponentsEnabledByColor = opponents,
        hideOwnLandsByColor = hideOwn,
        hideOpponentsLandsByColor = hideOpponents,
        firstCommanderOwnByColor = commanderOwn,
        firstCommanderOpponentsByColor = commanderOpponents,
        sizeByColor = sizeByColor
    }
end

function Settings.applyPreview()
    -- Both modules live in the same object: no cross-object call required.
    Preview.setPreferences(Settings.getPreviewPreferences())
end

function Settings.getOwner(obj)
    for _, color in ipairs(Settings.OWNERS) do
        if obj.hasTag(color) then return color end
    end
    return nil
end

-- EVERYONE is a bulk action and an aggregate indicator, not a master gate.
-- When the last player's ME flag is enabled, EVERYONE automatically checks.
function Settings.allOwnersVisible(kind)
    local state = Settings.state[kind]
    if not state or type(state.owners) ~= "table" then return false end
    for _, color in ipairs(Settings.OWNERS) do
        if state.owners[color] == false then return false end
    end
    return true
end

function Settings.visibility(kind, obj)
    local state = Settings.state[kind]
    if not state then return true end
    local owner = Settings.getOwner(obj)
    -- Unknown-owner counters cannot be selectively assigned to one seat.
    -- Keep them hidden unless all seats have this counter type enabled.
    if owner == nil then return Settings.allOwnersVisible(kind) end
    return state.owners[owner] ~= false
end

function Settings.applyType(kind, force)
    local tag = Settings.TAGS[kind]
    if tag == nil then return end
    for _, obj in ipairs(getObjectsWithTag(tag) or {}) do
        local guid = obj.getGUID()
        local visible = Settings.visibility(kind, obj)
        local key = kind .. ":" .. tostring(visible)
        if force or guid == nil or Settings.lastApplied[guid] ~= key then
            -- Identical semantics to original EDH Settings Controller:
            -- invisible to the four EDH seats when disabled.
            obj.setInvisibleTo(visible and {} or Settings.OWNERS)
            if guid ~= nil then Settings.lastApplied[guid] = key end
        end
    end
end

function Settings.applyAll(force)
    for _, kind in ipairs(Settings.TYPES) do
        Settings.applyType(kind, force)
    end
end

function Settings.playerColor(player)
    if type(player) == "string" then return player end
    return player and player.color or nil
end

function Settings.validColor(color)
    for _, c in ipairs(Settings.OWNERS) do
        if c == color then return true end
    end
    return false
end

function Settings.toBool(value)
    if type(value) == "boolean" then return value end
    return tostring(value):lower() == "true"
end

function Settings.setToggle(id, value)
    UI.setAttribute(id, "isOn", value and "true" or "false")
end

function Settings.syncUI()
    if not Settings.menuOwner then return end
    Settings.uiSyncing = true
    local color = Settings.menuOwner
    local allMe = true
    local allEveryone = true

    for _, kind in ipairs(Settings.TYPES) do
        local mine = Settings.state[kind].owners[color] ~= false
        local everyone = Settings.allOwnersVisible(kind)
        Settings.setToggle("counter_" .. kind .. "_me", mine)
        Settings.setToggle("counter_" .. kind .. "_everyone", everyone)
        if not mine then allMe = false end
        if not everyone then allEveryone = false end
    end

    Settings.setToggle("counter_all_me", allMe)
    Settings.setToggle("counter_all_everyone", allEveryone)
    Settings.setToggle("preview_cards_mine", Settings.previewOwnEnabled[color] ~= false)
    Settings.setToggle("preview_cards_opponents", Settings.previewOpponentsEnabled[color] ~= false)
    Settings.setToggle("preview_hide_lands_mine", Settings.previewHideOwnLands[color] == true)
    Settings.setToggle("preview_hide_lands_opponents",
        Settings.previewHideOpponentsLands[color] == true)
    Settings.setToggle("preview_first_commander_mine",
        Settings.previewFirstCommanderOwn[color] ~= false)
    Settings.setToggle("preview_first_commander_opponents",
        Settings.previewFirstCommanderOpponents[color] ~= false)
    local scale = Settings.getPreviewSize(color)
    UI.setAttribute("lotus_preview_size_slider", "value", tostring(scale))
    UI.setAttribute("lotus_preview_size_value", "text", tostring(scale) .. "%")
    Settings.setToggle("lotus_show_shortcuts",
        Settings.showShortcutsByColor[color] ~= false)
    Settings.setToggle("lotus_enable_combat",
        Settings.combatEnabledByColor[color] ~= false)
    local hold = Settings.getUndoHold(color)
    UI.setAttribute("lotus_combat_hold_slider", "value", tostring(hold))
    UI.setAttribute("lotus_combat_hold_value", "text", tostring(hold) .. " s")
    Settings.uiSyncing = false
end

-- The settings window is visible only to its current menu owner.
-- Tab selection therefore remains local to whoever opened this menu.
Settings.TAB_IDS = {
    general = { panel = "MTG_Settings_Tab_General", button = "MTG_Settings_Button_General" },
    notes = { panel = "MTG_Settings_Tab_Notes", button = "MTG_Settings_Button_Notes" },
    counters = { panel = "MTG_Settings_Tab_Counters", button = "MTG_Settings_Button_Counters" },
    preview = { panel = "MTG_Settings_Tab_Preview", button = "MTG_Settings_Button_Preview" }
}

function Settings.applyTab()
    local height = "465"
    if Settings.activeTab == "notes" then height = "605"
    elseif Settings.activeTab == "general" then height = "465"
    elseif Settings.activeTab == "preview" then height = "465"
    end
    UI.setAttribute("CounterVisibilityPanel", "height", height)
    for tab, ids in pairs(Settings.TAB_IDS) do
        local selected = Settings.activeTab == tab
        UI.setAttribute(ids.panel, "active", selected and "true" or "false")
        UI.setAttribute(ids.button, "colors", selected
            and "#315A87|#4274AC|#234363|#234363"
            or "#29292E|#3D3D45|#222229|#222229")
        UI.setAttribute(ids.button, "textColor", selected and "#FFFFFF" or "#C9D1DF")
    end
end

function Settings.selectTab(player, value, id)
    if Settings.playerColor(player) ~= Settings.menuOwner then return end
    local tab = ({
        MTG_Settings_Button_General = "general",
        MTG_Settings_Button_Notes = "notes",
        MTG_Settings_Button_Counters = "counters",
        MTG_Settings_Button_Preview = "preview"
    })[id]
    if tab == nil then return end
    Settings.activeTab = tab
    Settings.applyTab()
    if tab == "notes" then Settings.syncPatchNotes() end
end

-- NOTEBOOK STORAGE -------------------------------------------------------
-- Private Black notebook page = editable source for the table creator.
-- Lotus reads it when Patch Notes opens; the settings text is never editable.
Settings.NOTEBOOK_TITLE = "LOTUS_PATCH_NOTES"
Settings.NOTEBOOK_COLOR = "Black"

function Settings.getNotebookTab()
    -- Returns (matching tab or nil, notebook API available).
    -- Compare title and color so a public page with the same name cannot
    -- silently replace the private source. Tab indices may change; use name.
    local ok, tabs = pcall(function() return Notes.getNotebookTabs() end)
    if not ok or type(tabs) ~= "table" then
        return nil, false
    end
    for _, tab in ipairs(tabs) do
        if tab.title == Settings.NOTEBOOK_TITLE
            and tab.color == Settings.NOTEBOOK_COLOR then
            return tab, true
        end
    end
    return nil, true
end

function Settings.ensureNotebookTab()
    local tab, available = Settings.getNotebookTab()
    if not available then
        print("MTG Helper: could not access the TTS Notebook API.")
        return
    end
    if tab ~= nil then return end  -- never replace the creator's notes

    -- Create the private page only once, when it doesn't already exist.
    -- Blank by design: the creator provides the release notes in Notebook.
    local ok, index = pcall(function()
        return Notes.addNotebookTab({
            title = Settings.NOTEBOOK_TITLE,
            body = "",
            color = Settings.NOTEBOOK_COLOR
        })
    end)
    if not ok or index == -1 then
        print("MTG Helper: failed to create LOTUS_PATCH_NOTES Notebook page.")
    else
        log("MTG Helper: created private Black Notebook page LOTUS_PATCH_NOTES.")
    end
end

-- Read release headings from the creator's private Notebook, keeping the
-- Notebook text as the single source of truth. One release at a time avoids
-- TTS scroll view clipping and inconsistent mouse-wheel handling.
local function notesTrim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One release is one page. Do not wrap at character counts or split at
-- arbitrary line counts: Unity Text performs natural wrapping based on the
-- actual panel width, and the larger panel can shrink the font as needed.
function Settings.parsePatchNotes(raw)
    raw = tostring(raw or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local sections, current = {}, nil
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        local cleaned = notesTrim(line)
        if cleaned:match("^[Vv]ersion%s+[%d%.]+") then
            if current ~= nil then table.insert(sections, current) end
            current = { title = cleaned, lines = {} }
        elseif cleaned ~= "" then
            -- Blank Notebook spacer lines are visual separators only; they
            -- must not create empty rows inside the compact release reader.
            -- Preserve the full original words and let TTS wrap at the edge.
            if current == nil then
                current = { title = "Patch Notes", lines = {} }
            end
            table.insert(current.lines, cleaned)
        end
    end
    if current ~= nil then table.insert(sections, current) end
    if #sections == 0 then
        sections = {{ title = "Patch Notes", lines = {"No patch notes published yet."} }}
    end
    -- Avoid a useless empty intro when the Notebook starts with a heading.
    if #sections > 1 and sections[1].title == "Patch Notes"
        and #sections[1].lines == 0 then
        table.remove(sections, 1)
    end

    local pages = {}
    for _, section in ipairs(sections) do
        if #section.lines == 0 then section.lines = {"No changes listed."} end
        table.insert(pages, {
            title = section.title,
            body = table.concat(section.lines, "\n")
        })
    end
    return pages
end

function Settings.displayPatchNotes()
    local pages = Settings.notesPages
    if #pages == 0 then
        pages = {{ title = "Patch Notes", body = "No patch notes published yet." }}
    end
    Settings.notesIndex = math.max(1, math.min(Settings.notesIndex, #pages))
    local page = pages[Settings.notesIndex]
    UI.setAttribute("MTG_Settings_PatchNotesVersion", "text", page.title)
    UI.setAttribute("MTG_Settings_PatchNotesText", "text", page.body)
    UI.setAttribute("MTG_Settings_PatchNotesPosition", "text",
        tostring(Settings.notesIndex) .. " / " .. tostring(#pages))
    UI.setAttribute("MTG_Settings_PatchNotesNewer", "interactable",
        Settings.notesIndex > 1 and "true" or "false")
    UI.setAttribute("MTG_Settings_PatchNotesOlder", "interactable",
        Settings.notesIndex < #pages and "true" or "false")
    UI.setAttribute("MTG_Settings_PatchNotesHint", "text", Settings.PATCH_NOTES_HINT)
end

function Settings.syncPatchNotes(resetToLatest)
    -- Re-read the Notebook whenever the menu or tab opens. Do not mutate it.
    local tab, available = Settings.getNotebookTab()
    local notes
    if not available then
        notes = "Patch notes are unavailable: TTS Notebook could not be read."
    elseif tab == nil or type(tab.body) ~= "string" or notesTrim(tab.body) == "" then
        notes = "No patch notes published yet."
    else
        notes = tab.body
    end
    if Settings.notesRaw ~= notes then
        Settings.notesRaw = notes
        Settings.notesPages = Settings.parsePatchNotes(notes)
        Settings.notesIndex = 1
    elseif resetToLatest then
        Settings.notesIndex = 1
    end
    Settings.displayPatchNotes()
end

function Settings.navigateNotes(player, value, id)
    if Settings.playerColor(player) ~= Settings.menuOwner
        or Settings.activeTab ~= "notes" then return end
    if id == "MTG_Settings_PatchNotesNewer" then
        Settings.notesIndex = Settings.notesIndex - 1
    elseif id == "MTG_Settings_PatchNotesOlder" then
        Settings.notesIndex = Settings.notesIndex + 1
    else
        return
    end
    Settings.displayPatchNotes()
end

-- UI callbacks are global functions below, forwarded to these methods.
function Settings.open(obj, color)
    if Settings.menuOpen or not Settings.validColor(color) then return end
    Settings.menuOpen = true
    Settings.menuOwner = color
    UI.setAttribute("CounterVisibilityPanel", "visibility", color)
    UI.setAttribute("CounterVisibilityPanel", "active", "true")
    Settings.syncUI()
    Settings.activeTab = "general"
    Settings.applyTab()
    Settings.syncPatchNotes(true)
end

function Settings.close(player)
    local color = Settings.playerColor(player)
    if color ~= Settings.menuOwner then return end
    UI.setAttribute("CounterVisibilityPanel", "active", "false")
    Settings.menuOpen = false
    Settings.menuOwner = nil
end

function Settings.toggle(player, value, id)
    if Settings.uiSyncing then return end
    local color = Settings.playerColor(player)
    if color == nil or color ~= Settings.menuOwner or type(id) ~= "string" then return end
    local kind, column = id:match("^counter_(%w+)_(%w+)$")
    if not kind or not Settings.state[kind] then return end
    local checked = Settings.toBool(value)
    if column == "me" then
        Settings.state[kind].owners[color] = checked
    elseif column == "everyone" then
        for _, owner in ipairs(Settings.OWNERS) do
            Settings.state[kind].owners[owner] = checked
        end
    else
        return
    end
    Settings.applyType(kind, true)
    Settings.persist()
    Settings.syncUI()
end

function Settings.toggleAllMe(player, value)
    if Settings.uiSyncing then return end
    local color = Settings.playerColor(player)
    if color == nil or color ~= Settings.menuOwner then return end
    local checked = Settings.toBool(value)
    for _, kind in ipairs(Settings.TYPES) do
        Settings.state[kind].owners[color] = checked
        Settings.applyType(kind, true)
    end
    Settings.persist()
    Settings.syncUI()
end

function Settings.toggleAllEveryone(player, value)
    if Settings.uiSyncing then return end
    if Settings.playerColor(player) ~= Settings.menuOwner then return end
    local checked = Settings.toBool(value)
    for _, kind in ipairs(Settings.TYPES) do
        for _, owner in ipairs(Settings.OWNERS) do
            Settings.state[kind].owners[owner] = checked
        end
        Settings.applyType(kind, true)
    end
    Settings.persist()
    Settings.syncUI()
end

function Settings.togglePreview(player, value, id)
    if Settings.uiSyncing then return end
    local color = Settings.playerColor(player)
    if color == nil or color ~= Settings.menuOwner then return end
    local checked = Settings.toBool(value)
    if id == "preview_cards_mine" then
        Settings.previewOwnEnabled[color] = checked
    elseif id == "preview_cards_opponents" then
        Settings.previewOpponentsEnabled[color] = checked
    elseif id == "preview_hide_lands_mine" then
        Settings.previewHideOwnLands[color] = checked
    elseif id == "preview_hide_lands_opponents" then
        Settings.previewHideOpponentsLands[color] = checked
    elseif id == "preview_first_commander_mine" then
        Settings.previewFirstCommanderOwn[color] = checked
    elseif id == "preview_first_commander_opponents" then
        Settings.previewFirstCommanderOpponents[color] = checked
    else
        return
    end
    Settings.applyPreview()
    Settings.persist()
    Settings.syncUI()
end

-- Scale is a viewer preference, not a publisher preference. The callback
-- validates the current menu owner before touching any seat-specific panel.
function Settings.changePreviewSize(player, value, id)
    if Settings.uiSyncing or id ~= "lotus_preview_size_slider" then return end
    local color = Settings.playerColor(player)
    if not Settings.validColor(color) or color ~= Settings.menuOwner then return end
    local scale = Settings.normalizePreviewSize(value)
    UI.setAttribute("lotus_preview_size_value", "text", tostring(scale) .. "%")
    if Settings.getPreviewSize(color) == scale then return end
    Settings.previewSizeByColor[color] = scale
    Preview.setSize(color, scale)
    Settings.persist()
end

-- HUD visibility is a VIEWER preference. One player's switch never changes
-- any other player's overlay; global keyboard bindings remain in Global.lua.
Settings.HUD_VIEWERS = {
    "White", "Brown", "Red", "Orange", "Yellow", "Green",
    "Teal", "Blue", "Purple", "Pink", "Grey", "Black"
}

function Settings.applyShortcutsVisibility()
    local viewers = {}
    for _, color in ipairs(Settings.HUD_VIEWERS) do
        if Settings.showShortcutsByColor[color] ~= false then
            table.insert(viewers, color)
        end
    end
    -- Empty visibility means EVERYONE in TTS, so never use an empty string
    -- as the hidden value. The overlay is still a single shared Global UI node.
    UI.setAttribute("MTG_ShortcutsOverlay", "visibility",
        #viewers > 0 and table.concat(viewers, "|") or "Black")
    UI.setAttribute("MTG_ShortcutsOverlay", "active",
        #viewers > 0 and "true" or "false")
end

function Settings.toggleGeneral(player, value, id)
    if Settings.uiSyncing then return end
    local color = Settings.playerColor(player)
    if color == nil or color ~= Settings.menuOwner or not Settings.validColor(color) then
        return
    end
    if id == "lotus_show_shortcuts" then
        Settings.showShortcutsByColor[color] = Settings.toBool(value)
        Settings.applyShortcutsVisibility()
    elseif id == "lotus_enable_combat" then
        Settings.combatEnabledByColor[color] = Settings.toBool(value)
        if not Settings.combatEnabledByColor[color] then
            Combat.pending[color] = nil
            Combat.clear(color)
        end
    else
        return
    end
    Settings.persist()
end

-- A per-player value selected in the General tab. The menu is owner-only;
-- another player's slider callback must never change this owner's setting.
function Settings.changeUndoHold(player, value, id)
    if Settings.uiSyncing or id ~= "lotus_combat_hold_slider" then return end
    local color = Settings.playerColor(player)
    if not Settings.validColor(color) or color ~= Settings.menuOwner then return end
    local seconds = Settings.normalizeUndoHold(value)
    UI.setAttribute("lotus_combat_hold_value", "text", tostring(seconds) .. " s")
    if Settings.getUndoHold(color) == seconds then return end
    Settings.combatUndoHoldSecondsByColor[color] = seconds
    Settings.persist()
end

-- Keep every unrelated button attached to the Lotus intact.
function Settings.createButton()
    for _, button in ipairs(self.getButtons() or {}) do
        if button.click_function == "settingsButtonClick" then return end
    end
    self.createButton({
        click_function = "settingsButtonClick",
        function_owner = self,
        label = "Settings",
        position = {0, 0.6, 0},
        rotation = {0, 180, 0},
        scale = {1, 1, 1},
        width = 900,
        height = 150,
        font_size = 220,
        color = {0.15, 0.15, 0.15, 0.9},
        font_color = {1, 1, 1, 1}
    })
end

-- Single-release reader: natural word wrapping, no split pages, no
-- blank-line gaps, and a much larger text field. Best-fit prevents ordinary
-- release notes from being clipped without relying on mouse-wheel scrolling.
function Settings.patchNotesReader()
    return {
        tag = "Panel",
        attributes = {
            id = "MTG_Settings_PatchNotesBox",
            rectAlignment = "UpperCenter", offsetXY = "0 -36",
            width = "500", height = "394", color = "#28272B"
        },
        children = {
            { tag = "Text", attributes = {
                id = "MTG_Settings_PatchNotesVersion",
                rectAlignment = "UpperLeft", offsetXY = "13 -8",
                width = "474", height = "32", fontSize = "21",
                fontStyle = "Bold", color = "#FFFFFF",
                alignment = "MiddleLeft", text = "Patch Notes"
            }},
            { tag = "Panel", attributes = {
                id = "MTG_Settings_PatchNotesReader_v120",
                rectAlignment = "UpperCenter", offsetXY = "0 -44",
                width = "472", height = "2", color = "#4B5D71"
            }},
            { tag = "Text", attributes = {
                id = "MTG_Settings_PatchNotesText",
                rectAlignment = "UpperLeft", offsetXY = "13 -54",
                width = "474", height = "284", fontSize = "17",
                resizeTextForBestFit = "true",
                resizeTextMinSize = "12",
                resizeTextMaxSize = "17",
                color = "#EDEEF2", alignment = "UpperLeft",
                horizontalOverflow = "Wrap", verticalOverflow = "Truncate",
                raycastTarget = "false", text = "No patch notes published yet."
            }},
            { tag = "HorizontalLayout", attributes = {
                rectAlignment = "LowerCenter", offsetXY = "0 9",
                width = "474", height = "34", spacing = "10",
                childAlignment = "MiddleCenter",
                childForceExpandWidth = "false", childForceExpandHeight = "false"
            }, children = {
                {tag = "Button", attributes = {
                    id = "MTG_Settings_PatchNotesNewer",
                    preferredWidth = "135", preferredHeight = "34",
                    fontSize = "15", fontStyle = "Bold",
                    textColor = "#FFFFFF",
                    colors = "#315A87|#4274AC|#234363|#234363",
                    onClick = "777766/settingsNotesNavigate", text = "< NEWER"
                }},
                {tag = "Text", attributes = {
                    id = "MTG_Settings_PatchNotesPosition",
                    preferredWidth = "164", preferredHeight = "34",
                    fontSize = "14", color = "#AEBAC8",
                    alignment = "MiddleCenter", text = "1 / 1"
                }},
                {tag = "Button", attributes = {
                    id = "MTG_Settings_PatchNotesOlder",
                    preferredWidth = "135", preferredHeight = "34",
                    fontSize = "15", fontStyle = "Bold",
                    textColor = "#FFFFFF",
                    colors = "#315A87|#4274AC|#234363|#234363",
                    onClick = "777766/settingsNotesNavigate", text = "OLDER >"
                }}
            }}
        }
    }
end

Settings.PATCH_NOTES_HINT = "Read-only | Creator edits LOTUS_PATCH_NOTES in the Black Notebook"

-- The preview tab is regenerated as a unit to avoid mismatched columns
-- when upgrading older Global XML; counter/notes tabs remain untouched.
function Settings.previewTab()
    local function label(text, width, color, size, bold)
        local attr = {
            preferredWidth = tostring(width), minWidth = tostring(width),
            fontSize = tostring(size or 17), color = color or "rgb(0.9,0.9,0.9)",
            alignment = "MiddleLeft", text = text
        }
        if bold then attr.fontStyle = "Bold" end
        return {tag = "Text", attributes = attr}
    end
    local function toggle(id, enabled, width)
        return {tag = "Toggle", attributes = {
            id = id, isOn = enabled and "True" or "False",
            onValueChanged = "777766/previewToggle",
            preferredWidth = tostring(width), minWidth = tostring(width)
        }}
    end
    local function row(y, title, myID, myDefault, opponentsID, opponentsDefault, titleSize)
        return {tag = "HorizontalLayout", attributes = {
            rectAlignment = "UpperCenter", offsetXY = "0 " .. tostring(y),
            width = "500", height = "44", spacing = "8",
            childForceExpandWidth = "false", childForceExpandHeight = "false"
        }, children = {
            label(title, 220, nil, titleSize or 17),
            toggle(myID, myDefault, 105),
            toggle(opponentsID, opponentsDefault, 155)
        }}
    end
    return {tag = "Panel", attributes = {
        id = "MTG_Settings_Tab_Preview",
        rectAlignment = "UpperCenter", offsetXY = "0 -124",
        width = "516", height = "320", color = "clear", active = "false"
    }, children = {
        {tag = "HorizontalLayout", attributes = {
            id = "MTG_Settings_PreviewGrid_v120_compact",
            rectAlignment = "UpperCenter", offsetXY = "0 -8",
            width = "500", height = "28", spacing = "8",
            childForceExpandWidth = "false", childForceExpandHeight = "false"
        }, children = {
            label("PREVIEW OPTION", 220, "#6fa0d8", 14, true),
            label("MY CARDS", 105, "#6fa0d8", 13, true),
            label("OPPONENTS' CARDS", 155, "#6fa0d8", 12, true)
        }},
        row(-50, "Played Card Preview", "preview_cards_mine", true,
            "preview_cards_opponents", true),
        row(-102, "Hide Land Previews", "preview_hide_lands_mine", false,
            "preview_hide_lands_opponents", false),
        row(-154, "First Commander Entry Preview",
            "preview_first_commander_mine", true,
            "preview_first_commander_opponents", true, 14),
        {tag = "Text", attributes = {
            rectAlignment = "UpperLeft", offsetXY = "8 -211",
            width = "480", height = "21", fontSize = "14",
            fontStyle = "Bold", color = "#6fa0d8",
            text = "PREVIEW SIZE (MY SCREEN ONLY)"
        }},
        {tag = "HorizontalLayout", attributes = {
            rectAlignment = "UpperCenter", offsetXY = "0 -240",
            width = "500", height = "35", spacing = "8",
            childForceExpandWidth = "false", childForceExpandHeight = "false"
        }, children = {
            label("Card preview scale", 176, nil, 16),
            {tag = "Slider", attributes = {
                id = "lotus_preview_size_slider",
                onValueChanged = self.getGUID() .. "/settingsPreviewSizeChanged",
                preferredWidth = "237", minWidth = "237",
                preferredHeight = "30", minHeight = "30",
                minValue = "50", maxValue = "150", value = "100",
                wholeNumbers = "true",
                backgroundColor = "#393A42", fillColor = "#4274AC",
                handleColor = "#E5EBF4"
            }},
            {tag = "Text", attributes = {
                id = "lotus_preview_size_value",
                preferredWidth = "65", minWidth = "65",
                fontSize = "17", fontStyle = "Bold",
                color = "#87B9EF", alignment = "MiddleRight", text = "100%"
            }}
        }},
        {tag = "Text", attributes = {
            rectAlignment = "UpperLeft", offsetXY = "8 -288",
            width = "490", height = "20", fontSize = "13",
            color = "#9BA4B0",
            text = "Affects my and opponents' card previews on my screen only."
        }}
    }}
end

-- Read-only shortcut list mirrors Global.onScriptingButtonDown.
-- Numpad 0 corresponds to scripting index 10; 1-9 correspond to indices 1-9.
-- This overlay NEVER registers scripting events of its own.
Settings.SHORTCUTS = {
    { key = "Num 0", action = "Enable / End turn" },
    { key = "Num 1", action = "Untap" },
    { key = "Num 2", action = "Draw" },
    { key = "Num 3", action = "Scry" },
    { key = "Num 4", action = "Mill" },
    { key = "Num 5", action = "Reveal (fan)" },
    { key = "Num 6", action = "Reveal (stack)" },
    { key = "Num 7", action = "To graveyard *" },
    { key = "Num 8", action = "To exile *" },
    { key = "Num 9", action = "Library bottom *" }
}

-- Persistent screen-edge overlay, shown from every seat (not world-space text).
-- No raycast targets: it doesn't block tabletop interactions underneath.
function Settings.shortcutsOverlay()
    local rows = {}
    for _, item in ipairs(Settings.SHORTCUTS) do
        table.insert(rows, {tag = "HorizontalLayout", attributes = {
            preferredHeight = "24", minHeight = "24", spacing = "6",
            childForceExpandHeight = "false", childForceExpandWidth = "false",
            raycastTarget = "false"
        }, children = {
            {tag = "Text", attributes = {
                preferredWidth = "54", minWidth = "54", fontSize = "14",
                fontStyle = "Bold", color = "#87B9EF",
                alignment = "MiddleLeft", raycastTarget = "false",
                text = item.key
            }},
            {tag = "Text", attributes = {
                preferredWidth = "166", minWidth = "166", fontSize = "14",
                color = "#F0F1F4", alignment = "MiddleLeft",
                raycastTarget = "false", text = item.action
            }}
        }})
    end
    return {tag = "Panel", attributes = {
        id = "MTG_ShortcutsOverlay", rectAlignment = "MiddleLeft",
        offsetXY = "7 -165", width = "252", height = "325",
        color = "clear",
        raycastTarget = "false", active = "true"
    }, children = {
        {tag = "Text", attributes = {
            rectAlignment = "UpperLeft", offsetXY = "11 -9",
            width = "230", height = "22", fontSize = "17",
            fontStyle = "Bold", color = "#F0F1F4",
            raycastTarget = "false", text = "Shortcuts"
        }},
        {tag = "VerticalLayout", attributes = {
            rectAlignment = "UpperCenter", offsetXY = "0 -34",
            width = "228", height = "251", spacing = "1",
            childForceExpandHeight = "false", childForceExpandWidth = "false",
            raycastTarget = "false"
        }, children = rows},
        {tag = "Text", attributes = {
            rectAlignment = "LowerLeft", offsetXY = "11 8",
            width = "230", height = "15", fontSize = "11",
            color = "#ACB7C5", raycastTarget = "false",
            text = "* Selected cards or hovered card"
        }}
    }}
end

function Settings.generalTab()
    local cb = self.getGUID() .. "/"
    return {tag = "Panel", attributes = {
        id = "MTG_Settings_Tab_General", rectAlignment = "UpperCenter",
        offsetXY = "0 -124", width = "516", height = "280",
        color = "clear", active = "false"
    }, children = {
        {tag = "Text", attributes = {
            rectAlignment = "UpperLeft", offsetXY = "11 -3", width = "470",
            height = "24", fontSize = "14", fontStyle = "Bold",
            alignment = "MiddleLeft", color = "#6fa0d8", text = "GENERAL"
        }},
        {tag = "Panel", attributes = {
            id = "MTG_Settings_GeneralContent_v155",
            rectAlignment = "UpperCenter", offsetXY = "0 -36",
            width = "500", height = "240", color = "#28272B"
        }, children = {
            {tag = "Toggle", attributes = {
                id = "lotus_show_shortcuts", isOn = "True",
                onValueChanged = cb .. "settingsGeneralToggle",
                rectAlignment = "UpperLeft", offsetXY = "16 -12",
                width = "465", height = "31", fontSize = "17",
                textColor = "#EDEEF2"
            }, value = "Show numpad shortcuts on my screen"},
            {tag = "Text", attributes = {
                rectAlignment = "UpperLeft", offsetXY = "16 -46",
                width = "465", height = "20", fontSize = "13",
                color = "#9BA4B0", alignment = "MiddleLeft",
                text = "Numpad keys: TTS Configuration > Controls."
            }},
            {tag = "Toggle", attributes = {
                id = "lotus_enable_combat", isOn = "True",
                onValueChanged = cb .. "settingsGeneralToggle",
                rectAlignment = "UpperLeft", offsetXY = "16 -79",
                width = "465", height = "33", fontSize = "17",
                textColor = "#EDEEF2"
            }, value = "Enable combat targeting for me"},
            {tag = "Button", attributes = {
                id = "lotus_combat_bind",
                onClick = cb .. "settingsCombatKeyConfig",
                rectAlignment = "UpperLeft", offsetXY = "16 -127",
                width = "468", height = "35", fontSize = "15",
                textColor = "#FFFFFF", colors = "#315A87|#4274AC|#234363|#234363",
                text = "Open Game Keys"
            }},
            {tag = "Text", attributes = {
                rectAlignment = "UpperLeft", offsetXY = "16 -177",
                width = "365", height = "24", fontSize = "15",
                fontStyle = "Bold", color = "#EDEEF2",
                alignment = "MiddleLeft",
                text = "Hold UNDO to clear all your arrows"
            }},
            {tag = "Text", attributes = {
                id = "lotus_combat_hold_value",
                rectAlignment = "UpperRight", offsetXY = "-16 -177",
                width = "88", height = "24", fontSize = "17",
                fontStyle = "Bold", color = "#87B9EF",
                alignment = "MiddleRight", text = "5 s"
            }},
            {tag = "Slider", attributes = {
                id = "lotus_combat_hold_slider",
                onValueChanged = cb .. "settingsCombatHoldChanged",
                rectAlignment = "UpperLeft", offsetXY = "16 -209",
                width = "468", height = "27",
                minValue = "1", maxValue = "10", value = "5",
                wholeNumbers = "true",
                backgroundColor = "#393A42", fillColor = "#4274AC",
                handleColor = "#E5EBF4"
            }},
        }}
    }}
end

-- Upgrades both the older three-tab panel and the v1.4.1 Shortcuts tab.
-- Rebuilds only Lotus's own tab buttons; leaves all other Global UI intact.
function Settings.ensureGeneralTab(panel)
    if type(panel) ~= "table" or type(panel.children) ~= "table" then return false end
    local tabbar
    for _, child in ipairs(panel.children) do
        if child.attributes and child.attributes.id == "MTG_Settings_TabBar" then
            tabbar = child
            break
        end
    end
    if tabbar == nil or type(tabbar.children) ~= "table" then return false end
    local changed = false
    local hasGeneral = false
    -- Use an existing General button if present. Migrate the Shortcuts button
    -- in place when possible, instead of leaving two buttons behind.
    for _, btn in ipairs(tabbar.children) do
        if btn.attributes and btn.attributes.id == "MTG_Settings_Button_General" then
            hasGeneral = true
        end
    end
    for i = #tabbar.children, 1, -1 do
        local btn = tabbar.children[i]
        local attr = btn.attributes or {}
        if attr.id == "MTG_Settings_Button_Shortcuts" then
            if hasGeneral then
                table.remove(tabbar.children, i)
            else
                attr.id = "MTG_Settings_Button_General"
                attr.text = "General"
                attr.onClick = self.getGUID() .. "/settingsSelectTab"
                hasGeneral = true
            end
            changed = true
        end
    end
    if not hasGeneral then
        table.insert(tabbar.children, 1, {tag = "Button", attributes = {
            id = "MTG_Settings_Button_General", text = "General",
            preferredWidth = "124", minWidth = "124",
            preferredHeight = "38", minHeight = "38",
            fontSize = "15", fontStyle = "Bold", textColor = "#FFFFFF",
            colors = "#315A87|#4274AC|#234363|#234363",
            onClick = self.getGUID() .. "/settingsSelectTab"
        }})
        changed = true
    end
    local preferredOrder = {
        "MTG_Settings_Button_General", "MTG_Settings_Button_Notes",
        "MTG_Settings_Button_Counters", "MTG_Settings_Button_Preview"
    }
    local byId = {}
    for _, btn in ipairs(tabbar.children) do
        if btn.attributes then byId[btn.attributes.id] = btn end
    end
    local ordered = {}
    for _, id in ipairs(preferredOrder) do
        if byId[id] then table.insert(ordered, byId[id]) end
    end
    -- Unknown tab buttons should not be deleted.
    for _, btn in ipairs(tabbar.children) do
        local id = btn.attributes and btn.attributes.id
        if not byId[id] or not (
            id == preferredOrder[1] or id == preferredOrder[2] or
            id == preferredOrder[3] or id == preferredOrder[4]) then
            table.insert(ordered, btn)
        end
    end
    if #ordered == #tabbar.children then
        for i, btn in ipairs(ordered) do
            if tabbar.children[i] ~= btn then changed = true; break end
        end
        tabbar.children = ordered
    end
    for _, btn in ipairs(tabbar.children) do
        local attr = btn.attributes
        if attr and type(attr.id) == "string"
            and attr.id:match("^MTG_Settings_Button_") then
            for _, field in ipairs({"preferredWidth", "minWidth"}) do
                if attr[field] ~= "124" then attr[field] = "124"; changed = true end
            end
            if attr.fontSize ~= "15" then attr.fontSize = "15"; changed = true end
        end
    end

    local hasGeneralPanel = false
    for i = #panel.children, 1, -1 do
        local child = panel.children[i]
        local id = child.attributes and child.attributes.id
        if id == "MTG_Settings_Tab_General" then
            hasGeneralPanel = true
            -- Replace only Lotus' own obsolete General tab. Never touch other UI.
            local current = false
            for _, node in ipairs(child.children or {}) do
                if node.attributes
                    and node.attributes.id == "MTG_Settings_GeneralContent_v155" then
                    current = true
                    break
                end
            end
            if not current then
                panel.children[i] = Settings.generalTab()
                changed = true
            end
        elseif id == "MTG_Settings_Tab_Shortcuts" then
            table.remove(panel.children, i)
            changed = true
        end
    end
    if not hasGeneralPanel then
        table.insert(panel.children, 1, Settings.generalTab())
        changed = true
    end
    return changed
end

-- Add the new counter using the same ME / EVERYONE semantics as
-- Energy, Poison, Experience and Rad. This also migrates an older UI panel
-- already loaded in the TTS save, without recreating the settings window.
function Settings.manaCounterRow()
    return {
        tag = "HorizontalLayout",
        attributes = {
            preferredHeight = "38", minHeight = "38", spacing = "8",
            childForceExpandWidth = "false",
            childForceExpandHeight = "false"
        },
        children = {
            {
                tag = "Text",
                attributes = {
                    preferredWidth = "260", minWidth = "260",
                    fontSize = "17", color = "rgb(0.9,0.9,0.9)",
                    alignment = "MiddleLeft", text = "Mana Counters"
                }
            },
            {
                tag = "Toggle",
                attributes = {
                    id = "counter_mana_me", isOn = "True",
                    onValueChanged = self.getGUID() .. "/counterToggle",
                    preferredWidth = "80", minWidth = "80"
                }
            },
            {
                tag = "Toggle",
                attributes = {
                    id = "counter_mana_everyone", isOn = "True",
                    onValueChanged = self.getGUID() .. "/counterToggle",
                    preferredWidth = "100", minWidth = "100"
                }
            }
        }
    }
end

function Settings.ensureManaCounterRow(tab)
    local layout = nil
    for _, child in ipairs(tab.children or {}) do
        if child.tag == "VerticalLayout" then
            layout = child
            break
        end
    end
    if layout == nil or type(layout.children) ~= "table" then return false end
    local insertAt = #layout.children + 1
    for i, row in ipairs(layout.children) do
        for _, cell in ipairs(row.children or {}) do
            local id = cell.attributes and cell.attributes.id
            if id == "counter_mana_me" or id == "counter_mana_everyone" then
                return false
            end
            if id == "counter_all_me" then insertAt = i end
        end
    end
    table.insert(layout.children, insertAt, Settings.manaCounterRow())
    return true
end

-- Tabbed panel is also generated as a fallback when no Global XML panel exists.
-- The installer automatically upgrades the legacy panel on first load.
function Settings.tabbedPanel()
    local panel = {
        tag = "Panel",
        attributes = {
            id = "CounterVisibilityPanel",
            width = "560",
            height = "465",
            rectAlignment = "MiddleCenter",
            showAnimation = "FadeIn",
            hideAnimation = "FadeOut",
            returnToOriginalPositionWhenReleased = "false",
            allowDragging = "true",
            color = "rgba(0.1,0.1,0.1,0.97)",
            outline = "#635351",
            outlineSize = "2 -2",
            visibility = "",
            active = "false",
        },
        children = {
            {
            tag = "Text",
            attributes = {
                rectAlignment = "UpperCenter",
                offsetXY = "0 -18",
                width = "410",
                height = "34",
                fontSize = "26",
                fontStyle = "Bold",
                color = "rgb(1,1,1)",
                alignment = "MiddleCenter",
                text = "Table Settings",
            },
        }, 
            {
            tag = "Button",
            attributes = {
                id = "CounterVisibilityClose",
                rectAlignment = "UpperRight",
                offsetXY = "-8 -8",
                width = "30",
                height = "30",
                color = "#990000",
                textColor = "#FFFFFF",
                text = "X",
                fontSize = "18",
                onClick = "777766/closeCounterSettings",
            },
        }, 
            {
            tag = "HorizontalLayout",
            attributes = {
                id = "MTG_Settings_TabBar",
                rectAlignment = "UpperCenter",
                offsetXY = "0 -70",
                width = "516",
                height = "40",
                spacing = "6",
                childForceExpandWidth = "false",
                childForceExpandHeight = "false",
            },
            children = {
                {
                tag = "Button",
                attributes = {
                    id = "MTG_Settings_Button_Notes",
                    preferredWidth = "168",
                    minWidth = "168",
                    preferredHeight = "38",
                    minHeight = "38",
                    fontSize = "16",
                    fontStyle = "Bold",
                    textColor = "#FFFFFF",
                    colors = "#315A87|#4274AC|#234363|#234363",
                    onClick = "777766/settingsSelectTab",
                    text = "Patch Notes",
                },
            }, 
                {
                tag = "Button",
                attributes = {
                    id = "MTG_Settings_Button_Counters",
                    preferredWidth = "168",
                    minWidth = "168",
                    preferredHeight = "38",
                    minHeight = "38",
                    fontSize = "16",
                    fontStyle = "Bold",
                    textColor = "#C9D1DF",
                    colors = "#29292E|#3D3D45|#222229|#222229",
                    onClick = "777766/settingsSelectTab",
                    text = "Counters",
                },
            }, 
                {
                tag = "Button",
                attributes = {
                    id = "MTG_Settings_Button_Preview",
                    preferredWidth = "168",
                    minWidth = "168",
                    preferredHeight = "38",
                    minHeight = "38",
                    fontSize = "16",
                    fontStyle = "Bold",
                    textColor = "#C9D1DF",
                    colors = "#29292E|#3D3D45|#222229|#222229",
                    onClick = "777766/settingsSelectTab",
                    text = "Card Preview",
                },
            }, 
            },
        }, 
            {
            tag = "Panel",
            attributes = {
                id = "MTG_Settings_Tab_Notes",
                rectAlignment = "UpperCenter",
                offsetXY = "0 -124",
                width = "516",
                height = "460",
                color = "clear",
                active = "true",
            },
            children = {
                {
                tag = "Text",
                attributes = {
                    rectAlignment = "UpperLeft",
                    offsetXY = "11 -3",
                    width = "400",
                    height = "25",
                    fontSize = "14",
                    fontStyle = "Bold",
                    alignment = "MiddleLeft",
                    color = "#6fa0d8",
                    text = "PATCH NOTES",
                },
            }, 
                Settings.patchNotesReader(),
                {
                tag = "Text",
                attributes = {
                    id = "MTG_Settings_PatchNotesHint",
                    rectAlignment = "LowerCenter",
                    offsetXY = "0 5",
                    width = "495",
                    height = "22",
                    fontSize = "12",
                    alignment = "MiddleLeft",
                    color = "#9BA4B0",
                    text = Settings.PATCH_NOTES_HINT,
                },
            }, 
            },
        }, 
            {
            tag = "Panel",
            attributes = {
                id = "MTG_Settings_Tab_Counters",
                rectAlignment = "UpperCenter",
                offsetXY = "0 -124",
                width = "516",
                height = "325",
                color = "clear",
                active = "false",
            },
            children = {
                {
                tag = "VerticalLayout",
                attributes = {
                    rectAlignment = "UpperCenter",
                    offsetXY = "0 -5",
                    width = "500",
                    height = "300",
                    spacing = "5",
                    childForceExpandHeight = "false",
                    childForceExpandWidth = "true",
                },
                children = {
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "28",
                        minHeight = "28",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "14",
                            fontStyle = "Bold",
                            color = "#6fa0d8",
                            alignment = "MiddleLeft",
                            text = "COUNTER TYPE",
                        },
                    }, 
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "80",
                            minWidth = "80",
                            fontSize = "14",
                            fontStyle = "Bold",
                            color = "#6fa0d8",
                            alignment = "MiddleCenter",
                            text = "ME",
                        },
                    }, 
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "100",
                            minWidth = "100",
                            fontSize = "14",
                            fontStyle = "Bold",
                            color = "#6fa0d8",
                            alignment = "MiddleCenter",
                            text = "EVERYONE",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "38",
                        minHeight = "38",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            color = "rgb(0.9,0.9,0.9)",
                            alignment = "MiddleLeft",
                            text = "Energy Counters",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_energy_me",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_energy_everyone",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "38",
                        minHeight = "38",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            color = "rgb(0.9,0.9,0.9)",
                            alignment = "MiddleLeft",
                            text = "Poison Counters",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_poison_me",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_poison_everyone",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "38",
                        minHeight = "38",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            color = "rgb(0.9,0.9,0.9)",
                            alignment = "MiddleLeft",
                            text = "Experience Counters",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_experience_me",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_experience_everyone",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "38",
                        minHeight = "38",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            color = "rgb(0.9,0.9,0.9)",
                            alignment = "MiddleLeft",
                            text = "Rad Counters",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_rad_me",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_rad_everyone",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "42",
                        minHeight = "42",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            fontStyle = "Bold",
                            color = "rgb(1,1,1)",
                            alignment = "MiddleLeft",
                            text = "ALL COUNTERS",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_all_me",
                            isOn = "True",
                            onValueChanged = "777766/allMeToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_all_everyone",
                            isOn = "True",
                            onValueChanged = "777766/allEveryoneToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                },
            }, 
            },
        }, 
            Settings.previewTab(),
        },
    }
    for _, child in ipairs(panel.children) do
        if child.attributes and child.attributes.id == "MTG_Settings_Tab_Counters" then
            Settings.ensureManaCounterRow(child)
            break
        end
    end
    Settings.ensureGeneralTab(panel)
    return panel
end

-- v1.2.0 marker upgrades earlier patch-note readers on Save & Play.
-- This is essential because the previous reader already had the same root ID.
function Settings.isCurrentPatchReader(node)
    local function hasMarker(n)
        if n.attributes and n.attributes.id ==
            "MTG_Settings_PatchNotesReader_v120" then
            return true
        end
        for _, child in ipairs(n.children or {}) do
            if hasMarker(child) then return true end
        end
        return false
    end
    return hasMarker(node)
end

function Settings.installUI()
    local xml = UI.getXmlTable() or {}
    local found, changed = false, false
    local guid = self.getGUID()
    local callbacks = {
        closeCounterSettings = true,
        counterToggle = true,
        allMeToggle = true,
        allEveryoneToggle = true,
        previewToggle = true,
        settingsSelectTab = true,
        settingsNotesNavigate = true,
        settingsGeneralToggle = true,
        settingsCombatKeyConfig = true,
        settingsCombatHoldChanged = true,
        settingsPreviewSizeChanged = true
    }

    local function hasTabs(node)
        if type(node) ~= "table" then return false end
        if node.attributes and node.attributes.id == "MTG_Settings_TabBar" then
            return true
        end
        for _, child in ipairs(node.children or {}) do
            if hasTabs(child) then return true end
        end
        return false
    end

    -- Walk every UI subtree, replacing only the legacy Settings panel.
    -- Preserve all unrelated Global XML, including preview/other mod UIs.
    local function walk(nodes)
        for index, node in ipairs(nodes) do
            if node.attributes and node.attributes.id == "CounterVisibilityPanel" then
                found = true
                if not hasTabs(node) then
                    nodes[index] = Settings.tabbedPanel()
                    node = nodes[index]
                    changed = true
                    log("MTG Helper: legacy settings panel upgraded to tabs.")
                end
                if Settings.ensureGeneralTab(node) then
                    changed = true
                    log("MTG Helper: installed General settings tab.")
                end
            end
            if type(node.attributes) == "table" then
                -- The previous tab panel is too short for a full release.
                if node.attributes.id == "MTG_Settings_Tab_Notes"
                    and node.attributes.height ~= "460" then
                    node.attributes.height = "460"
                    changed = true
                end
                -- Migrate legacy InputField, ScrollViews and older readers
                -- without touching any other settings or table UI.
                if node.attributes.id == "MTG_Settings_PatchNotesInput"
                    or (node.attributes.id == "MTG_Settings_PatchNotesBox"
                        and not Settings.isCurrentPatchReader(node)) then
                    nodes[index] = Settings.patchNotesReader()
                    node = nodes[index]
                    changed = true
                    log("MTG Helper: upgraded Patch Notes to the release reader.")
                end
                if node.attributes.id == "MTG_Settings_Tab_Counters" then
                    if Settings.ensureManaCounterRow(node) then
                        changed = true
                        log("MTG Helper: added Mana counter visibility settings.")
                    end
                end
                if node.attributes.id == "MTG_Settings_Tab_Preview" then
                    local upgraded = false
                    for _, child in ipairs(node.children or {}) do
                        if child.attributes and
                            child.attributes.id == "lotus_preview_size_slider" then
                            upgraded = true
                            break
                        end
                    end
                    if not upgraded then
                        nodes[index] = Settings.previewTab()
                        node = nodes[index]
                        changed = true
                        log("MTG Helper: updated compact Card Preview settings.")
                    end
                end
                if node.attributes.id == "MTG_Settings_PatchNotesHint" then
                    if node.attributes.text ~= Settings.PATCH_NOTES_HINT then
                        node.attributes.text = Settings.PATCH_NOTES_HINT
                        changed = true
                    end
                end
                for _, attr in ipairs({"onClick", "onValueChanged", "onEndEdit"}) do
                    local callback = node.attributes[attr]
                    if type(callback) == "string" then
                        local previous, fn = callback:match("^([%w]+)/([%w_]+)$")
                        if previous == Settings.OLD_CONTROLLER_GUID and callbacks[fn] then
                            node.attributes[attr] = guid .. "/" .. fn
                            changed = true
                        end
                    end
                end
            end
            if type(node.children) == "table" then walk(node.children) end
        end
    end
    walk(xml)

    -- Install the shortcuts overlay only if it is missing.
    -- Never replace an existing panel: its position, size, alignment, and
    -- appearance belong to the editable Global UI XML.
    local hasOverlay = false
    for _, node in ipairs(xml) do
        if node.attributes and node.attributes.id == "MTG_ShortcutsOverlay" then
            hasOverlay = true
            break
        end
    end
    if not hasOverlay then
        table.insert(xml, Settings.shortcutsOverlay())
        changed = true
    end

    if not found then
        table.insert(xml, Settings.tabbedPanel())
        changed = true
        log("MTG Helper: created tabbed EDH Settings UI.")
    end
    if changed then UI.setXmlTable(xml) end
    -- Runtime UI may be rebuilding after setXmlTable; defer panel reset.
    Wait.frames(function()
        UI.setAttribute("CounterVisibilityPanel", "active", "false")
        Settings.applyShortcutsVisibility()
    end, 4)
end

function Settings.ready()
    Settings.createButton()
    Settings.ensureNotebookTab()
    Settings.installUI()
    Settings.applyPreview()
    Settings.applyAll(true)
    Wait.time(function() Settings.applyAll(false) end, 3.0, -1)
    log("MTG Portable Helper: EDH Settings module ready.")
end

-- =============================================================
-- MODULE 5/5: ORIGINAL MOON-MTG EQUIPMENT (ENCODER-BASED)
-- Source: moon-mtg-equip v1.0.4 from the supplied standalone script.
-- Original Encoder attachment/unequip mechanics preserved.
-- Both equipment controls are now visible only while hovered.
-- =============================================================

local Equipment = {}

--[[--
moon-mtg-equip (tag-aware, menu-safe, high-visibility hover button)
Original equipment logic: stella + Lilith / stella.lifeless.space

WHY THE CONTROL MOVED:
Tabletop Simulator cannot remove one specific object context-menu item.
Object.clearContextMenu() would also remove custom menu options installed
by other MTG scripts (Draw Random, Cascade, Reveal, etc.).

This version NEVER adds an 'equip all to top' context-menu entry.
Instead it shows a large, high-contrast 'EQUIP ALL' button on hover over
an eligible Deck; the button disappears on leaving the deck or on entering
an Exile/Library/Graveyard tagged area. Other scripts' menus are untouched.

Tags can be on the Deck, a Scripting Zone, or a snap point.
Tagged snap points are detected by proximity (configurable radius below).
Reload scripts with Save & Play to discard old context-menu entries.
--]]--

local prop_id = "moon-mtg-equip"
local equipment_version = "1.0.4"

local EXCLUDED_TAGS = { "Exile", "Library", "Graveyard" }
local EXCLUDED_LOOKUP = { exile = true, library = true, graveyard = true }
local BUTTON_MARKER = "moon-mtg-equip / equip all to top"
local PROTECTED_SNAP_RADIUS = 0.85 -- TTS world units; adjust if needed
local protectedSnapPositions = {}

-- High-visibility hover button appearance. Adjust these settings to taste.
-- The button only appears on eligible Decks while hovered.
local EQUIP_BUTTON_STYLE = {
    label = "EQUIP ALL",
    position = {0, 0.38, -0.8},
    scale = {0.63, 0.63, 0.63},
    width = 980,
    height = 300,
    font_size = 155,
    color = {1.0, 0.73, 0.12, 1.0},       -- bright amber/gold
    font_color = {0.08, 0.06, 0.02, 1.0}, -- dark text for contrast
    hover_color = {1.0, 0.88, 0.33, 1.0},
    press_color = {0.79, 0.48, 0.04, 1.0},
}

-- player color -> hovered Deck/Card GUID; only hovered objects get buttons
local hovered = {}

local function has_protected_tag(obj)
    if obj == nil then return false end
    local ok, tags = pcall(function() return obj.getTags() end)
    if not ok or type(tags) ~= "table" then return false end
    for _, tag in ipairs(tags) do
        if EXCLUDED_LOOKUP[string.lower(tostring(tag))] then
            return true
        end
    end
    return false
end

local function is_protected_tag_list(tags)
    for _, tag in ipairs(tags or {}) do
        if EXCLUDED_LOOKUP[string.lower(tostring(tag))] then return true end
    end
    return false
end

-- Snap points are separate from scripting zones. In particular, putting a
-- deck onto a tagged snap point does NOT apply that tag to the Deck.
-- Cache them once at load to avoid scanning every object on each hover.
local function collect_protected_snap_points()
    protectedSnapPositions = {}

    local function collect(owner)
        local ok, points = pcall(function() return owner.getSnapPoints() end)
        if not ok or type(points) ~= "table" then return end

        for _, point in ipairs(points) do
            if is_protected_tag_list(point.tags) then
                local pos = point.position
                if owner ~= Global then
                    pos = owner.positionToWorld(point.position)
                end
                table.insert(protectedSnapPositions, pos)
            end
        end
    end

    collect(Global)
    for _, obj in ipairs(getObjects()) do collect(obj) end
end

local function near_protected_snap_point(deck)
    local pos = deck.getPosition()
    local px, pz = pos.x or pos[1], pos.z or pos[3]
    local r2 = PROTECTED_SNAP_RADIUS * PROTECTED_SNAP_RADIUS
    for _, snap in ipairs(protectedSnapPositions) do
        local sx, sz = snap.x or snap[1], snap.z or snap[3]
        if sx and sz then
            local dx, dz = px - sx, pz - sz
            if dx*dx + dz*dz <= r2 then return true end
        end
    end
    return false
end

local function deck_is_excluded(deck)
    if deck == nil or deck.tag ~= "Deck" then return false end
    if has_protected_tag(deck) or near_protected_snap_point(deck) then return true end

    -- Scripting zones TTS reports for this object.
    for _, zone in ipairs(deck.getZones() or {}) do
        if has_protected_tag(zone) then return true end
    end

    -- getZones() is tag-filtered. Check tagged scripting zones with
    -- getObjects(true) so an untagged deck doesn't get missed.
    for _, candidate in ipairs(getObjectsWithAnyTags(EXCLUDED_TAGS)) do
        if candidate.tag == "Scripting" or candidate.type == "Scripting" then
            local ok, occupants = pcall(function()
                return candidate.getObjects(true)
            end)
            if ok and type(occupants) == "table" then
                for _, occupant in ipairs(occupants) do
                    if occupant == deck then return true end
                end
            end
        end
    end

    return false
end

-- Encoder API wrapper -----------------------------------------------------
local encoder
do
    local mt = {
        __index = function(self, index)
            return function(args)
                return rawget(self, "object").call("API" .. index, args)
            end
        end
    }

    encoder = function()
        local object = Global.getVar("Encoder")
        return object ~= nil and setmetatable({ object = object }, mt) or nil
    end
end

local function register_module()
    local enc = encoder()
    if enc == nil then return end

    local v = tostring(enc.object.getVar("version") or "")
    local major, minor = v:match("^(%d+)%.(%d+)")
    major, minor = tonumber(major), tonumber(minor)
    if not major or major < 4 or (major == 4 and minor < 4) then
        broadcastToAll("encoder version must be >=4.4", {1, 0, 0, 1})
        error("bad encoder version")
    end

    enc.registerProperty {
        propID = prop_id,
        name = "Manage Equipment",
        values = { "moon_mtg_equip" },
        tags = "basic,counter",
        visible = false,
        visible_in_hand = 0,
        funcOwner = self,
        activateFunc = "",
    }

    enc.registerValue {
        valueID = "moon_mtg_equip",
        validType = "nil",
        desc = "who up describing they values (when are these ever used)",
        default = {},
    }
end

local function init_card(card)
    if card == nil or card.tag ~= "Card" then return end
    if card.getVar("noencode") == true then return end

    local enc = encoder()
    if enc == nil then return end

    if not enc.objectExists { obj = card } then
        enc.encodeObject { obj = card }
    end
    if not enc.propertyExists { propID = prop_id } then return end

    if not enc.objIsPropEnabled { obj = card, propID = prop_id } then
        enc.objEnableProp { obj = card, propID = prop_id }
        enc.rebuildButtons { obj = card }
    end
end

local function equipped_offset(i)
    local col = math.floor(i / 3)
    local row = i % 3
    return Vector(-1.65 - 1.15 * col, 0.05 + row * (-0.05 / 3),
                  -0.75 + row * (2.2 / 3))
end

local function equip_to(deck, to)
    local enc = encoder()
    if enc == nil then return end

    local data = enc.objGetPropData { obj = to, propID = prop_id }
    local angles = to.getRotation()

    while deck ~= nil and (deck.tag == "Card" or #deck.getObjects() > 0) do
        local card
        if deck.tag == "Card" then
            card = deck
            deck = nil
        else
            card = deck.takeObject {
                position = deck.getPosition(),
                top = true,
                smooth = false,
            }
            deck = deck.remainder or deck
        end

        card.setPosition(to.positionToWorld(equipped_offset(#data.moon_mtg_equip)))
        card.setRotation(angles, false, false)
        card.setScale({0.475, 0.475, 0.475})
        card.locked = true
        to.addAttachment(card)
        table.insert(data.moon_mtg_equip, #to.getAttachments())
    end

    enc.objSetPropData { obj = to, propID = prop_id, data = data }
end

-- This is the exact same equip action, invoked by a hover button.
function equip_hovered_deck(deck, player_color, alt_click)
    if deck == nil or deck.tag ~= "Deck" then return end
    if deck_is_excluded(deck) then
        printToColor("Equipment disabled for Exile, Library and Graveyard.",
                     player_color, {1, 0.7, 0.2})
        return
    end

    local card = deck.takeObject {
        position = deck.getPosition() + Vector(0, 1, 0),
        top = true,
    }
    if card == nil then return end
    local remaining = deck.remainder or deck

    init_card(card)
    equip_to(remaining, card)
end

-- A specific classic UI button CAN be removed safely by index.
-- Other scripted buttons and all context-menu items are preserved.
local function find_equip_button(deck)
    for _, b in ipairs(deck.getButtons() or {}) do
        if b.tooltip == BUTTON_MARKER then return b.index end
    end
    return nil
end

local function remove_equip_button(deck)
    local index = find_equip_button(deck)
    if index ~= nil then deck.removeButton(index) end
end

local function is_hovered(guid)
    for _, other_guid in pairs(hovered) do
        if other_guid == guid then return true end
    end
    return false
end

local function refresh_deck(deck)
    if deck == nil or deck.tag ~= "Deck" then return end

    if not is_hovered(deck.getGUID()) or deck_is_excluded(deck) then
        remove_equip_button(deck)
        return
    end

    if find_equip_button(deck) ~= nil then return end
    deck.createButton {
        click_function = "equip_hovered_deck",
        function_owner = self,
        label = EQUIP_BUTTON_STYLE.label,
        tooltip = BUTTON_MARKER,
        position = EQUIP_BUTTON_STYLE.position,
        rotation = {0, 0, 0},
        scale = EQUIP_BUTTON_STYLE.scale,
        width = EQUIP_BUTTON_STYLE.width,
        height = EQUIP_BUTTON_STYLE.height,
        font_size = EQUIP_BUTTON_STYLE.font_size,
        font_color = EQUIP_BUTTON_STYLE.font_color,
        color = EQUIP_BUTTON_STYLE.color,
        hover_color = EQUIP_BUTTON_STYLE.hover_color,
        press_color = EQUIP_BUTTON_STYLE.press_color,
    }
end

local function refresh_deck_later(deck)
    if deck == nil or deck.tag ~= "Deck" then return end
    local guid = deck.getGUID()
    Wait.frames(function()
        local current = getObjectFromGUID(guid)
        if current ~= nil then refresh_deck(current) end
    end, 2)
end

-- Encoder button (for equipped cards) -----------------------------------
-- Leave Encoder responsible for equipment data and button rebuilds.
-- Only toggle this one button using the same hover state as EQUIP ALL.
local function find_unequip_button(card)
    for _, b in ipairs(card.getButtons() or {}) do
        if b.click_function == "unequip_all" and b.tooltip == "unequip all" then
            return b.index
        end
    end
    return nil
end

local function remove_unequip_button(card)
    local index = find_unequip_button(card)
    if index ~= nil then card.removeButton(index) end
end

local function refresh_equipped_card(card)
    if card == nil or card.tag ~= "Card" then return end
    if not is_hovered(card.getGUID()) then
        remove_unequip_button(card)
        return
    end
    if find_unequip_button(card) ~= nil then return end

    local enc = encoder()
    if enc == nil then return end
    -- Hover events also fire on unencoded cards. Never query property data
    -- until Encoder confirms this card has the equipment property enabled.
    if not enc.objectExists { obj = card } then return end
    if not enc.propertyExists { propID = prop_id } then return end
    if not enc.objIsPropEnabled { obj = card, propID = prop_id } then return end

    local flip = enc.getFlip { obj = card } or 1
    if flip == -1 then return end
    local equipped = enc.objGetPropData { obj = card, propID = prop_id }
    if type(equipped) ~= "table" or type(equipped.moon_mtg_equip) ~= "table"
        or #equipped.moon_mtg_equip == 0 then return end

    card.createButton {
        label = "unequip all",
        position = {0, 0.28, 0},
        rotation = {0, 0, 0},
        scale = {0.5, 0.5, 0.5},
        width = 800,
        height = 300,
        font_size = 125,
        font_color = {1, 1, 1},
        color = {0.1, 0.1, 0.1},
        tooltip = "unequip all",
        click_function = "unequip_all",
        function_owner = self,
    }
end

-- Encoder calls this during its button rebuilds. It must not create an
-- UNEQUIP ALL button unless the card is currently being hovered.
function createButtons(params)
    if params == nil then return end
    refresh_equipped_card(params.obj)
end

-- Check only hovered objects for missing buttons after a rebuild or move.
-- This avoids scanning/encoding every card and preserves deck tag checks.
local function refresh_hovered_decks()
    local seen = {}
    for _, guid in pairs(hovered) do
        if not seen[guid] then
            seen[guid] = true
            local obj = getObjectFromGUID(guid)
            if obj ~= nil then
                if obj.tag == "Deck" then
                    refresh_deck(obj)
                elseif obj.tag == "Card" then
                    refresh_equipped_card(obj)
                end
            end
        end
    end
    Wait.time(refresh_hovered_decks, 0.5)
end

function unequip_all(obj, ply)
    local enc = encoder()
    if enc == nil then return end

    local equipped = enc.objGetPropData { obj = obj, propID = prop_id }
    if #equipped.moon_mtg_equip == 0 then return end

    local origin = obj.getPosition()
    obj.setPosition(origin + Vector(0, #equipped.moon_mtg_equip + 1, 0))

    for i = #equipped.moon_mtg_equip, 1, -1 do
        local new = obj.removeAttachment(equipped.moon_mtg_equip[i] - 1)
        new.setPosition(origin + Vector(0, #equipped.moon_mtg_equip - i + 1, 0))
        new.setScale({1, 1, 1})
        new.locked = false
    end

    enc.objSetPropData {
        obj = obj,
        propID = prop_id,
        data = { moon_mtg_equip = {} },
    }
    remove_unequip_button(obj)
end

-- Events -----------------------------------------------------------------
function Equipment.load()
    self.addContextMenuItem("Register Module", register_module)
    Wait.condition(register_module, function()
        return Global.getVar("Encoder") ~= nil
    end, 30)

    -- Clean only this module's old buttons, never other mods' buttons/menus.
    Wait.frames(function()
        collect_protected_snap_points()
        for _, obj in ipairs(getObjects()) do
            if obj.tag == "Deck" then
                remove_equip_button(obj)
            elseif obj.tag == "Card" then
                remove_unequip_button(obj)
            end
        end
        refresh_hovered_decks()
    end, 10)
end

function Equipment.onHover(player_color, obj)
    local old_guid = hovered[player_color]
    local new_guid = (obj ~= nil and (obj.tag == "Deck" or obj.tag == "Card"))
                     and obj.getGUID() or nil

    hovered[player_color] = new_guid

    if old_guid ~= nil and old_guid ~= new_guid
        and not is_hovered(old_guid) then
        local previous = getObjectFromGUID(old_guid)
        if previous ~= nil then
            if previous.tag == "Deck" then
                remove_equip_button(previous)
            elseif previous.tag == "Card" then
                remove_unequip_button(previous)
            end
        end
    end

    if new_guid ~= nil then
        if obj.tag == "Deck" then
            refresh_deck(obj)
        else
            refresh_equipped_card(obj)
        end
    end
end

function Equipment.onDrop(player_color, obj)
    if obj == nil then return end
    local ok, guid, kind = pcall(function()
        return obj.getGUID(), obj.tag
    end)
    if not ok or not guid or (kind ~= "Deck" and kind ~= "Card") then return end

    -- Multiple loose cards dropped on a library are consumed by TTS while
    -- merging. Avoid sending a destroyed Card reference to Encoder.
    Wait.frames(function()
        local current = getObjectFromGUID(guid)
        if current == nil or current.isDestroyed() then return end
        if current.tag == "Card" then
            init_card(current)
            refresh_equipped_card(current)
        elseif current.tag == "Deck" then
            refresh_deck(current)
        end
    end, 2)
end

function Equipment.onEnterZone(zone, obj)
    if obj ~= nil and obj.tag == "Deck" then refresh_deck_later(obj) end
end

function Equipment.onLeaveZone(zone, obj)
    if obj ~= nil and obj.tag == "Deck" then refresh_deck_later(obj) end
end

function Equipment.onSpawn(obj)
    if obj ~= nil and obj.tag == "Deck" then refresh_deck_later(obj) end
end


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

-- =============================================================
-- MODULE 7: COMBAT TARGETING (TWO HOTKEYS: DRAW / TAP-UNDO, HOLD-CLEAR)
--
-- TTS does not let Lua assign C (or any default key) programmatically.
-- Players bind "MTG: Declare Combat Target" to C in Options > Game Keys.
-- DRAW: hold over the starting card and release over the destination card.
-- UNDO: tap to remove latest arrow; hold for your chosen duration to clear all.
-- Holding never performs the short-press undo.
-- Arrows are visual-only and session-only; no MTG rules are enforced.
-- =============================================================

Combat = {
    HOTKEY = "MTG: Declare Combat Target",
    UNDO_HOTKEY = "MTG: Undo Combat Target",
    DEFAULT_UNDO_HOLD_SECONDS = 5.0,
    OWNERS = {White = true, Red = true, Yellow = true, Blue = true},
    COLOR = {
        White = {0.95, 0.94, 0.83},
        Red = {0.96, 0.33, 0.27},
        Yellow = {1.0, 0.83, 0.19},
        Blue = {0.30, 0.64, 1.0}
    },
    pending = {}, -- color -> starting card GUID during DRAW
    history = {}, -- color -> created pairs in order
    undoHeld = {}, -- color -> pending short/long press token
    links = {},   -- starting GUID -> {defenders = { [destinationGUID] = ownerColor }, by = color} (historic keys)
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

-- Each start card can point to multiple destinations, and each destination
-- can receive multiple arrows. No attacker/defender role is inferred.
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
-- Each destination stores the color of the player who added the arrow.
-- Legacy attacker/defender fields now simply mean start/destination.
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
    Combat.undoHeld[color] = nil -- cancel a pending hold when clearing via UI/disable
    Combat.history[color] = {}
    local changed = false
    for attackerGUID, link in pairs(Combat.links) do
        for defenderGUID, owner in pairs(link.defenders) do
            if owner == color or (owner == true and link.by == color) then
                link.defenders[defenderGUID] = nil
                if TargetRegistry and TargetRegistry.onArrowRemoved then
                    TargetRegistry.onArrowRemoved(color, attackerGUID, defenderGUID)
                end
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
    local startGUID = Combat.pending[color]
    Combat.pending[color] = nil
    if not Combat.enabled(color) or not startGUID
        or not combatCard(getObjectFromGUID(startGUID))
        or not combatCard(hovered) then return end
    local endGUID = hovered.getGUID()
    -- Direct the arrow from key-down card to key-up card, without combat roles.
    if endGUID ~= startGUID then
        Combat.addDefender(startGUID, endGUID, color)
        -- A deliberate gesture during an explicit selection assigns a target,
        -- even when the visual arrow already existed. Ordinary arrows stay visual.
        if TargetRegistry and TargetRegistry.onDraw then
            TargetRegistry.onDraw(color, startGUID, endGUID)
        end
    end
end

-- Removing a single arrow requires an entirely separate key gesture.
-- Ownership is checked on the exact attacker/defender pair.
function Combat.removePair(attacker, defender, color)
    local link = Combat.links[attacker]
    if not link or link.defenders[defender] ~= color then return false end
    link.defenders[defender] = nil
    if TargetRegistry and TargetRegistry.onArrowRemoved then
        TargetRegistry.onArrowRemoved(color, attacker, defender)
    end
    if next(link.defenders) == nil then Combat.links[attacker] = nil end
    Combat.updated()
    return true
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

-- A short press triggers on release. A continuous configurable hold clears
-- only the holding player's arrows, and suppresses the short-press undo.
-- Each hold has a unique table token so stale timers cannot clear later.
function Combat.undoHotkey(color, hovered, pointerPosition, isKeyUp)
    if not Combat.OWNERS[color] then return end

    if isKeyUp then
        local held = Combat.undoHeld[color]
        Combat.undoHeld[color] = nil -- cancels an outstanding timer
        if held == nil or held.cleared then return end
        Combat.undo(color)
        return
    end

    -- A completed long hold retains a sentinel until key-up. This blocks
    -- keyboard-repeat key-down events from starting another hold.
    if not Combat.enabled(color) or Combat.undoHeld[color] ~= nil then return end
    local held = {cleared = false}
    Combat.undoHeld[color] = held
    local seconds = Combat.DEFAULT_UNDO_HOLD_SECONDS
    if Settings.getUndoHold then seconds = Settings.getUndoHold(color) end
    Wait.time(function()
        if Combat.undoHeld[color] ~= held then return end
        if not Combat.enabled(color) then
            Combat.undoHeld[color] = nil
            return
        end
        Combat.clear(color) -- removes this player's arrows and history
        Combat.undoHeld[color] = {cleared = true} -- suppress undo until release
    end, seconds)
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
    Combat.undoHeld = {}
    Combat.history = {}
    Combat.links = {}
    Combat.baseLines = self.getVectorLines() or {}
    Combat.loopActive = false
    Combat.loopGeneration = 0
    -- TTS has no removeHotkey(label). Older registrations can remain in the
    -- Game Keys menu after Save & Play, so reset the custom registry before
    -- declaring the current two actions. Native controls are unaffected.
    -- This table currently uses addHotkey only for Lotus combat shortcuts.
    clearHotkeys()
    addHotkey(Combat.HOTKEY, Combat.hotkey, true)
    addHotkey(Combat.UNDO_HOTKEY, Combat.undoHotkey, true)
    -- TTS may restore old spawned anchors when loading a saved table.
    -- Clean them after all objects have spawned.
    Wait.frames(Combat.cleanupLegacyFight, 30)
end
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
        sourceName = record.sourceGUID and targetName(getObjectFromGUID(record.sourceGUID))
            or "(waiting for first arrow)",
        sourceValid = record.sourceGUID ~= nil
            and targetCard(getObjectFromGUID(record.sourceGUID)) or false,
        count = #values, targets = values
    }
end

-- Source discovery for chat-driven sessions: a hovered arrow DESTINATION
-- is not necessarily its source. Prefer outgoing arrows from the hovered
-- card, otherwise search inbound arrows newest-first in this player's history.
-- Only links owned by the requesting seat can become that seat's targets.
local function targetOwnedArrow(color, sourceGUID, destinationGUID)
    local link = Combat.links[sourceGUID]
    return link ~= nil and link.defenders ~= nil
        and link.defenders[destinationGUID] == color
        and targetCard(getObjectFromGUID(sourceGUID))
        and targetCard(getObjectFromGUID(destinationGUID))
end

local function targetSourceForHint(color, hintGUID)
    if type(hintGUID) ~= "string"
        or not targetCard(getObjectFromGUID(hintGUID)) then return nil end
    for _, pair in ipairs(Combat.history[color] or {}) do
        if pair.attacker == hintGUID
            and targetOwnedArrow(color, pair.attacker, pair.defender) then
            return hintGUID
        end
    end
    local history = Combat.history[color] or {}
    for i = #history, 1, -1 do
        local pair = history[i]
        if pair.defender == hintGUID
            and targetOwnedArrow(color, pair.attacker, pair.defender) then
            return pair.attacker
        end
    end
    return nil
end

local function targetSeedExisting(record)
    for _, pair in ipairs(Combat.history[record.color] or {}) do
        if #record.targets >= TargetRegistry.MAX_TARGETS then break end
        if pair.attacker == record.sourceGUID
            and not record.index[pair.defender]
            and targetOwnedArrow(record.color, pair.attacker, pair.defender) then
            record.targets[#record.targets + 1] = pair.defender
            record.index[pair.defender] = true
        end
    end
end

function TargetRegistry.begin(params)
    local color = type(params) == "table" and params.color or nil
    local explicitSource = type(params) == "table" and params.sourceGUID or nil
    local hintGUID = type(params) == "table" and params.hintGUID or nil
    if not Combat.OWNERS[color] or not Combat.enabled(color) then
        return {status = "invalid", reason = "targeting disabled or invalid seat"}
    end
    if TargetRegistry.active[color] then
        local snapshot = targetSnapshot(TargetRegistry.active[color], "active")
        snapshot.alreadyActive = true
        return snapshot
    end
    if explicitSource ~= nil
        and (type(explicitSource) ~= "string"
            or not targetCard(getObjectFromGUID(explicitSource))) then
        return {status = "invalid", reason = "source must be a live card"}
    end
    local selectedSource = explicitSource or targetSourceForHint(color, hintGUID)
    TargetRegistry.sequence = TargetRegistry.sequence + 1
    local record = {
        id = "target-" .. tostring(TargetRegistry.sequence),
        color = color, sourceGUID = selectedSource,
        targets = {}, index = {}
    }
    -- When invoked from chat after drawing the arrows, capture those arrows
    -- immediately. Explicit API sessions start empty for callers to control.
    if explicitSource == nil and selectedSource ~= nil then
        targetSeedExisting(record)
    end
    TargetRegistry.active[color] = record
    return targetSnapshot(record, "active")
end

-- Called only after a deliberate successful key-down/source, key-up/destination
-- gesture. This also allows the user to select a pre-existing visual arrow.
function TargetRegistry.onDraw(color, sourceGUID, destinationGUID)
    local record = TargetRegistry.active[color]
    if record == nil or not targetCard(getObjectFromGUID(sourceGUID)) then
        return false
    end
    -- First arrow chooses the source. Hovering a target while typing the
    -- command can no longer accidentally pin the wrong source.
    if record.sourceGUID == nil then record.sourceGUID = sourceGUID end
    if record.sourceGUID ~= sourceGUID then
        targetTell(color, "Ignored arrow from " ..
            targetName(getObjectFromGUID(sourceGUID)) ..
            ". Current source is " ..
            targetName(getObjectFromGUID(record.sourceGUID)) .. ".")
        return false
    end
    if sourceGUID == destinationGUID or record.index[destinationGUID]
        or #record.targets >= TargetRegistry.MAX_TARGETS
        or not targetCard(getObjectFromGUID(destinationGUID)) then return false end
    record.targets[#record.targets + 1] = destinationGUID
    record.index[destinationGUID] = true
    targetTell(color, "Target " .. tostring(#record.targets) .. ": " ..
        targetName(getObjectFromGUID(destinationGUID)) ..
        " (source: " .. targetName(getObjectFromGUID(sourceGUID)) .. ")")
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
    if #record.targets == 0 then
        return {status = "invalid",
            reason = "No targets selected. Draw a source-to-target arrow first."}
    end
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
        " | source: " .. tostring(result.sourceName) ..
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
        ["mtg targets"] = true, ["mtg state"] = true, ["mtg help"] = true
    }
    if not recognized[command] then return nil end
    local color = player.color
    if not Combat.OWNERS[color] then return false end
    if command == "mtg help" then
        targetTell(color, "mtg inspect = remote card catalog; mtg state = Encoder stats; " ..
            "mtg target = capture arrows, mtg targets = view, " ..
            "mtg done = commit, mtg cancel = discard draft.")
    elseif command == "mtg state" then
        local guid = TargetRegistry.hovered[color]
        if not guid then
            targetTell(color, "Hover over a face-up card first.")
        else
            local ok, state = pcall(function()
                return Global.call("mtgCardState", {guid=guid})
            end)
            if not ok or type(state)~="table" or state.status~="ready" then
                targetTell(color, "Card state unavailable (face-down or invalid).")
            else
                local p = state.currentPower
                local t = state.currentToughness
                local pt = (p~=nil and tostring(p) or "?") ..
                    "/" .. (t~=nil and tostring(t) or "?")
                targetTell(color, tostring(state.name) ..
                    " | owner " .. tostring(state.owner or "?") ..
                    " | controller " .. tostring(state.controller or "?") ..
                    " | zone " .. tostring(state.zone or "?") ..
                    " (" .. tostring(state.zoneColor or "-") .. ")")
                targetTell(color, "P/T " .. pt ..
                    " (" .. tostring(state.powerToughnessSource or "unknown") ..
                    "; layers unverified), tapped=" .. tostring(state.tapped) ..
                    ", ready=" .. tostring(state.controlReady) ..
                    ", damage=" .. tostring(state.damageMarked))
                local counters = type(state.counters)=="table" and state.counters or {}
                local shown = {}
                for _, key in ipairs({"plusOnePlusOne","named","stun","time","generic"}) do
                    if counters[key]~=nil then
                        shown[#shown+1]=key .. "=" .. tostring(counters[key])
                    end
                end
                targetTell(color, "Counters: " ..
                    (#shown>0 and table.concat(shown,", ") or "none encoded"))
                local keywords = {}
                for name, val in pairs(state.encodedKeywords or {}) do
                    if val and val~=0 then keywords[#keywords+1]=name end
                end
                table.sort(keywords)
                targetTell(color,"Encoded keywords: " ..
                    (#keywords>0 and table.concat(keywords,", ") or "none"))
            end
        end
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
            color = color, hintGUID = TargetRegistry.hovered[color]
        })
        if result.status == "active" and result.alreadyActive then
            targetTell(color, "Selection " .. tostring(result.id) ..
                " is already active: " .. tostring(result.count) ..
                " target(s). Continue drawing, then type mtg done.")
        elseif result.status == "active" and result.sourceGUID ~= nil then
            targetTell(color, "Captured " .. tostring(result.count) ..
                " existing arrow target(s) for " .. result.sourceName ..
                ". Draw more arrows from that card or type mtg done.")
        elseif result.status == "active" then
            targetTell(color, "Target capture ready. Draw FIRST arrow from " ..
                "your source card to a target; draw more from the SAME source. " ..
                "Type mtg targets to check, then mtg done.")
        else
            targetTell(color, result.reason or "Could not start target selection.")
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
-- =============================================================
-- SHARED EVENT DISPATCHER (6 MODULES)
-- =============================================================

function onLoad(savedData)
    Playmats.load(savedData)
    Wait.frames(Playmats.alignExisting, 30)
    Settings.load(savedData)
    Preview.load(savedData)
    DrawRandom.load()
    Equipment.load()
    RevealTop.load(savedData)
    Combat.load()
    TargetRegistry.load()
    -- Deferred until Global and the other script objects have loaded.
    Wait.frames(Settings.ready, 20)
    log("MTG Portable Helper: Playmat module ready.")
end

function onSave()
    return Playmats.save()
end

function onChat(message, player)
    local targetResult = TargetRegistry.onChat(message, player)
    if targetResult ~= nil then return targetResult end
    local rtResult = RevealTop.onChat(message, player)
    if rtResult ~= nil then return rtResult end
    return Playmats.onChat(message, player)
end

function onObjectEnterZone(zone, obj)
    Preview.onEnterZone(zone, obj)
    DrawRandom.onEnterZone(zone, obj)
    Equipment.onEnterZone(zone, obj)
end

function onObjectPickUp(playerColor, obj)
    Preview.onPickUp(playerColor, obj)
end

function onObjectDrop(playerColor, obj)
    Preview.onDrop(playerColor, obj)
    Equipment.onDrop(playerColor, obj)
end

function onObjectDestroy(obj)
    DrawRandom.onDestroy(obj)
    RevealTop.onDestroy(obj)
    Combat.onDestroy(obj)
    TargetRegistry.onDestroy(obj)
end

function onObjectHover(playerColor, obj)
    Equipment.onHover(playerColor, obj)
    TargetRegistry.onHover(playerColor, obj)
end

function onObjectLeaveZone(zone, obj)
    Preview.onLeaveZone(zone, obj)
    Equipment.onLeaveZone(zone, obj)
end

function onObjectSpawn(obj)
    Equipment.onSpawn(obj)
    RevealTop.onSpawn(obj)
end

-- Public methods retained for compatibility with other table scripts.
function setPreviewPreferences(params)
    Preview.setPreferences(params)
end

function getPreviewPreferences()
    return Settings.getPreviewPreferences()
end

function applyPreviewSettings()
    Settings.applyPreview()
end

-- Optional host-side tracing (TTS console):
-- getObjectFromGUID("185063").call("previewDebug", {enabled=true})
function previewDebug(params)
    Preview.DEBUG = type(params) == "table" and params.enabled == true
    print("MTG Preview diagnostics " .. (Preview.DEBUG and "enabled" or "disabled"))
    return Preview.DEBUG
end

function applyAll()
    Settings.applyAll(true)
end

-- Object button callback (playerColor is a string)
function settingsButtonClick(obj, playerColor, alt)
    Settings.open(obj, playerColor)
end

-- Global XML UI callbacks (player may be a Player object)
function closeCounterSettings(player, value, id)
    Settings.close(player)
end

function counterToggle(player, value, id)
    Settings.toggle(player, value, id)
end

function allMeToggle(player, value, id)
    Settings.toggleAllMe(player, value)
end

function allEveryoneToggle(player, value, id)
    Settings.toggleAllEveryone(player, value)
end

function previewToggle(player, value, id)
    Settings.togglePreview(player, value, id)
end

function settingsPreviewSizeChanged(player, value, id)
    Settings.changePreviewSize(player, value, id)
end

-- Global XML: tab navigation. Notebook patch notes are read-only.
function settingsSelectTab(player, value, id)
    Settings.selectTab(player, value, id)
end

-- Personal on-screen shortcut overlay switch in General Settings.
function settingsGeneralToggle(player, value, id)
    Settings.toggleGeneral(player, value, id)
end

-- TTS shows the local Game Keys dialog with no arguments.
function settingsCombatKeyConfig(player, value, id)
    local color = Settings.playerColor(player)
    if not Settings.validColor(color) or color ~= Settings.menuOwner then return end
    local ok = pcall(function() showHotkeyConfig() end)
    if not ok then
        printToColor("Open Options > Game Keys and bind MTG: Declare and Undo Combat Target.",
            color, {0.90, 0.75, 0.45})
    end
end

-- Per-seat slider callback for the Undo long-press threshold.
function settingsCombatHoldChanged(player, value, id)
    Settings.changeUndoHold(player, value, id)
end

-- Global XML: navigate read-only patch notes release pages.
function settingsNotesNavigate(player, value, id)
    Settings.navigateNotes(player, value, id)
end

-- Explicit target-selection API (no MTG legality / spell resolution).
function mtgBeginTargetSelection(params)
    return TargetRegistry.begin(params)
end

function mtgReadTargetSelection(params)
    return TargetRegistry.read(params)
end

function mtgFinishTargetSelection(params)
    return TargetRegistry.finish(params)
end

function mtgCancelTargetSelection(params)
    return TargetRegistry.cancel(params)
end
