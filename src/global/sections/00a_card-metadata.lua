-- SHARED CARD METADATA | on-demand, read-only, bounded
-- Public: Global.call("mtgCardMetadata", {guid = card.getGUID()})
-- Optional: Global.call("mtgInvalidateCardMetadata", {guid = guid})
-- Unknown data stays nil. Never mutates cards, Encoder, or hidden objects.
local mtgMetadataCache = {}
local mtgMetadataCount = 0
local MTG_METADATA_MAX = 1024
local mtgMetadataTypes = {
    artifact = true, creature = true, enchantment = true, instant = true,
    sorcery = true, land = true, planeswalker = true, battle = true,
    kindred = true, tribal = true
}
local mtgMetadataSupertypes = {
    basic = true, legendary = true, snow = true, world = true, ongoing = true
}
local mtgMetadataBasicLands = {
    plains = true, island = true, swamp = true, mountain = true,
    forest = true, wastes = true,
    ["snow-covered plains"] = true, ["snow-covered island"] = true,
    ["snow-covered swamp"] = true, ["snow-covered mountain"] = true,
    ["snow-covered forest"] = true
}

function mtgInvalidateCardMetadata(params)
    local guid = type(params) == "table" and params.guid or params
    if type(guid) ~= "string" then return end
    if mtgMetadataCache[guid] ~= nil then
        mtgMetadataCache[guid] = nil
        mtgMetadataCount = math.max(0, mtgMetadataCount - 1)
    end
end

local function mtgMetadataTypesFromLine(line)
    if type(line) ~= "string" then return nil end
    line = line:lower():gsub("^%s*card%s+type%s*:%s*", "")
        :gsub("^%s*type%s*:%s*", "")
        :gsub("%s*%d+%s*cmc%s*$", "")
    local cut = line:find("—", 1, true) or line:find("–", 1, true)
        or line:find("%s+%-%s+")
    if cut then line = line:sub(1, cut - 1) end
    local found, seen = {}, {}
    for word in line:gmatch("[%a]+") do
        if mtgMetadataTypes[word] then
            if not seen[word] then found[#found + 1] = word; seen[word] = true end
        elseif not mtgMetadataSupertypes[word] then
            return nil
        end
    end
    return #found > 0 and found or nil
end

-- One-line imports may append type words immediately before their CMC.
local function mtgMetadataInlineTypes(name)
    if not name:lower():match("%d+%s*cmc%s*$") then return nil end
    local head = name:lower():gsub("%s*%d+%s*cmc%s*$", "")
    local cut = head:find("—", 1, true) or head:find("–", 1, true)
        or head:find("%s+%-%s+")
    if cut then head = head:sub(1, cut - 1) end
    local words, types, seen = {}, {}, {}
    for word in head:gmatch("[%a]+") do words[#words + 1] = word end
    for i = #words, 1, -1 do
        local word = words[i]
        if mtgMetadataTypes[word] then
            if not seen[word] then table.insert(types, 1, word); seen[word] = true end
        elseif not mtgMetadataSupertypes[word] then break end
    end
    return #types > 0 and types or nil
end

local function mtgMetadataHasType(types, wanted)
    if type(types) ~= "table" then return false end
    for _, word in ipairs(types) do if word == wanted then return true end end
    return false
end

-- GUID identifies this TTS object, not the underlying printed MTG card.
function mtgCardMetadata(params)
    local guid = type(params) == "table" and params.guid or params
    if type(guid) ~= "string" or guid == "" then return nil end
    local obj = getObjectFromGUID(guid)
    if obj == nil or obj.type ~= "Card" then
        mtgInvalidateCardMetadata(guid)
        return nil
    end

    local nameRaw = tostring(obj.getName() or "")
    local descRaw = tostring(obj.getDescription() or "")
    local notesRaw = tostring(obj.getGMNotes() or "")
    local tagLand = obj.hasTag("MTG_Land") or obj.hasTag("Land")
    local tagNonLand = obj.hasTag("MTG_NonLand")
    local old = mtgMetadataCache[guid]
    if old and old.nameRaw == nameRaw and old.descRaw == descRaw
        and old.notesRaw == notesRaw and old.tagLand == tagLand
        and old.tagNonLand == tagNonLand then
        return old.value
    end

    local name = (nameRaw:match("^([^\r\n]*)") or "")
        :gsub("^%s+", ""):gsub("%s+$", "")
    local typeLine = nameRaw:match("[\r\n]+([^\r\n]+)")
    local notes = {}
    if notesRaw:match("^%s*{") then
        local ok, value = pcall(JSON.decode, notesRaw)
        if ok and type(value) == "table" then notes = value end
    end
    local nested = type(notes.card) == "table" and notes.card or {}
    local notesType = notes.type_line or notes.typeLine
        or nested.type_line or nested.typeLine
    local types = mtgMetadataTypesFromLine(typeLine)
        or mtgMetadataTypesFromLine(notesType)
    if types == nil then
        types = mtgMetadataTypesFromLine(descRaw:match("^([^\r\n]+)"))
    end
    if types == nil and typeLine == nil then
        types = mtgMetadataInlineTypes(nameRaw)
    end
    if types == nil and mtgMetadataBasicLands[name:lower()] then
        types = {"land"}
    end

    local isLand = nil
    if types ~= nil then isLand = mtgMetadataHasType(types, "land") end
    if tagLand then isLand = true end
    if tagNonLand then isLand = false end

    local numeric = nameRaw:lower():match("(%d+)%s*cmc")
        or nameRaw:lower():match("cmc%s*(%d+)")
        or descRaw:lower():match("(%d+)%s*cmc")
        or descRaw:lower():match("cmc%s*(%d+)")
    local manaValue = tonumber(numeric)
    if manaValue == nil then
        manaValue = tonumber(notes.cmc or notes.mana_value
            or nested.cmc or nested.mana_value)
    end
    if manaValue == nil and isLand == true then manaValue = 0 end

    local owner = notes.owner or nested.owner
    if type(owner) ~= "string" then owner = nil end
    local value = {
        guid = guid, name = name, rawName = nameRaw,
        typeLine = typeLine or notesType,
        types = types, isLand = isLand, manaValue = manaValue,
        owner = owner,
        scryfallId = notes.scryfall_id or notes.scryfallId
            or nested.scryfall_id or nested.scryfallId,
        oracleId = notes.oracle_id or notes.oracleId
            or nested.oracle_id or nested.oracleId
    }
    if mtgMetadataCache[guid] == nil then
        if mtgMetadataCount >= MTG_METADATA_MAX then
            -- Bounded reset prevents stale destroyed GUIDs accumulating forever.
            mtgMetadataCache = {}
            mtgMetadataCount = 0
        end
        mtgMetadataCount = mtgMetadataCount + 1
    end
    mtgMetadataCache[guid] = {
        nameRaw = nameRaw, descRaw = descRaw, notesRaw = notesRaw,
        tagLand = tagLand, tagNonLand = tagNonLand, value = value
    }
    return value
end

