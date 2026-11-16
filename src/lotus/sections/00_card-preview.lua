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

