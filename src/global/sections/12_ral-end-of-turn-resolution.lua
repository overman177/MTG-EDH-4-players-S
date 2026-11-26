-- End-of-turn cleanup of Ral cards and the Past in Flames helper.

------------------------- RAL END-OF-TURN RESOLUTION ---------------------------
-- When the Ral player's turn ends: clear the π note on every card we staged this
-- turn, then send uncast flashback (pif) cards that aren't in exile to the
-- graveyard, and uncast freecast (ult) cards that aren't in the graveyard to exile.
function ralEndOfTurnCleanup(color)
	if data[color] == nil then
		return
	end
	-- flashback cards stay if already exiled, otherwise return to the graveyard
	resolveRalCards(ralFlashbackCards[color], data[color]["exileZone"], data[color]["graveyard"])
	-- freecast cards stay if already in the graveyard, otherwise stay exiled
	resolveRalCards(ralFreecastCards[color], data[color]["graveyard"], data[color]["exileZone"])
	ralFlashbackCards[color] = {}
	ralFreecastCards[color] = {}
	-- reset this turn's storm / instants-sorceries counters too
	if ralCounts[color] ~= nil then
		ralCounts[color] = { storm = 0, spells = 0 }
		for _, def in ipairs(ralCounterDefs) do
			setCommandZoneButtonLabel(color, def.click_function, def.name .. ": 0")
		end
	end
end

-- clear each card's note, then move it to destZone unless it's already in keepZone
function resolveRalCards(cards, keepZone, destZone)
	for _, card in ipairs(cards or {}) do
		pcall(function()
			if card == nil then
				return
			end
			setCardNotepad(card, "")
			if not cardInZone(card, keepZone) then
				moveCardToZone(card, destZone)
			end
		end)
	end
end

----------------------------- PAST IN FLAMES (pif) -----------------------------
-- Move every instant/sorcery in the owner's graveyard to the spell row (same spot
-- as the ult), tagged "flashback". Nothing is exiled; non-spells stay put.
function playerPif(obj, clickerColor, alt)
	local owner = commandZoneOwnerOf(obj)
	if owner == nil then
		return
	end
	if clickerColor ~= owner then
		Player[clickerColor].broadcast("Only " .. owner .. " may use Past in Flames.")
		return
	end
	if ralPifRunning then
		return
	end
	ralPifRunning = true
	Wait.time(function()
		ralPifRunning = false
	end, 3)
	ralUltPlaced = 0
	ralFlashbackCards[owner] = ralFlashbackCards[owner] or {}

	local gy = data[owner] and data[owner]["graveyard"]
	if gy == nil then
		return
	end
	-- build a queue of "pullers"; each returns one instant/sorcery card object,
	-- whether it is loose in the graveyard or stacked inside a deck there
	local queue = {}
	for _, o in ipairs(mtgZoneObjects(gy)) do
		if o.type == "Card" then
			if cardIsInstantOrSorcery(o) then
				table.insert(queue, function()
					return o
				end)
			end
		elseif o.type == "Deck" then
			for _, e in ipairs(o.getObjects()) do
				if nameIsInstantOrSorcery(e.name) then
					table.insert(queue, function()
						local ok, card = pcall(function()
							return o.takeObject({ guid = e.guid, smooth = false })
						end)
						return ok and card or nil
					end)
				end
			end
		end
	end

	if #queue == 0 then
		Player[owner].broadcast("Past in Flames: no instants or sorceries in your graveyard.", owner)
		return
	end
	Player[owner].broadcast("Past in Flames: flashback for your graveyard instants & sorceries", owner)
	pifNext(owner, queue, 1)
end

-- process the queue one card at a time, waiting for each to settle before the next
function pifNext(color, queue, idx)
	if idx > #queue then
		return
	end
	local card = queue[idx]()
	if card == nil then
		pifNext(color, queue, idx + 1)
		return
	end
	Wait.condition(function()
		ralPlaceSpell(color, card, ralPifNote)
		Wait.time(function()
			pifNext(color, queue, idx + 1)
		end, 0.35)
	end, function()
		return not card.spawning
	end)
end
