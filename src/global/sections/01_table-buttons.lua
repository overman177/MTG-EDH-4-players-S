-- Physical buttons, numbered shortcuts and moving selected cards between game zones.

--------------------------------- Table buttons --------------------------------
function buildTableButtons()
	-- support variables
	nAlt = 3
	drawDelay = 0.1 -- changing the draw delay might cause problems
	for color, playerData in pairs(data) do
        if playerData["drawButton"] ~= nil then
            createTableButton(playerData["drawButton"], "Draw", "playerDraw", "Draw")
        end
        if playerData["scryButton"] ~= nil then
            createTableButton(playerData["scryButton"], "Scry", "playerScry", "Scry")
        end
        if playerData["millButton"] ~= nil then
            createTableButton(playerData["millButton"], "Mill", "playerMill", "Mill")
        end
        if playerData["untapButton"] ~= nil then
            createTableButton(playerData["untapButton"], "Untap", "playerUntap", "Untap")
        end
        if playerData["mulliganButton"] ~= nil then
            createTableButtonM(playerData["mulliganButton"], "Mulligan", "playerMulligan", "Mulligan")
        end
        if playerData["revealButton"] ~= nil then
            createTableButtonR(playerData["revealButton"])
        end
		data[color]["mulliganNumber"] = 7
		data[color]["mulliganCount"] = 0

        if playerData["drawButton"] ~= nil then
            playerData["drawButton"].max_typed_number = 99
        end
        if playerData["scryButton"] ~= nil then
            playerData["scryButton"].max_typed_number = 99
        end
        if playerData["millButton"] ~= nil then
            playerData["millButton"].max_typed_number = 99
        end
        if playerData["revealButton"] ~= nil then
            playerData["revealButton"].max_typed_number = 99
        end
	end
end

-- Use the destination's actual transform rather than a library-relative offset.
-- Graveyard/exile cards go face-up; empty-library fallback cards go face-down.
function mtgGetZonePlacement(playerColor, key, height, faceDown)
    local playerData = data and data[playerColor]
    local zone = playerData and playerData[key]
    if zone == nil then return nil, nil end
    local pos = zone.getPosition()
    pos.y = height or 3
    local zoneRot = zone.getRotation()
    local rot = { x = 0, y = zoneRot.y, z = faceDown and 180 or 0 }
    return pos, rot
end

-- Treat a typed number on an action button as a request to repeat that action.
function onObjectNumberTyped(obj, ply, int)
	local txt = " card"
	if int > 1 then
		txt = " cards"
	end
	-- drawing a full 7 straight off your own deck with an empty hand counts as
	-- taking a hand, so bump the mulligan counter (default deal still happens)
	if int == 7 and data[ply] ~= nil and obj == getDeckFromZone(data[ply]["libraryZone"]) and handIsEmpty(ply) then
		bumpMulliganCount(ply)
	end
	for color, playerData in pairs(data) do
		if obj == playerData["drawButton"] and color == ply then
			local deck = getDeckFromZone(playerData["libraryZone"])
			if deck == nil then
				return
			end
			if int > deck.getQuantity() then
				int = deck.getQuantity()
			end
			if int > 0 then
				Player[ply].broadcast("drawing " .. int .. txt, ply)
				Wait.time(function()
					draw1(ply)
				end, drawDelay, int)
			end
		end
		if obj == playerData["scryButton"] and color == ply then
			local deck = getDeckFromZone(playerData["libraryZone"])
			if deck == nil then
				return
			end
			if int > deck.getQuantity() then
				int = deck.getQuantity()
			end
			if int > 0 then
				Player[ply].broadcast("scrying " .. int .. txt, ply)
				Wait.time(function()
					scry1(ply)
				end, drawDelay, int)
			end
		end
		if obj == playerData["millButton"] and color == ply then
			local deck = getDeckFromZone(playerData["libraryZone"])
			if deck == nil then
				return
			end
			if int > deck.getQuantity() then
				int = deck.getQuantity()
			end
			if int > 0 then
				Player[ply].broadcast("milling " .. int .. txt, ply)
				Wait.time(function()
					mill1(ply)
				end, drawDelay, int)
			end
		end
		if obj == playerData["revealButton"] and color == ply then
			local deck = getDeckFromZone(playerData["libraryZone"])
			if deck == nil then
				return
			end
			if int > deck.getQuantity() then
				int = deck.getQuantity()
			end
			if int > 0 then
				Player[ply].broadcast("revealing " .. int .. txt, ply)
				if obj.getRotation().z == 0 then
					Wait.time(function()
						revealFan(obj, ply)
					end, drawDelay, int)
				elseif obj.getRotation().z == 180 then
					Wait.time(function()
						revealStack(obj, ply)
					end, drawDelay, int)
				end
			end
		end
	end
end

-- Attach a physical button and its click handler to the object.
function createTableButton(object, name, clickFunction, ttip)
	object.tooltip = false
	object.interactable = true
	object.setLock(true)
	object.setName(name)
	if name == "Untap" then
		ttip = "[b]" .. ttip .. "[/b]"
	else
		ttip = "                  [b]"
			.. ttip
			.. "[/b]"
			.. "\n       [i]left click[/i] for 1 card"
			.. "\n     [i]right click[/i] for "
			.. tostring(nAlt)
			.. " cards\nor [i]type[/i] the desired amount"
	end
	return object.createButton({
		click_function = clickFunction,
		tooltip = ttip,
		width = 600,
		height = 600,
		position = { 0, 0.1, 0 },
		font_size = 250,
		color = { 1, 1, 1, 0 },
		font_color = { 1, 1, 1, 100 },
	})
end

function createTableButtonM(object, name, clickFunction, ttip)
	object.tooltip = false
	-- Buttons must remain interactable; setLock prevents the token moving.
	object.interactable = true
	object.setLock(true)
	object.setName(name)
	object.createButton({
		click_function = clickFunction,
		tooltip = "           [b]Mulligan[/b]\n  [i]left click[/i] to mulligan\n  [i]right click[/i] to reset count",
		width = 2500,
		height = 850,
		position = { 0, 0.1, 0 },
		font_size = 250,
		color = { 1, 1, 1, 0 },
		font_color = { 1, 1, 1, 100 },
		hover_color = { 1, 1, 1, 0.1 },
		press_color = { 1, 0, 0, 0.2 },
	})
	-- mulligan counter label below the button (noop click = display only)
	-- Note: kept at index 1 so playerMulligan's editButton({ index = 1 }) updates it
	object.createButton({
		click_function = "noop",
		label = "Mulligans: 0",
		width = 0,
		height = 0,
		position = { 0, 0.1, 1.4 },
		font_size = 600,
		font_color = { 1, 1, 1, 100 },
	})
	-- serum powder button, shifted sideways from the mulligan button.
	-- Aim at a world point offset along x and convert it into local space
	-- (positionToLocal handles each token's rotation for us).
	local sideShift = 3
	local wpos = object.getPosition()
	local targetWorld = Vector(wpos.x + (wpos.x > 0 and sideShift or -sideShift), wpos.y, wpos.z)
	local lp = object.positionToLocal(targetWorld)
	object.createButton({
		click_function = "playerSerumPowder",
		label = "Serum Powder",
		tooltip = "         [b]Serum Powder[/b]\n[i]left click[/i] to exile your hand and\n   draw a new one of the same size",
		width = 4000,
		height = 1000,
		position = { lp.x, 0.1, lp.z },
		font_size = 500,
		color = { 1, 1, 1, 0 },
		font_color = { 1, 1, 1, 100 },
		hover_color = { 1, 1, 1, 0.1 },
		press_color = { 1, 0, 0, 0.2 },
	})
	-- (the Etali button is no longer here -- it spawns under the command zone only
	-- when a player starts a game with Etali, Primal Conqueror as their commander;
	-- see etali.lua)
	-- reset button, directly under the mulligan counter (z = 1.4)
	object.createButton({
		click_function = "playerReset",
		label = "Reset",
		tooltip = "              [b]Reset Board[/b]\n[i]double-click[/i] to restore your library,\n   board, and commander to game start",
		width = 2500,
		height = 700,
		position = { 0, 0.1, 2.8 },
		font_size = 250,
		color = { 1, 1, 1, 0 },
		font_color = { 1, 1, 1, 100 },
		hover_color = { 1, 1, 1, 0.1 },
		press_color = { 1, 0, 0, 0.2 },
	})
	-- the keep / pregame button no longer lives here -- it's created directly at the
	-- centre of each player's playmat by spawnKeepButtons (see pregame.lua).
end

-- Intentionally do nothing; display-only buttons still need a callback.
function noop() end

-- Create the two reveal modes on opposite faces of one physical button.
function createTableButtonR(object)
	object.tooltip = false
	object.interactable = true
	rot = object.getRotation()
	rot[3] = 0
	object.setRotation(rot)
	object.setLock(true)
	object.setName("Reveal")
	object.memo = tostring(os.time())
	object.setGMNotes("0")
	return object.createButton({
		click_function = "revealFan",
		tooltip = "                  [b]fanned-out reveal[/b]\n[i]left click[/i] or [i]type[/i] number to reveal cards\n       [i]right click[/i] to swap button mode",
		function_owner = self,
		width = 600,
		height = 600,
		position = { 0, 0.1, 0 },
		color = { 1, 1, 1, 0 },
	}),
		object.createButton({
			click_function = "revealStack",
			tooltip = "                     [b]stacked reveal[/b]\n[i]left click[/i] or [i]type[/i] number to reveal cards\n       [i]right click[/i] to swap button mode",
			function_owner = self,
			width = 600,
			height = 600,
			position = { 0, -0.1, 0 },
			rotation = { 0, 0, 180 },
			color = { 1, 1, 1, 0 },
			font_color = { 1, 1, 1, 100 },
		})
end

-- Numbered TTS scripting shortcuts.
function onScriptingButtonDown(index, playerColor)
	if index == 10 then
		if Turns.enable then
			if playerColor == Turns.turn_color then
				Player[playerColor].broadcast("keybind 0: end turn", { 0.7, 0.7, 0.7 })
				Turns.turn_color = Turns.getNextTurnColor()
			end
		else
			Player[playerColor].broadcast("keybind 0: enable turns", { 0.7, 0.7, 0.7 })
			Turns.enable = true
			Turns.turn_color = playerColor
		end
	elseif index == 1 then
		Player[playerColor].broadcast("keybind 1: untap", { 0.7, 0.7, 0.7 })
		playerUntap(data[playerColor]["untapButton"], playerColor, false)
	elseif index == 2 then
		Player[playerColor].broadcast("keybind 2: draw", { 0.7, 0.7, 0.7 })
		playerDraw(data[playerColor]["drawButton"], playerColor, false)
	elseif index == 3 then
		Player[playerColor].broadcast("keybind 3: scry", { 0.7, 0.7, 0.7 })
		playerScry(data[playerColor]["scryButton"], playerColor, false)
	elseif index == 4 then
		Player[playerColor].broadcast("keybind 4: mill", { 0.7, 0.7, 0.7 })
		playerMill(data[playerColor]["millButton"], playerColor, false)
	elseif index == 5 then
		Player[playerColor].broadcast("keybind 5: revealFan", { 0.7, 0.7, 0.7 })
		local obj = data[playerColor]["revealButton"]
		revealFan(obj, playerColor)
	elseif index == 6 then
		Player[playerColor].broadcast("keybind 6: revealStack", { 0.7, 0.7, 0.7 })
		local obj = data[playerColor]["revealButton"]
		revealStack(obj, playerColor)
	elseif index == 7 then
		Player[playerColor].broadcast("keybind 7: move to graveyard", { 0.7, 0.7, 0.7 })
		move2grav(playerColor)
	elseif index == 8 then
		Player[playerColor].broadcast("keybind 8: move to exile", { 0.7, 0.7, 0.7 })
		move2exile(playerColor)
	elseif index == 9 then
		Player[playerColor].broadcast("keybind 9: move to bottom of library", { 0.7, 0.7, 0.7 })
		move2botLib(playerColor)
	end
end

-- Collect selected or hovered cards and place them under the player's library.
function move2botLib(ply)
	local objs = Player[ply].getSelectedObjects()
	local cards = {}
	for _, obj in pairs(objs) do
		if obj.type == "Card" or obj.type == "Deck" then
			local rot = obj.getRotation()
			rot[3] = 180
			obj.setRotationSmooth(rot, false, true)
			table.insert(cards, obj)
		end
	end
	Wait.time(function()
		if #cards > 1 then
			targpos = vector(0, 0, 0)
			for _, c in pairs(cards) do
				targpos = targpos + c.getPosition()
			end
			targpos = targpos:scale(1 / #cards)
			for _, c in pairs(cards) do
				c.setPositionSmooth(targpos, false, true)
			end
		end
		local gr = group(cards)
		gr = gr[1]
		if gr == nil then
			pcall(function()
				gr = hoveredObjs[ply]
			end)
		end
		if gr == nil or not (gr.type == "Card" or gr.type == "Deck") then
			return
		end
		local rot = gr.getRotation()
		rot[3] = 180
		gr.interactable = false
		gr.use_gravity = false
		gr.shuffle()
		local deck = getDeckFromZone(data[ply]["libraryZone"])
		if deck == nil then
			deck = getCardFromZone(data[ply]["libraryZone"])
		end
		Wait.time(function()
			gr.use_gravity = true
			gr.interactable = true
			gr.shuffle()
			if gr.type == "Card" then
				handTrigger(gr)
			end
			gr.shuffle()
			if deck ~= nil then
				local pos = deck.getPosition()
				pos[2] = 1
				gr.setPositionSmooth(pos, false, true)
				gr.setRotationSmooth(deck.getRotation(), false, true)
				deck.setPositionSmooth(deck.getPosition() + Vector(0, 2, 0), false, true)
			else
				local pos, rot = mtgGetZonePlacement(ply, "libraryZone", 1, true)
				if pos == nil then return end
				gr.setRotationSmooth(rot, false, true)
				gr.setPositionSmooth(pos, false, true)
			end
		end, 1)
	end, 0.25)
end

hoveredObjs = {}
-- Remember the last object hovered by each player for shortcuts without a selection.
function onObjectHover(ply, obj)
	hoveredObjs[ply] = obj
end

-- Move selected or hovered cards to the player's graveyard.
function move2grav(ply)
	local objs = Player[ply].getSelectedObjects()
	local cards = {}
	for _, obj in pairs(objs) do
		if obj.type == "Card" or obj.type == "Deck" then
			table.insert(cards, obj)
		end
	end
	local gr = group(cards)
	gr = gr[1]
	if gr == nil then
		pcall(function()
			gr = hoveredObjs[ply]
		end)
	end
	if gr == nil or not (gr.type == "Card" or gr.type == "Deck") then
		return
	end
	gr.interactable = false
	gr.use_gravity = false
	Wait.time(function()
		gr.interactable = true
		gr.use_gravity = true
		if gr.type == "Card" then
			handTrigger(gr)
		end
		local pos, rot = mtgGetZonePlacement(ply, "graveyard", 3, false)
		if pos == nil then return end
		gr.setRotationSmooth(rot, false, true)
		gr.setPositionSmooth(pos, false, true)
	end, 1)
end

-- Move selected or hovered cards to the player's exile zone.
function move2exile(ply)
	local objs = Player[ply].getSelectedObjects()
	local cards = {}
	for _, obj in pairs(objs) do
		if obj.type == "Card" or obj.type == "Deck" then
			table.insert(cards, obj)
		end
	end
	local gr = group(cards)
	gr = gr[1]
	if gr == nil then
		pcall(function()
			gr = hoveredObjs[ply]
		end)
	end
	if gr == nil or not (gr.type == "Card" or gr.type == "Deck") then
		return
	end
	gr.interactable = false
	gr.use_gravity = false
	Wait.time(function()
		gr.interactable = true
		gr.use_gravity = true
		if gr.type == "Card" then
			handTrigger(gr)
		end
		local pos, rot = mtgGetZonePlacement(ply, "exileZone", 3, false)
		if pos == nil then return end
		gr.setRotationSmooth(rot, false, true)
		gr.setPositionSmooth(pos, false, true)
	end, 1)
end

