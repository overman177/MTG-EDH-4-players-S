-- Opening hands, mulligan counts and new-game safeguards.

----------------------------------- MULLIGAN -----------------------------------
mulliganResetDelay = 300 -- auto-reset the count after this many seconds idle

-- Increase the mulligan count and refresh the displayed label.
function bumpMulliganCount(color)
	-- a bump while the count sits at 0 is a fresh opening hand (the very first one,
	-- or the first after a right-click / inactivity reset): (re)snapshot the board
	-- for the reset button while the library is still complete (see reset.lua)
	if (data[color]["mulliganCount"] or 0) == 0 then
		captureResetSnapshot(color, true)
		-- show/hide this player's commander buttons based on their command zone now
		refreshEtaliButton(color)
		refreshRalButton(color)
		refreshObNixButton(color)
		-- deal goblin sticker cards if their commander is "_____ Goblin" (once)
		refreshGoblinStickers(color)
	end
	data[color]["mulliganCount"] = (data[color]["mulliganCount"] or 0) + 1
	data[color]["mulliganButton"].editButton({
		index = 1,
		label = "Mulligans: " .. (data[color]["mulliganCount"] - 1),
	})
	-- restart the idle timer: if the count isn't touched again in time, reset it
	if data[color]["mulliganResetTimer"] ~= nil then
		Wait.stop(data[color]["mulliganResetTimer"])
	end
	data[color]["mulliganResetTimer"] = Wait.time(function()
		resetMulliganCount(color)
	end, mulliganResetDelay)
end

-- reset a player's mulligan counter to 0 and cancel any pending idle timer
function resetMulliganCount(color)
	if data[color]["mulliganResetTimer"] ~= nil then
		Wait.stop(data[color]["mulliganResetTimer"])
		data[color]["mulliganResetTimer"] = nil
	end
	data[color]["mulliganCount"] = 0
	data[color]["mulliganButton"].editButton({ index = 1, label = "Mulligans: 0" })
	-- re-arm the keep/pregame flow for a fresh game
	resetKeepState(color)
end

-- Check whether the first hand zone contains any cards.
function handIsEmpty(color)
	for _, obj in pairs(Player[color].getHandObjects(1)) do
		if obj.tag == "Card" then
			return false
		end
	end
	return true
end

-- Handle opening hands, mulligans and manual count reset from the physical button.
function playerMulligan(button, playerColor, alt)
	-- identify which player's mulligan button was clicked (not necessarily the clicker)
	local ownerColor = nil
	for color, pdata in pairs(data) do
		if button == pdata["mulliganButton"] then
			ownerColor = color
			break
		end
	end
	if ownerColor ~= nil then
		if alt then
			-- right-click: anyone may reset this player's mulligan count
			resetMulliganCount(ownerColor)
			-- re-arm goblin stickers so the next opening hand re-deals (manual reset
			-- only -- the inactivity timer must not wipe stickers mid-game)
			data[ownerColor]["goblinStickersDealt"] = nil
			return
		end
		-- left-click: only the owning player may mulligan their own hand
		if playerColor ~= ownerColor then
			warnNotYours(button, playerColor)
			return
		end
		-- with cards already in the play area, require a double-click so an
		-- accidental mid-game press doesn't wipe the board into a mulligan
		local cardsInPlay = false
		for _, v in pairs(mtgZoneObjects(data[playerColor]["playmat"])) do
			if v.type == "Card" or v.type == "Deck" then
				cardsInPlay = true
				break
			end
		end
		if cardsInPlay and not isDoubleClick("mull_" .. playerColor) then
			Player[playerColor].broadcast(
				"Cards detected in the play area = accidental mulligan press in the middle of a game?\n"
					.. "If you still wish to mulligan, [b]double click[/b] the button."
			)
			return
		end

		buttonCooldown(button, 2)

		local deck = getDeckFromZone(data[playerColor]["libraryZone"])
		if deck ~= nil then
			data[playerColor]["mulliganNumber"] = 7
			-- first click draws the opening hand (0 mulligans); each later click is a mulligan
			bumpMulliganCount(playerColor)
			local objs = Player[playerColor].getHandObjects(1)
			for _, obj in pairs(objs) do
				if obj.tag == "Card" then
					deck.putObject(obj)
				end
			end
			Wait.time(function()
				deck.shuffle()
			end, 0.1, 7)

			Wait.time(function()
				if smartMulligan then -- ensure 2-5 lands in hand
					local nMulls = 0
					local keepTrying = true
					while keepTrying do
						nMulls = nMulls + 1
						deck.shuffle()
						local nLands = 0
						local cards = deck.getObjects()
						for i = 1, 7 do
							if cards[i].name:lower():find("land") then
								nLands = nLands + 1
							end
						end
						if (nLands >= 3 and nLands <= 4) or nMulls >= 3 then
							keepTrying = false
						end
					end
				end
				deck.deal(data[playerColor]["mulliganNumber"], playerColor, 1)
			end, 0.8)
			-- Wait.time(function() sortHands(playerColor) end, 1.5)
		end
	end
end

