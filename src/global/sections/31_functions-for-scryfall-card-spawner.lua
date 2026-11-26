-- Scryfall requests, card spawning and text deck-list imports.

---------------------- FUNCTIONS FOR SCRYFALL CARD SPAWNER ---------------------
--------------------------------------------------------------------------------

-- Shared Scryfall client: custom identification headers, a paced request queue,
-- duplicate-request coalescing, and an in-memory lookup cache.  Every Scryfall
-- call in this Global script goes through scryfallGet; unrelated GitHub and
-- rikrassen requests intentionally keep their existing request paths.
-- Scryfall asks applications to stay UNDER 10 requests/second.  0.20 seconds
-- between request starts means at most 5 requests/second from this script.
local scryfallRequestInterval = 0.20
local scryfallMaxCachedResponses = 250
local scryfallUserAgent = "MTG-EDH-TTS-Card-Spawner/1.0 (Tabletop Simulator Magic importer)"
local scryfallRequestQueue = {}
local scryfallPendingByUrl = {}
local scryfallResponseCache = {}
local scryfallResponseCacheOrder = {}
local scryfallQueueRunning = false
local scryfallBlockedUntil = 0
local scryfallBlockWarningIssued = false

-- Keep a reusable response in the Scryfall request cache.
local function scryfallRememberResponse(url, result)
    if scryfallResponseCache[url] == nil then
        table.insert(scryfallResponseCacheOrder, url)
    end
    scryfallResponseCache[url] = result
    while #scryfallResponseCacheOrder > scryfallMaxCachedResponses do
        local oldest = table.remove(scryfallResponseCacheOrder, 1)
        scryfallResponseCache[oldest] = nil
    end
end

-- Report a failed Scryfall request.
local function scryfallReportError(req)
    local status = tonumber(req.response_code) or 0
    local message = ""
    if type(req.text) == "string" and req.text ~= "" then
        local ok, parsed = pcall(JSON.decode, req.text)
        if ok and type(parsed) == "table" then
            message = tostring(parsed.details or parsed.error or "")
        end
    end
    local summary = "Scryfall HTTP " .. tostring(status)
    if message ~= "" then summary = summary .. ": " .. message end
    printToAll(summary, { 1, 0.35, 0.35 })
end

-- Advance the queued Scryfall requests.
local function scryfallDispatchNext()
    if os.time() < scryfallBlockedUntil then
        scryfallQueueRunning = false
        return
    end

    local task = table.remove(scryfallRequestQueue, 1)
    if task == nil then
        scryfallQueueRunning = false
        return
    end

    -- Schedule the next START before this asynchronous request completes.
    -- This limits outgoing request frequency without serializing slow responses.
    Wait.time(scryfallDispatchNext, scryfallRequestInterval)

    local headers = {
        ["User-Agent"] = scryfallUserAgent,
        ["Accept"] = "application/json;q=0.9,*/*;q=0.8",
    }
    WebRequest.custom(task.url, "GET", true, "", headers, function(req)
        if scryfallPendingByUrl[task.url] == task then
            scryfallPendingByUrl[task.url] = nil
        end
        if req.is_error then
            printToAll("Scryfall connection error: " .. tostring(req.error), { 1, 0.35, 0.35 })
            return
        end

        local status = tonumber(req.response_code) or 0
        if status == 429 then
            -- Do NOT automatically retry 429 responses.  Discard outstanding
            -- queued work and require a fresh user action after the cooldown.
            scryfallBlockedUntil = os.time() + 60
            scryfallRequestQueue = {}
            scryfallPendingByUrl = {}
            scryfallBlockWarningIssued = false
            printToAll(
                "Scryfall rate limit (429): queued requests cancelled. "
                    .. "Please allow traffic to cool down before trying again.",
                { 1, 0.35, 0.35 }
            )
            return
        end
        if status ~= 200 and status ~= 404 then
            scryfallReportError(req)
            return
        end

        -- Cache successful results as plain Lua values, not WebRequest objects:
        -- TTS automatically disposes request objects after their callbacks.
        local result = {
            is_error = false,
            response_code = status,
            text = req.text or "",
        }
        if status == 200 then
            scryfallRememberResponse(task.url, result)
        end
        for _, callback in ipairs(task.callbacks) do
            local ok, err = pcall(callback, result)
            if not ok then
                print("[Scryfall] Response handler failed: " .. tostring(err))
            end
        end
    end)
end

-- Requests for the same URL share one HTTP call and one cached JSON response,
-- but all interested callers still receive their own callback (and can spawn
-- their own cards).  The cache lasts only until Global Lua is reloaded.
function scryfallGet(url, callback)
    if type(url) ~= "string" or not url:match("^https://api%.scryfall%.com/") then
        printToAll("Scryfall: invalid API URL.", { 1, 0.35, 0.35 })
        return
    end
    if os.time() < scryfallBlockedUntil then
        if not scryfallBlockWarningIssued then
            printToAll("Scryfall requests are temporarily paused after a rate-limit response.", { 1, 0.6, 0.2 })
            scryfallBlockWarningIssued = true
        end
        return
    end
    scryfallBlockWarningIssued = false

    local cached = scryfallResponseCache[url]
    if cached ~= nil then
        local ok, err = pcall(callback, cached)
        if not ok then print("[Scryfall] Cached response handler failed: " .. tostring(err)) end
        return
    end
    local pending = scryfallPendingByUrl[url]
    if pending ~= nil then
        table.insert(pending.callbacks, callback)
        return
    end

    local task = { url = url, callbacks = { callback } }
    scryfallPendingByUrl[url] = task
    table.insert(scryfallRequestQueue, task)
    if not scryfallQueueRunning then
        scryfallQueueRunning = true
        scryfallDispatchNext()
    end
end

-- Open the card-spawner interface.
function show(obj, color, alt)
	if obj.getName() == "MTG Importer" then
		if alt then
			visibleOpenRules(color, "ListPanel")
		else
			visibleOpenRules(color, "SearchPanel")
		end
	elseif obj.getName() == "MTG Counter" then
		visibleOpenRules(color, color .. "Counter")
	end
end

-- Close the relevant spawner or importer UI.
function close(player, value, id)
	if id == "closeButton" then
		visibleCloseRules(player, "SearchPanel")
	elseif id == "ListCloseButton" then
		visibleCloseRules(player, "ListPanel")
	elseif id == "bcCloseButton" then
		visibleCloseRules(player, player.color .. "Counter")
	end
end

-- Build and submit the current card-spawner query.
function search(player)
	--INPUTFIELD RELATED
	local q = ""
	local name = UI.getAttribute("vName", "text")
	local cmc = UI.getAttribute("vCmc", "text")
	local power = UI.getAttribute("vPower", "text")
	local toughness = UI.getAttribute("vToughness", "text")
	if name ~= nil and name ~= "" then
		q = q .. encodeString(name)
	end
	if cmc ~= nil and cmc ~= "" then
		q = q .. "+cmc%3D" .. encodeString(cmc)
	end
	if power ~= nil and power ~= "" then
		q = q .. "+power%3D" .. encodeString(power)
	end
	if toughness ~= nil and toughness ~= "" then
		q = q .. "+toughness%3D" .. encodeString(toughness)
	end

	--COLOR RELATED
	--c%3ARG+%28-c%3AW+AND+-c%3AU+AND+-c%3AB%29
	local colorIds = { vWhite = "W", vBlue = "U", vBlack = "B", vRed = "R", vGreen = "G", vColorless = "C" }
	local colors = ""
	local xColors = {}
	for k, v in pairs(colorIds) do
		--TOGGLEBUTTONS ARE INVERSED TO SHOW ICONS
		if UI.getAttribute(k, "isOn") == "False" then
			colors = colors .. v
		else
			table.insert(xColors, v)
		end
	end
	if colors ~= "" then
		q = q .. "+color%3A" .. colors
		if xColors[1] ~= "" then
			q = q .. "+%28-c%3A" .. table.concat(xColors, "+AND+-c%3A") .. "%29"
		end
	end

	--TYPE RELATED
	local tokenParam = ""
	if UI.getAttribute("vToken", "isOn") == "True" then
		tokenParam = "include_extras=true&"
		--+layout%3Dtoken+or+layout%3Ddouble_faced_token
		q = q .. "+layout%3Dtoken"
	elseif UI.getAttribute("vEmblem", "isOn") == "True" then
		q = q .. "+layout%3Demblem"
		tokenParam = "include_extras=false&"
	else
		tokenParam = "include_extras=false&"
	end

	--STARTS WITH +
	if string.sub(q, 1, 2) == "+" then
		q = string.sub(q, 2, -1)
	end

	local requestUrl = "https://api.scryfall.com/cards/search?format=json&unique=cards&order=name&"
		.. tokenParam
		.. "q="
		.. q

	scryfallGet(requestUrl, function(a)
		objectProccessor(a, player, false)
	end)
end

-- Route a response to the appropriate card or list processing path.
function objectProccessor(webReturn, player, isPart)
	if webReturn.is_error then
		printToAll("Scryfall server error:")
		errorJson(webReturn.text, player)
	else
		local object = string.match(webReturn.text, '"object":"[^"]*"')
		if object == nil then
			errorJson(webReturn.text, player)
		else
			if isPart == false then
				local object = string.sub(object, 11, -2)
				if object == "list" then
					listJson(webReturn.text, player)
				elseif object == "error" then
					errorJson(webReturn.text, player)
				elseif object == "card" then
					cardJson(webReturn.text, "card", player, false)
				else
					printToAll("Unexpect object returned from search")
				end
			else
				cardJson(webReturn.text, "card", player, true)
			end
		end
	end
end

-- Process a list of returned card records.
function listJson(json, player)
	local cardUri = string.match(json, '"uri":"[^"]*"')
	local cardUri = string.sub(cardUri, 8, -2)
	scryfallGet(cardUri, function(a)
		objectProccessor(a, player, false)
	end)
end

-- Prepare Oracle text for the imported card representation.
function setOracle(c)
	local n = "\n[b]"
	if c.power then
		n = n .. c.power .. "/" .. c.toughness
	elseif c.loyalty then
		n = n .. tostring(c.loyalty)
	else
		n = "[b]"
	end
	return c.oracle_text:gsub('"', "'") .. n .. "[/b]"
end

-- Convert a Scryfall card record into the data needed by the spawner.
function cardJson(json, type, player, isPart)
	local back =
		"https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"
	local json = JSONdecode(json)
	if json.card_faces and type == "card" then
		face = json.card_faces[1].image_uris.large:gsub("%?.*", "")
		back = json.card_faces[2].image_uris.large:gsub("%?.*", "")
		if face:find("/back/") and back:find("/front/") then
			local temp = face
			face = back
			back = temp
		end
	elseif json.card_faces and type == "deck" then
		if json.card_faces[1].image_uris then
			face = json.card_faces[1].image_uris.large:gsub("%?.*", "")
		else
			face = json.image_uris.large:gsub("%?.*", "")
		end
	else
		face = json.image_uris.large:gsub("%?.*", "")
	end
	local oracleID = json.oracle_id
	local c = json
	c.oracle = ""
	--Oracle text Handling for Split/DFCs
	if c.card_faces then
		for _, f in ipairs(c.card_faces) do
			f.name = f.name:gsub('"', "") .. "\n" .. f.type_line .. " " .. c.cmc .. "CMC"
			if _ == 1 then
				c.name = f.name
			end
			c.oracle = c.oracle .. f.name .. "\n" .. setOracle(f) .. (_ == #c.card_faces and "" or "\n")
		end
	else
		c.name = c.name:gsub('"', "") .. "\n" .. c.type_line .. " " .. c.cmc .. "CMC"
		c.oracle = setOracle(c)
	end

	local name_ex = c.name
	local oracle = c.oracle
	--json.mana_cost
	spawn(oracleID, name_ex, oracle, face, back, player, isPart)
	if isPart == false and json.all_parts then
		for _, v in ipairs(json.all_parts) do
			if v.id ~= json.id then
				if v.component == "combo_piece" then
					if string.match(v.type_line, "Emblem") ~= nil then
						local cardUri = v.uri
						scryfallGet(cardUri, function(a)
							objectProccessor(a, player, true)
						end)
					end
				else
					local cardUri = v.uri
					scryfallGet(cardUri, function(a)
						objectProccessor(a, player, true)
					end)
				end
			end
		end
	end
end

-- Display an error returned by the card API.
function errorJson(json, player)
	local json = JSONdecode(json)
	if json.status == 404 then
		printToAll(
			"Your query didn't match any cards. Adjust your search terms and try again.",
			{ r = 0, g = 123, b = 255 }
		)
	else
		printToAll(json.details)
	end
end

-- Extract the Oracle text used for imported cards.
function getOracle(json)
	local str = ""
	if json.card_faces then
		for _, v in ipairs(json.card_faces) do
			str = str .. "\n" .. getOracle(v)
		end
	else
		if json.oracle_text then
			str = str .. "\n" .. json.oracle_text
		end
		if json.power then
			str = str .. "\n[b]" .. json.power .. "/" .. json.toughness .. "[/b]"
		end
		if json.loyalty then
			str = str .. "\n[b]" .. json.loyalty .. "[/b]"
		end
		str = string.gsub(str, '"', '\\"')
	end
	return str
end

-- Spawn a physical card from the prepared card information and images.
function spawn(oracleID, name, oracle, face, back, player, isPart)
	--SPAWN POSITION IN RELATION TO PLAYER COLOR
	local spawn
	local spawns = props[player.color].spawns
	if isPart then
		spawn = spawns.main
	else
		spawn = spawns.part
	end
	tColor = '"Transform":{"posX":'
		.. spawn.posX
		.. ',"posY":5,"posZ":'
		.. spawn.posZ
		.. ',"rotX":0,"rotY":'
		.. spawn.rotY
		.. ',"rotZ":0,"scaleX":1.0,"scaleY":1.0,"scaleZ":1.0}'

	local Object = {}
	Object.json = '{"Name":"Card",'
		.. tColor
		.. ","
		.. '"Memo":"'
		.. oracleID
		.. '",'
		.. '"Nickname":"'
		.. name
		.. '",'
		.. '"Description":"'
		.. oracle
		.. '",'
		.. '"CardID":536,"CustomDeck":{"5":{'
		.. '"FaceURL":"'
		.. face
		.. '",'
		.. '"BackURL":"'
		.. back
		.. '",'
		.. '"NumWidth":1,"NumHeight":1,"BackIsHidden":true}}}'
	Object.params = { name = name, oracle = oracle }
	spawnObjectJSON(Object)
end

-- Read the text deck list from the UI and start importing it.
function getDeckList(player)
	local deckList = UI.getAttribute("vDeckList", "text")
	if deckList ~= "" then
		for i in string.gmatch(deckList, "[^\n\r]+") do
			local fStart, fEnd = string.find(i, "%d+")
			--EACH LINE NEEDS TO BE: NUMBER SPACE CARDNAME
			if fStart ~= 1 then
				return
			end
			local count = tonumber(string.sub(i, fStart, fEnd))
			if count ~= nil then
				local name = string.sub(i, fEnd + 2, -1)
				local requestBaseUrl = "https://api.scryfall.com/cards/named?fuzzy="
				local requestUrl = requestBaseUrl .. encodeString(name)
				scryfallGet(requestUrl, function(a)
					getDeck(a, count, player)
				end)
			end
		end
	else
		broadcastToAll("Deck is empty", { r = 0, g = 123, b = 255 })
	end
end

-- Process a deck import response and assemble the resulting cards.
function getDeck(webReturn, cardCount, player)
	if webReturn.is_error then
		printToAll("Scryfall server error: " .. tostring(webReturn.error or "unknown error"))
		return
	end
	local ok, card = pcall(JSON.decode, webReturn.text or "")
	if not ok or type(card) ~= "table" then
		printToAll("Scryfall returned an unreadable card response.")
		return
	end
	if card.object == "error" then
		if card.status == 404 then
			printToAll("Scryfall did not find a card: " .. tostring(card.details or "unknown name"))
		else
			printToAll("Scryfall error: " .. tostring(card.details or "unknown error"))
		end
		return
	end
	if card.object ~= "card" then
		printToAll("Scryfall returned an unexpected response instead of a card.")
		return
	end
	for i = 1, cardCount do
		cardJson(webReturn.text, "deck", player, false)
	end
end

-- Store a text field change from the spawner or importer UI.
function updateText(player, value, id)
	UI.setAttribute(id, "text", value)
end

-- Update the selected search color filters.
function updatevColor(player, value, id)
	UI.setAttribute(id, "isOn", value)
end

-- Update the selected search card category.
function updateType(player, value, id)
	local ids = { "vToken", "vEmblem", "vOther" }
	for _, i in pairs(ids) do
		if i == id then
			UI.setAttribute(i, "isOn", "True")
		else
			UI.setAttribute(i, "isOn", "False")
		end
	end
end

-- Show the requested rules UI for the player.
function visibleOpenRules(color, id)
	if color ~= "Grey" then
		local active = UI.getAttribute(id, "active")
		local visibleColors = UI.getAttribute(id, "visibility")
		if visibleColors == "" then
			UI.setAttribute(id, "visibility", color)
		else
			if string.find(visibleColors, color) == nil then
				visibleColors = visibleColors .. "|" .. color
				UI.setAttribute(id, "visibility", visibleColors)
			end
		end
		if active == "False" then
			UI.setAttribute(id, "active", "True")
		end
	end
end

-- Hide the requested rules UI.
function visibleCloseRules(player, id)
	local visibleColors = UI.getAttribute(id, "visibility")
	if visibleColors == player.color then
		UI.setAttribute(id, "active", "False")
	end
	if visibleColors == player.color then
		UI.setAttribute(id, "visibility", "")
	else
		local colorTbl = {}
		for i in string.gmatch(visibleColors, "[^|]+") do
			if i ~= player.color then
				table.insert(colorTbl, i)
			end
		end
		visibleColors = table.concat(colorTbl, "|")
		UI.setAttribute(id, "visibility", visibleColors)
	end
end

--FUNCTIONS RELATED TO DECK IMAGE FIXING
function createButtons(obj)
	enc = Global.getVar("Encoder")
	if enc ~= nil then
		if obj.is_face_down then
			flip = -1
		else
			flip = 1
		end
		scaler = { x = 1, y = 1, z = 1 }
		temp = " Fix Images "
		barSize, fsize, offset_x, offset_y =
			enc.call("APIformatButton", { str = temp, font_size = 90, max_len = 90, xJust = 0, yJust = 0 })
		obj.createButton({
			label = temp,
			click_function = "fixDeck",
			function_owner = self,
			position = {
				(0 + offset_x) * flip * scaler.x,
				0.28 * flip * scaler.z,
				(-1.65 + offset_y) * scaler.y,
			},
			height = 170,
			width = barSize,
			font_size = fSize,
			rotation = { 0, 0, 90 - 90 * flip },
		})
	end
end

-- Run the existing deck preparation action.
function fixDeck(obj, color)
	if obj.type == "Deck" then
		local deck = obj
		for _, card in ipairs(deck.getObjects()) do
			if card.nickname ~= nil and card.nickname ~= "" then
				local count = 1
				local name = card.nickname
				local requestBaseUrl = "https://api.scryfall.com/cards/named?fuzzy="
				local requestUrl = requestBaseUrl .. encodeString(name)
				scryfallGet(requestUrl, function(a)
					getDeck(a, count, Player[color])
				end)
			end
		end
	elseif obj.type == "Card" and obj.getName() ~= nil and obj.getName() ~= "" then
		local name = obj.getName()
		local requestBaseUrl = "https://api.scryfall.com/cards/named?fuzzy="
		local requestUrl = requestBaseUrl .. encodeString(name)
		scryfallGet(requestUrl, function(a)
			objectProccessor(a, Player[color], false)
		end)
	end
end

--PERCENT ENCODING
function encodeChar(chr)
	return string.format("%%%X", string.byte(chr))
end

-- Encode a string for use in a URL.
function encodeString(str)
	local output, t = string.gsub(str, "[^%w]", encodeChar)
	return output
end

