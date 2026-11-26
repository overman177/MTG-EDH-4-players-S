-- Serum Powder's separate hand replacement flow.

-------------------------------- Serum Powder ----------------------------------
-- Exile the current hand and draw a fresh one of the same size.
-- Hand size = min(7, 7 + 2 - mulliganCount). mulliganCount is the displayed
-- mulligan number + 1, so the opening hand and the first mulligan both draw 7,
-- then it drops by one per additional mulligan.
function playerSerumPowder(button, playerColor, alt)
	if button ~= data[playerColor]["mulliganButton"] then
		warnNotYours(button, playerColor)
		return
	end
	if data[playerColor]["serumCooldown"] then
		return
	end

	local handSize = math.min(7, 7 + 2 - (data[playerColor]["mulliganCount"] or 0))

	-- step 1: the hand must hold exactly handSize cards before powdering
	local cards = {}
	for _, obj in pairs(Player[playerColor].getHandObjects(1)) do
		if obj.tag == "Card" then
			table.insert(cards, obj)
		end
	end
	if #cards ~= handSize then
		Player[playerColor].broadcast(
			"Serum Powder: expected " .. handSize .. " cards in hand but found " .. #cards .. "."
		)
		return
	end

	-- there must actually be a Serum Powder card in hand to powder
	local hasPowder = false
	for _, card in ipairs(cards) do
		if mainCardName(card.getName()):lower() == "serum powder" then
			hasPowder = true
			break
		end
	end
	if not hasPowder then
		Player[playerColor].broadcast("Serum Powder: no Serum Powder card in your hand.")
		return
	end

	local deck = getDeckFromZone(data[playerColor]["libraryZone"])
	if deck == nil then
		Player[playerColor].broadcast("Serum Powder: no library found.")
		return
	end

	data[playerColor]["serumCooldown"] = true
	Wait.time(function()
		data[playerColor]["serumCooldown"] = false
	end, 2)
	buttonPress(button, 0.5)

	-- step 2: exile the current hand (stacked on the dedicated exile zone, which
	-- keeps placement correct regardless of how the zones are rotated)
	local exilePos, exileRot = mtgGetZonePlacement(playerColor, "exileZone", 3, false)
	if exilePos == nil then
		Player[playerColor].broadcast("Serum Powder: exile zone not found.")
		return
	end
	local i = 0
	for _, card in pairs(cards) do
		card.use_hands = false
		card.use_gravity = true
		card.setRotationSmooth(exileRot, false, true)
		card.setPositionSmooth({ x = exilePos.x, y = exilePos.y + i * 0.4, z = exilePos.z }, false, true)
		i = i + 1
	end
	Wait.time(function()
		for _, card in pairs(cards) do
			if card ~= nil then
				card.use_hands = true
			end
		end
	end, 1.5)

	-- step 3: draw a fresh hand of the same size
	Wait.time(function()
		deck.deal(handSize, playerColor, 1)
	end, 1.0)
end

