-------------------------------- RAL ULTIMATE ----------------------------------
-- Exile the top 8 cards of the owner's library: instants & sorceries go into a
-- row on top of their board, everything else into their exile zone.
ralUltCount = 8
ralUltNote = "free to play until end of turn (ral ult)" -- written to each spell's π Notepad
ralPifNote = "flashback (past in flames)" -- ditto, for Past in Flames

-- button handler: owner-only, guarded against double-fire while cards animate
function playerRalUlt(obj, clickerColor, alt)
	local owner = commandZoneOwnerOf(obj)
	if owner == nil then
		return
	end
	if clickerColor ~= owner then
		Player[clickerColor].broadcast("Only " .. owner .. " may use Ral's ultimate.")
		return
	end
	if ralUltRunning then
		return
	end
	ralUltRunning = true
	Wait.time(function()
		ralUltRunning = false
	end, 3)
	ralUltPlaced = 0
	ralFreecastCards[owner] = ralFreecastCards[owner] or {}
	Player[owner].broadcast("Ral ultimate: exiling the top " .. ralUltCount .. " of your library", owner)
	ralUltNext(owner, ralUltCount)
end

-- pull the next top card and route it (instant/sorcery -> board row, else exile),
-- then continue until the requested count is reached or the library is empty
function ralUltNext(color, remaining)
	if remaining <= 0 then
		return
	end
	local card = getCardFromZone(data[color]["libraryZone"])
	if card == nil then
		return -- empty library
	end
	Wait.condition(function()
		if cardIsInstantOrSorcery(card) then
			ralPlaceSpell(color, card, ralUltNote)
		else
			ralUltExile(color, card)
		end
		Wait.time(function()
			ralUltNext(color, remaining - 1)
		end, 0.35)
	end, function()
		return not card.spawning
	end)
end

-- lay an instant/sorcery into the fanned-reveal layout above the library (same
-- placement the reveal buttons use) and tag it with the given π Notepad note
function ralPlaceSpell(color, card, note)
	local i = ralUltPlaced or 0
	ralUltPlaced = i + 1
	local pos = revealFanPos(color, i)
	checkPosMove(pos, data[color]["libraryZone"])
	card.setPositionSmooth(pos, false, true)
	card.setRotationSmooth(revealFanRot(color), false, true)
	setCardNotepad(card, note)
	-- track for end-of-turn resolution
	if note == ralUltNote then
		table.insert(ralFreecastCards[color], card)
	elseif note == ralPifNote then
		table.insert(ralFlashbackCards[color], card)
	end
end

-- send everything else to the owner's dedicated exile zone (cf. etaliExile)
function ralUltExile(color, card)
	moveCardToZone(card, data[color]["exileZone"])
end

-- drop a card face up at a zone's position (rotation-proof, like etaliExile)
function moveCardToZone(card, zone)
	if card == nil or zone == nil then
		return
	end
	local rot = card.getRotation()
	rot.z = 0
	rot.y = zone.getRotation().y
	local pos = zone.getPosition()
	pos.y = 3
	card.setRotationSmooth(rot, false, true)
	card.setPositionSmooth(pos, false, true)
end

-- is this card currently a loose object inside the given scripting zone?
function cardInZone(card, zone)
	if card == nil or zone == nil then
		return false
	end
	for _, o in ipairs(mtgZoneObjects(zone)) do
		if o == card then
			return true
		end
	end
	return false
end

