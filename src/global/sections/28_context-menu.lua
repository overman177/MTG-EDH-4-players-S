--------------------------------- CONTEXT MENU ---------------------------------

-- Context menus are shared by all scripts on an object.
-- Do NOT call clearContextMenu(): it also deletes Portable Helper entries.
local mtgAddedMenus = {}

local function mtgObjectInRole(obj, roleKey)
    if obj == nil or data == nil then return false end
    for _, color in ipairs(mtgPlayerColors) do
        local pdata = data[color]
        if pdata ~= nil and zoneContains(pdata[roleKey], obj) then
            return true
        end
    end
    return false
end

local function mtgObjectInHand(obj)
    if obj == nil then return false end
    for _, color in ipairs(mtgPlayerColors) do
        for _, held in ipairs(Player[color].getHandObjects(1)) do
            if held == obj then return true end
        end
    end
    return false
end

function mtgAddMenu(obj, label, handler, roleKey)
    if obj == nil then return end
    local guid = obj.getGUID()
    if mtgAddedMenus[guid] == nil then mtgAddedMenus[guid] = {} end
    if mtgAddedMenus[guid][label] then return end
    -- A callback must validate current location because context menu entries
    -- cannot be individually removed using TTS API.
    obj.addContextMenuItem(label, function(color, pos, clicked)
        if roleKey == "Hand" then
            if not mtgObjectInHand(obj) then return end
        elseif roleKey ~= nil then
            if not mtgObjectInRole(obj, roleKey) then return end
        end
        handler(color, pos, clicked)
    end)
    mtgAddedMenus[guid][label] = true
end

function mtgRefreshContextMenus(obj)
    if obj == nil or (obj.type ~= "Card" and obj.type ~= "Deck") then return end
    if obj.getName():lower():find("planechase") then return end
    if obj.type == "Card" and mtgObjectInRole(obj, "playmat") then
        mtgAddMenu(obj, "Make Token Copy", cardToken, "playmat")
        if obj.getDescription():lower():find("cascade") then
            mtgAddMenu(obj, "Cascade", cardCascade, "playmat")
        end
    end
    if obj.type == "Card" and mtgObjectInHand(obj) then
        mtgAddMenu(obj, "Sort Hand by CMC", sortHands, "Hand")
        mtgAddMenu(obj, "Random Discard", randomDiscard, "Hand")
    end
    if obj.type == "Deck" and mtgObjectInRole(obj, "libraryZone") then
        mtgAddMenu(obj, "Cascade for X", deckCascade, "libraryZone")
        mtgAddMenu(obj, "Reveal until Type", deckSeachType, "libraryZone")
        addLandContextMenus(obj)
        obj.setScale({ 1, 1, 1 })
    end
end

function addZoneContextMenus()
    if data == nil then return end
    for _, color in ipairs(mtgPlayerColors) do
        local playerData = data[color]
        if playerData ~= nil then
            for _, obj in ipairs(mtgZoneObjects(playerData.libraryZone)) do
                mtgRefreshContextMenus(obj)
            end
            for _, obj in ipairs(mtgZoneObjects(playerData.playmat)) do
                mtgRefreshContextMenus(obj)
            end
            for _, obj in ipairs(Player[color].getHandObjects(1)) do
                mtgRefreshContextMenus(obj)
            end
        end
    end
end

-- Global context menu items (on the tabletop itself)
addContextMenuItem("have a response", function(c)
    broadcastToAll(Player[c].steam_name .. " has a response!", stringColorToRGB(c))
end)
addContextMenuItem("could you not", function(c)
    broadcastToAll(Player[c].steam_name .. ' asks: [999999]"Could you not?"[-]', stringColorToRGB(c))
end)
addContextMenuItem("hand counts", function(c)
    local s = "number of cards in hands:"
    for _, p in pairs(Player.getPlayers()) do
        local n = #p.getHandObjects()
        if n < 10 then n = "0" .. n end
        s = s .. "\n[" .. Color[p.color]:toHex() .. "]" .. n
    end
    Player[c].broadcast(s .. "[-]", { 0.7, 0.7, 0.7 })
end)

-- The built-in event is suppressed for cards incompatible with a tagged zone.
-- mtgPollZoneSnapshots() routes those missing changes to the same handlers.
function onObjectEnterZone(zone, obj)
    mtgDispatchZoneChange(zone, obj, true)
end

function onObjectLeaveZone(zone, obj)
    mtgDispatchZoneChange(zone, obj, false)
end

function mtgHandleZoneEnter(zone, obj)
    if obj == nil or (obj.type ~= "Card" and obj.type ~= "Deck") then return end
    if obj.getName():lower():find("planechase") then return end
    trackLandEnter(zone, obj)
    fetchlandEnter(zone, obj)
    dfcLandEnter(zone, obj)
    stampOwnershipOnEnter(zone, obj)
    if obj.type == "Card" then mtgInvalidateCardMetadata({guid = obj.getGUID()}) end
    ownershipMatEnter(zone, obj)
    mtgQueuePrintedKeywordEquip(zone, obj)
    mtgFlyingHoverEnter(zone, obj)
    mtgRefreshContextMenus(obj)
end

function mtgHandleZoneLeave(zone, obj)
    if obj == nil or (obj.type ~= "Card" and obj.type ~= "Deck") then return end
    if obj.getName():lower():find("planechase") then return end
    if landZoneColor(zone) ~= nil then
        fetchlandLeave(zone, obj)
    end
    ownershipMatLeave(zone, obj)
    mtgFlyingHoverLeave(zone, obj)
    mtgRefreshContextMenus(obj)
end

function addLandContextMenus(deck)
	local plains, island, mountain, swamp, forest, wastes = false, false, false, false, false, false
	for _, card in pairs(deck.getObjects()) do
		local cname = card.name:lower():gsub("%p", "")
		if cname:find("basic") and cname:find("land") and cname:find("plains") then
			plains = true
		end
		if cname:find("basic") and cname:find("land") and cname:find("island") then
			island = true
		end
		if cname:find("basic") and cname:find("land") and cname:find("mountain") then
			mountain = true
		end
		if cname:find("basic") and cname:find("land") and cname:find("swamp") then
			swamp = true
		end
		if cname:find("basic") and cname:find("land") and cname:find("forest") then
			forest = true
		end
		if cname:find("basic") and cname:find("land") and cname:find("wastes") then
			wastes = true
		end
	end

	if plains then
		mtgAddMenu(deck, "Get Basic Plains", deckRampW, "libraryZone")
	end
	if island then
		mtgAddMenu(deck, "Get Basic Island", deckRampU, "libraryZone")
	end
	if mountain then
		mtgAddMenu(deck, "Get Basic Mountain", deckRampR, "libraryZone")
	end
	if swamp then
		mtgAddMenu(deck, "Get Basic Swamp", deckRampB, "libraryZone")
	end
	if forest then
		mtgAddMenu(deck, "Get Basic Forest", deckRampG, "libraryZone")
	end
	if wastes then
		mtgAddMenu(deck, "Get Basic Wastes", deckRampWa, "libraryZone")
	end
end

function deckRampW(ply)
	local deck = getDeckFromZone(data[ply]["libraryZone"])
	if deck == nil then
		return
	end
	for i, card in ipairs(deck.getObjects()) do
		local cname = card.name:lower():gsub("%p", "")
		if cname:find("basic") and cname:find("land") and cname:find("plains") then
			local rot = deck.getRotation()
			local pos = deck.getPosition()
			local rig = deck.getTransformRight()
			rot[3] = 0
			pos = pos + rig:scale(deckDirs[ply] * 2.4)
			deck.takeObject({ index = i - 1, position = pos, rotation = rot })
			break
		end
	end
	Wait.time(function()
		deck.shuffle()
	end, 0.1, 5)
end

function deckRampU(ply)
	local deck = getDeckFromZone(data[ply]["libraryZone"])
	if deck == nil then
		return
	end
	for i, card in ipairs(deck.getObjects()) do
		local cname = card.name:lower():gsub("%p", "")
		if cname:find("basic") and cname:find("land") and cname:find("island") then
			local rot = deck.getRotation()
			local pos = deck.getPosition()
			local rig = deck.getTransformRight()
			rot[3] = 0
			pos = pos + rig:scale(deckDirs[ply] * 2.4)
			deck.takeObject({ index = i - 1, position = pos, rotation = rot })
			break
		end
	end
	Wait.time(function()
		deck.shuffle()
	end, 0.1, 5)
end

function deckRampR(ply)
	local deck = getDeckFromZone(data[ply]["libraryZone"])
	if deck == nil then
		return
	end
	for i, card in ipairs(deck.getObjects()) do
		local cname = card.name:lower():gsub("%p", "")
		if cname:find("basic") and cname:find("land") and cname:find("mountain") then
			local rot = deck.getRotation()
			local pos = deck.getPosition()
			local rig = deck.getTransformRight()
			rot[3] = 0
			pos = pos + rig:scale(deckDirs[ply] * 2.4)
			deck.takeObject({ index = i - 1, position = pos, rotation = rot })
			break
		end
	end
	Wait.time(function()
		deck.shuffle()
	end, 0.1, 5)
end

function deckRampB(ply)
	local deck = getDeckFromZone(data[ply]["libraryZone"])
	if deck == nil then
		return
	end
	for i, card in ipairs(deck.getObjects()) do
		local cname = card.name:lower():gsub("%p", "")
		if cname:find("basic") and cname:find("land") and cname:find("swamp") then
			local rot = deck.getRotation()
			local pos = deck.getPosition()
			local rig = deck.getTransformRight()
			rot[3] = 0
			pos = pos + rig:scale(deckDirs[ply] * 2.4)
			deck.takeObject({ index = i - 1, position = pos, rotation = rot })
			break
		end
	end
	Wait.time(function()
		deck.shuffle()
	end, 0.1, 5)
end

function deckRampG(ply)
	local deck = getDeckFromZone(data[ply]["libraryZone"])
	if deck == nil then
		return
	end
	for i, card in ipairs(deck.getObjects()) do
		local cname = card.name:lower():gsub("%p", "")
		if cname:find("basic") and cname:find("land") and cname:find("forest") then
			local rot = deck.getRotation()
			local pos = deck.getPosition()
			local rig = deck.getTransformRight()
			rot[3] = 0
			pos = pos + rig:scale(deckDirs[ply] * 2.4)
			deck.takeObject({ index = i - 1, position = pos, rotation = rot })
			break
		end
	end
	Wait.time(function()
		deck.shuffle()
	end, 0.1, 5)
end

function deckRampWa(ply)
	local deck = getDeckFromZone(data[ply]["libraryZone"])
	if deck == nil then
		return
	end
	for i, card in ipairs(deck.getObjects()) do
		local cname = card.name:lower():gsub("%p", "")
		if cname:find("basic") and cname:find("land") and cname:find("wastes") then
			local rot = deck.getRotation()
			local pos = deck.getPosition()
			local rig = deck.getTransformRight()
			rot[3] = 0
			pos = pos + rig:scale(deckDirs[ply] * 2.4)
			deck.takeObject({ index = i - 1, position = pos, rotation = rot })
			break
		end
	end
	Wait.time(function()
		deck.shuffle()
	end, 0.1, 5)
end

function toggleEncMenu(ply)
	objs = Player[ply].getSelectedObjects()
	for i, obj in pairs(objs) do
		obj.setLock(true)
		Encoder.call("APIencodeObject", { obj = obj })
		local objRot = obj.getRotation()
		local cardFlip = 1
		if objRot[3] > 90 and objRot[3] < 270 then
			cardFlip = -1
		end
		local encFlip = Encoder.call("APIgetFlip", { obj = obj })
		if encFlip ~= cardFlip then
			Encoder.call("APIFlip", { obj = obj })
		end
		Encoder.call("APIobjToggleMenu", { obj = obj, menuID = "πMenu" })
		Encoder.call("APIrebuildButtons", { obj = obj })
		Wait.frames(function()
			obj.setLock(false)
		end, 1)
	end
end

function cardToken(ply)
	objs = Player[ply].getSelectedObjects()
	card = objs[1]
	Player[ply].clearSelectedObjects()
	if card.type ~= "Card" then
		return
	end
	local newPos = card.getPosition() + card.getTransformForward():scale(-3.2)
	local cardDat = card.getData()
	cardDat.Transform.posX = newPos.x
	cardDat.Transform.posY = newPos.y + 0.1
	cardDat.Transform.posZ = newPos.z
	Encoder.call("APIencodeObject", { obj = card })
	local flip = Encoder.call("APIgetFlip", { obj = card })
	local moduleData = Encoder.call("APIobjGetProps", { obj = card })
	local valueData = Encoder.call("APIobjGetAllData", { obj = card })
	local tCard = spawnObjectData({ data = cardDat })
	Wait.Condition(function()
		if tCard == nil or Encoder == nil then
			return
		end
		Encoder.call("APIencodeObject", { obj = tCard })
		Encoder.call("APIobjSetAllData", { obj = tCard, data = valueData })
		Encoder.call("APIobjSetProps", { obj = tCard, data = moduleData })
		if flip < 0 then
			Encoder.call("APIFlip", { obj = tCard })
		end
		Encoder.call("APIobjEnableProp", { obj = tCard, propID = "MTG_Token" })
		Encoder.call("APIrebuildButtons", { obj = tCard })
	end, function()
		return tCard == nil or not tCard.spawning
	end)
end

function cardCascade(ply)
	objs = Player[ply].getSelectedObjects()
	card = objs[1]
	Player[ply].clearSelectedObjects()
	if card.type ~= "Card" then
		return
	end
	local proceed = false
	for _, obj in pairs(mtgZoneObjects(data[ply]["playmat"])) do
		if obj == card then
			proceed = true
		end
	end
	if proceed then
		local cmc = getCMC(card.getName(), card.getDescription())
		local val = cmc - 1
		local deck = getDeckFromZone(data[ply]["libraryZone"])
		if val >= 0 and deck ~= nil then
			local rot = deck.getRotation()
			rot.z = 180
			deck.setRotation(rot)
			cascade(deck, ply, val)
		end
	end
end

-- sort hands by CMC
function sortHands(ply)
	Player[ply].clearSelectedObjects()
	for handInd = 1, Player[ply].getHandCount() do
		local cards = Player[ply].getHandObjects(handInd)
		local cmcs = {}
		local poss = {}
		noCMCs = false
		for i, card in ipairs(cards) do
			if card.type == "Card" then
				cmc = getCMC(card.getName(), card.getDescription())
				if cmc == nil then
					cmc = "-2"
					noCMCs = true
				end
				table.insert(cmcs, { id = i, cmc = cmc })
				table.insert(poss, card.getPosition())
			end
		end
		table.sort(cmcs, function(a, b)
			return tonumber(a.cmc) < tonumber(b.cmc)
		end)

		if noCMCs then
			Player[ply].broadcast(
				"No CMC info found in the card names or description.\n"
					.. "You could use the Deck Lister to reimport your deck with the necessary info,\n"
					.. "Or the Deck Data Fetcher to download and port the info directly onto your deck.",
				{ 0.7, 0.7, 0.7 }
			)
			local pingGUIDs = { "6d07c3", "5006a4", "6d46cd", "6ed442" }
			for i, guid in ipairs(pingGUIDs) do
				if getObjectFromGUID(guid) ~= nil then
					Player[ply].pingTable(getObjectFromGUID(guid).getPosition())
				end
			end
		else
			-- for i,v in ipairs(cmcs) do
			-- cards[v.id].setPosition(poss[i])
			-- end

			for i, v in ipairs(cmcs) do
				cards[v.id].setHiddenFrom(allBut(ply))
				cards[v.id].setLock(true)
				Wait.frames(function()
					cards[v.id].setPositionSmooth(poss[i], false, false)
				end, 1)
			end

			Wait.frames(function()
				Wait.condition(function()
					for i, v in ipairs(cmcs) do
						cards[v.id].setLock(false)
						cards[v.id].setPosition(poss[i])
						Wait.frames(function()
							cards[v.id].setHiddenFrom({})
						end, 20)
					end
				end, function()
					local doneMoving = true
					for _, card in pairs(cards) do
						if card.isSmoothMoving() then
							doneMoving = false
						end
					end
					return doneMoving
				end)
			end, 5)
		end
	end
end

function randomDiscard(ply)
	local cards = Player[ply].getHandObjects(1)
	Player[ply].clearSelectedObjects()
	local discardN = math.random(#cards)
	Wait.time(function()
		discardN = math.random(#cards)
		cards[discardN].highlightOn({ 1, 1, 1 }, 0.1)
	end, 0.1, 20)
	Wait.time(function()
		Wait.time(function()
			cards[discardN].highlightOn({ 1, 0, 0 }, 0.05)
		end, 0.1, 10)
	end, 2)
	Wait.time(function()
		discardCard(cards[discardN], ply)
	end, 3)
end

function discardCard(card, playerColor)
	Player[playerColor].clearSelectedObjects()
	local gravPos = data[playerColor]["graveyard"].getPosition()
	local target = { x = gravPos.x, y = 3, z = gravPos.z }
	local cardRot = card.getRotation()
	cardRot.z = 0
	card.setRotationSmooth(cardRot, false, true)
	Wait.time(function()
		handTrigger(card)
		card.setPositionSmooth(target, false, true)
	end, 0.2)
	Wait.time(function()
		checkMoveSuccess(card, target, playerColor)
	end, 0.5)
end

