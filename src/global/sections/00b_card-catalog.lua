-- CARD CATALOG | on-demand MTGA lookup, Scryfall fallback (4P prototype)
-- Public: Global.call("mtgCardCatalogRequest", {guid="abcdef", color="White"})
--         Global.call("mtgCardCatalogGet", {guid="abcdef"})
-- Data is descriptive only. Never evaluate rules text or write to card scripts.
-- Name-based identity is deliberately provisional: not a printing/face ID.
local MTG_CATALOG_BASE = "https://mtga-card-catalog-wajen.caringgiraffe2.chatgpt.site"
local MTG_CATALOG_MAX_CACHE = 256
local MTG_CATALOG_MAX_WAITING = 24
local MTG_CATALOG_MAX_ACTIVE = 3
local mtgCatalogCache, mtgCatalogOrder = {}, {}
local mtgCatalogQueue, mtgCatalogActive = {}, 0
local mtgCatalogColors = {White=true, Red=true, Yellow=true, Blue=true}

local function mtgCatalogName(raw)
    if type(raw) ~= "string" then return "" end
    return (raw:match("^([^\r\n]*)") or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function mtgCatalogKey(name)
    return name:lower():gsub("%s+", " ")
end

local function mtgCatalogEncode(s)
    return (s:gsub("([^%w%-_%.~])", function(ch)
        return string.format("%%%02X", string.byte(ch))
    end))
end

local function mtgCatalogTell(color, message)
    if mtgCatalogColors[color] then
        printToColor("[MTG Catalog] " .. message, color, {0.75, 0.85, 1})
    end
end

local function mtgCatalogNormalizeMTGA(card)
    if type(card) ~= "table" or type(card.name) ~= "string" then return nil end
    local text = card.rules_text or card.oracle_text or card.text
    if type(text) ~= "string" then text = "" end
    local typ = card.type_line or card.typeLine
    if type(typ) ~= "string" then typ = "" end
    return {
        source = "mtga", name = card.name, typeLine = typ,
        rulesText = text, manaValue = tonumber(card.mana_value or card.cmc),
        power = card.power, toughness = card.toughness,
        arenaId = card.arena_id or card.id,
        -- Metadata is NOT an executable rules representation.
        abilityIds = card.ability_ids
    }
end

local function mtgCatalogCandidates(decoded)
    if type(decoded) ~= "table" then return {} end
    if type(decoded.cards) == "table" then return decoded.cards end
    if type(decoded.results) == "table" then return decoded.results end
    if type(decoded.data) == "table" then
        if type(decoded.data.cards) == "table" then return decoded.data.cards end
        if type(decoded.data.results) == "table" then return decoded.data.results end
        if decoded.data.name then return {decoded.data} end
        if decoded.data[1] then return decoded.data end
    end
    if type(decoded.card) == "table" then return {decoded.card} end
    if decoded.name then return {decoded} end
    if decoded[1] then return decoded end
    return {}
end

local function mtgCatalogParseMTGA(decoded, requestedName)
    local best, bestScore = nil, -1
    for _, card in ipairs(mtgCatalogCandidates(decoded)) do
        if type(card) == "table" and type(card.name) == "string"
            and mtgCatalogKey(card.name) == mtgCatalogKey(requestedName) then
            local score = 0
            if card.is_primary == true or card.is_primary == 1 then score = score + 8 end
            if card.is_rebalanced ~= true and card.is_rebalanced ~= 1 then score = score + 4 end
            if card.is_token ~= true and card.is_token ~= 1 then score = score + 2 end
            if card.is_digital_only ~= true and card.is_digital_only ~= 1 then score = score + 1 end
            if score > bestScore then best, bestScore = card, score end
        end
    end
    return best and mtgCatalogNormalizeMTGA(best) or nil
end

local function mtgCatalogParseScryfall(decoded, requestedName)
    if type(decoded) ~= "table" or type(decoded.name) ~= "string" then return nil end
    if mtgCatalogKey(decoded.name) ~= mtgCatalogKey(requestedName) then return nil end
    local types, rules = decoded.type_line or "", decoded.oracle_text or ""
    if type(decoded.card_faces) == "table" and #decoded.card_faces > 0 then
        local faceTypes, faceRules = {}, {}
        for _, face in ipairs(decoded.card_faces) do
            if type(face.type_line) == "string" then faceTypes[#faceTypes+1] = face.type_line end
            if type(face.oracle_text) == "string" then faceRules[#faceRules+1] = face.oracle_text end
        end
        if types == "" then types = table.concat(faceTypes, " // ") end
        if rules == "" then rules = table.concat(faceRules, " // ") end
    end
    return {
        source = "scryfall", name = decoded.name, typeLine = types,
        rulesText = rules, manaValue = tonumber(decoded.cmc),
        power = decoded.power, toughness = decoded.toughness,
        scryfallId = decoded.id, oracleId = decoded.oracle_id
    }
end

local function mtgCatalogReport(color, entry)
    if not mtgCatalogColors[color] then return end
    if entry.state ~= "ready" then
        mtgCatalogTell(color, "No remote data for " .. entry.name .. " (lookup unavailable).")
        return
    end
    local value = entry.value
    local typ = value.typeLine ~= "" and value.typeLine or "type unknown"
    mtgCatalogTell(color, value.name .. " | " .. typ .. " | " .. value.source)
    if type(value.rulesText) == "string" and value.rulesText ~= "" then
        local preview = value.rulesText:gsub("[\r\n]+", " ")
        if #preview > 220 then preview = preview:sub(1, 217) .. "..." end
        mtgCatalogTell(color, preview)
    end
end

local function mtgCatalogNotify(entry)
    for color in pairs(entry.listeners) do mtgCatalogReport(color, entry) end
    entry.listeners = {}
end

local mtgCatalogPump

local function mtgCatalogLookup(key)
    local entry = mtgCatalogCache[key]
    if not entry or entry.state ~= "pending" then return end
    mtgCatalogActive = mtgCatalogActive + 1
    local completed = false

    local function complete(value)
        if completed then return end
        completed = true
        entry.state = value and "ready" or "miss"
        entry.value = value
        entry.finishedAt = os.time()
        mtgCatalogActive = math.max(0, mtgCatalogActive - 1)
        mtgCatalogNotify(entry)
        mtgCatalogPump()
    end

    local headers = {
        ["User-Agent"] = "MTGA-TTS/1.0 (Tabletop Simulator)",
        ["Accept"] = "application/json"
    }

    local function send(url, callback)
        local answered = false
        local function resolve(payload)
            if answered or completed then return end
            answered = true
            callback(payload)
        end
        local ok = pcall(function()
            WebRequest.custom(url, "GET", true, "", headers, function(resp)
                if resp == nil or resp.is_error or resp.response_code ~= 200
                    or type(resp.text) ~= "string" then
                    resolve(nil)
                    return
                end
                local decodedOK, data = pcall(JSON.decode, resp.text)
                resolve(decodedOK and data or nil)
            end)
        end)
        if not ok then resolve(nil); return end
        -- Ignore late replies. Network errors never stall the lookup queue.
        Wait.time(function() resolve(nil) end, 12)
    end

    local function fallback()
        local url = "https://api.scryfall.com/cards/named?exact="
            .. mtgCatalogEncode(entry.name)
        send(url, function(response)
            complete(mtgCatalogParseScryfall(response, entry.name))
        end)
    end

    send(MTG_CATALOG_BASE .. "/api/cards?name="
            .. mtgCatalogEncode(entry.name) .. "&limit=20",
        function(response)
            local value = mtgCatalogParseMTGA(response, entry.name)
            if value then complete(value) else fallback() end
        end)
end

mtgCatalogPump = function()
    while mtgCatalogActive < MTG_CATALOG_MAX_ACTIVE and #mtgCatalogQueue > 0 do
        local key = table.remove(mtgCatalogQueue, 1)
        if mtgCatalogCache[key] and mtgCatalogCache[key].state == "pending" then
            mtgCatalogLookup(key)
        end
    end
end

local function mtgCatalogEntry(name)
    local key = mtgCatalogKey(name)
    local entry = mtgCatalogCache[key]
    if entry and entry.state == "miss"
        and os.time() - (entry.finishedAt or 0) >= 120 then
        mtgCatalogCache[key] = nil
        entry = nil
    end
    if entry then return key, entry end
    -- Bound memory and avoid evicting in-flight requests.
    if #mtgCatalogOrder >= MTG_CATALOG_MAX_CACHE then
        for i = 1, #mtgCatalogOrder do
            local oldKey = mtgCatalogOrder[i]
            local old = mtgCatalogCache[oldKey]
            if not old or old.state ~= "pending" then
                mtgCatalogCache[oldKey] = nil
                table.remove(mtgCatalogOrder, i)
                break
            end
        end
    end
    entry = {name = name, state = "pending", listeners = {}}
    mtgCatalogCache[key] = entry
    mtgCatalogOrder[#mtgCatalogOrder + 1] = key
    if #mtgCatalogQueue < MTG_CATALOG_MAX_WAITING then
        mtgCatalogQueue[#mtgCatalogQueue + 1] = key
        mtgCatalogPump()
    else
        entry.state, entry.finishedAt = "miss", os.time()
    end
    return key, entry
end

-- Returns immediately. For remote data, request and poll Get later.
-- With a supplied seated color, results are also printed privately on completion.
function mtgCardCatalogRequest(params)
    local guid = type(params) == "table" and params.guid or params
    local color = type(params) == "table" and params.color or nil
    if type(guid) ~= "string" then return {status = "invalid"} end
    local obj = getObjectFromGUID(guid)
    if obj == nil or obj.type ~= "Card" or obj.is_face_down then
        return {status = "invalid", reason = "not a visible card"}
    end
    local localData = mtgCardMetadata({guid = guid})
    local name = localData and localData.name or mtgCatalogName(obj.getName())
    if name == "" then return {status = "invalid", reason = "unnamed card"} end
    local _, entry = mtgCatalogEntry(name)
    if mtgCatalogColors[color] then
        if entry.state == "pending" then
            entry.listeners[color] = true
        else
            mtgCatalogReport(color, entry)
        end
    end
    return {status = entry.state, localData = localData,
        remote = entry.state == "ready" and entry.value or nil}
end

-- Read-only, no network request. The caller must handle pending/miss explicitly.
function mtgCardCatalogGet(params)
    local guid = type(params) == "table" and params.guid or params
    if type(guid) ~= "string" then return {status = "invalid"} end
    local obj = getObjectFromGUID(guid)
    if obj == nil or obj.type ~= "Card" or obj.is_face_down then
        return {status = "invalid"}
    end
    local localData = mtgCardMetadata({guid = guid})
    local key = mtgCatalogKey(localData and localData.name or mtgCatalogName(obj.getName()))
    local entry = mtgCatalogCache[key]
    return {status = entry and entry.state or "not_requested",
        localData = localData,
        remote = entry and entry.state == "ready" and entry.value or nil}
end
