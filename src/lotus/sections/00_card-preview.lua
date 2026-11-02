--[[==========================================================================
    MTG LOTUS HELPER  |  v1.4.5  |  Tabletop Simulator Object Script

    MODULES
      1. Card Preview  - Hand plays and first CommanderZone battlefield entry
      2. Playmats      - Personal artwork via "playmat <URL>" / "playmat none"
      3. Draw Random   - Draw a random card from tagged Library/GY/Exile decks
      4. EDH Settings  - Counter visibility, personal preview options, UI
      5. Equipment     - Encoder equipment with hover-only Equip/Unequip buttons
      6. Reveal Top    - Non-interactive visual clone above each library



==========================================================================]]

local HELPER_NAME = "MTG Lotus Helper"
local HELPER_VERSION = "1.4.5"

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

function Preview.createDisplay()
    local xml = UI.getXmlTable() or {}
    for _, element in ipairs(xml) do
        if element.attributes and element.attributes.id == "MTG_CastDisplay" then
            return
        end
    end

    table.insert(xml, {
        tag = "Panel",
        attributes = {
            id = "MTG_CastDisplay",
            width = "400",
            height = "560",
            rectAlignment = "MiddleRight",
            offsetXY = "-50 0",
            active = "false",
            color = "rgba(0,0,0,0.85)",
            outline = "White",
            outlineSize = "2 2",
            ignoreLayout = "true"
        },
        children = {{
            tag = "Image",
            attributes = {
                id = "MTG_CastImage",
                width = "380",
                height = "540",
                preserveAspect = "true"
            }
        }}
    })

    UI.setXmlTable(xml)
end

-- All preferences belong to the VIEWER, not to the player casting a card.
-- MY CARDS means cards dropped by the viewer; OPPONENTS' CARDS means
-- cards dropped by anyone else. A player's choices NEVER affect another
-- player's view of those cards.
-- TTS treats empty UI visibility as 'everyone', so we must keep the
-- display inactive when no viewers qualify.
function Preview.updateVisibility(isLand)
    if isLand == nil then isLand = Preview.currentLandStatus end
    local source = Preview.currentSourceColor
    local visibleTo = {}
    for _, viewer in ipairs(Preview.ALL_UI_COLORS) do
        local ownCard = (source ~= nil and source == viewer)
        local allowed, hideLands
        if Preview.currentPreviewKind == "commander" then
            -- First-entry previews have their own personal switches. They
            -- are independent of ordinary Played Card / Hide Land switches.
            allowed = ownCard
                and Preview.firstCommanderOwnByColor[viewer] ~= false
                or not ownCard
                    and Preview.firstCommanderOpponentsByColor[viewer] ~= false
        else
            if ownCard then
                allowed = Preview.ownEnabledByColor[viewer] ~= false
                hideLands = Preview.hideOwnLandsByColor[viewer] == true
            else
                allowed = Preview.opponentsEnabledByColor[viewer] ~= false
                hideLands = Preview.hideOpponentsLandsByColor[viewer] == true
            end
            -- Hide only cards POSITIVELY identified as lands.
            if isLand == true and hideLands then allowed = false end
        end
        if allowed then table.insert(visibleTo, viewer) end
    end
    Preview.visibleViewerCount = #visibleTo
    UI.setAttribute("MTG_CastDisplay", "visibility",
        #visibleTo > 0 and table.concat(visibleTo, "|") or "Black")
    if Preview.isPreviewActive and Preview.imageReady then
        UI.setAttribute("MTG_CastDisplay", "active",
            #visibleTo > 0 and "true" or "false")
    elseif #visibleTo == 0 then
        UI.setAttribute("MTG_CastDisplay", "active", "false")
    end
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
    if type(own) ~= "table" or type(opponents) ~= "table" then return end

    for _, color in ipairs(Preview.EDH_COLORS) do
        Preview.ownEnabledByColor[color] = own[color] ~= false
        Preview.opponentsEnabledByColor[color] = opponents[color] ~= false
        Preview.hideOwnLandsByColor[color] = hideOwn[color] == true
        Preview.hideOpponentsLandsByColor[color] = hideOpponents[color] == true
        Preview.firstCommanderOwnByColor[color] = commanderOwn[color] ~= false
        Preview.firstCommanderOpponentsByColor[color] =
            commanderOpponents[color] ~= false
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
        Preview.rememberCommanderOrigin(zone, card)
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
    -- Fallback for scripted moves, or when a zone-leave event occurs before
    -- onObjectPickUp. We only act after a subsequent valid battlefield drop.
    Preview.rememberCommanderOrigin(zone, card)
end

function Preview.onEnterZone(zone, obj)
    if obj == nil or obj.tag ~= "Card" then return end
    if zone.type == "Hand" and not obj.hasTag(Preview.HAND_TAG) then
        obj.addTag(Preview.HAND_TAG)
    end
    -- Moving a card back into its CommanderZone cancels an incomplete play.
    if Preview.commanderZoneOwner(zone) ~= nil then
        Preview.commanderPending[obj.getGUID()] = nil
    end
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
    UI.setAttribute("MTG_CastDisplay", "active", "false")
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

    local assetName = "MTG_CAST_PREVIEW"
    local assets = UI.getCustomAssets() or {}
    for i = #assets, 1, -1 do
        if assets[i].name == assetName then
            table.remove(assets, i)
        end
    end
    table.insert(assets, {name = assetName, url = custom.face})
    UI.setCustomAssets(assets)

    Wait.condition(
        function()
            if previewID ~= Preview.currentPreviewID then return end
            UI.setAttribute("MTG_CastImage", "image", assetName)
            UI.setAttribute("MTG_CastDisplay", "outline", playerColor)
            Preview.imageReady = true
            Preview.isPreviewActive = true
            Preview.updateVisibility()

            Preview.timerID = Wait.time(function()
                if previewID ~= Preview.currentPreviewID then return end
                Preview.isPreviewActive = false
                UI.setAttribute("MTG_CastDisplay", "active", "false")
                Preview.timerID = nil
            end, Preview.DISPLAY_TIME)
        end,
        function()
            return not UI.loading
        end,
        10,
        function()
            if previewID == Preview.currentPreviewID then
                print("MTG Preview: image asset failed to load.")
            end
        end
    )
end

function Preview.onDrop(playerColor, card)
    if card == nil or card.tag ~= "Card" then return end

    local guid = card.getGUID()
    local commanderOwner = guid and Preview.commanderPending[guid] or nil
    if guid ~= nil then Preview.commanderPending[guid] = nil end

    local inHand = false
    for _, zone in ipairs(card.getZones() or {}) do
        if zone.type == "Hand" then
            inHand = true
            break
        end
    end

    if inHand then
        if not card.hasTag(Preview.HAND_TAG) then
            card.addTag(Preview.HAND_TAG)
        end
        return
    end

    local fromHand = card.hasTag(Preview.HAND_TAG)
    if fromHand then card.removeTag(Preview.HAND_TAG) end
    if not fromHand and commanderOwner == nil then return end

    -- Wait for the actual drop position. A CommanderZone pickup that is
    -- merely moved elsewhere must not count as a first battlefield entry.
    Wait.frames(function()
        if card == nil or card.isDestroyed() or card.is_face_down then return end
        if not Preview.isOnBattlefield(card) then return end

        if commanderOwner ~= nil and guid ~= nil
            and not Preview.commanderFirstShown[guid] then
            -- Consume the first entry even when this viewer has the preview
            -- disabled, so toggling it later cannot replay an old event.
            Preview.commanderFirstShown[guid] = true
            Preview.showCard(card, commanderOwner, "commander")
        elseif fromHand then
            Preview.showCard(card, playerColor, "played")
        end
    end, 5)
end

function Preview.load(savedData)
    Preview.commanderPending = {}
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
        UI.setAttribute("MTG_CastDisplay", "active", "false")
        Preview.updateVisibility()
        Preview.loadPreferences()
    end, 12)

    print(HELPER_NAME .. " " .. HELPER_VERSION .. " loaded (Card Preview).")
end

