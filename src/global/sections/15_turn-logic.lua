----------------------------------- TURN LOGIC ----------------------------------

-- at the start of a player's turn the previous turn has ended, so stop the
-- glow on any lands played during it; then snapshot the lands already in the
-- starting player's land zone and clear their entered-this-turn list
function onPlayerTurnStart(player_color_start, player_color_previous)
	clearLandGlows()
	-- the previous player's turn just ended -- drop their Etali glow if it's theirs
	maybeClearEtaliGlows(player_color_previous)
	-- and resolve their staged Ral ult/pif cards
	ralEndOfTurnCleanup(player_color_previous)
	if data[player_color_start] ~= nil then
		resetLandTracker(player_color_start)
	end
end

-- turn off the glow on every land that was played this turn
function clearLandGlows()
	for _, card in ipairs(glowingLands) do
		if card ~= nil then
			pcall(function()
				card.highlightOff()
			end)
		end
	end
	glowingLands = {}
end

function resetLandTracker(color)
	landsEnteredThisTurn[color] = {}
	landZoneBaseline[color] = {}
	local zone = data[color]["landZone"]
	if zone ~= nil then
		for _, obj in ipairs(mtgZoneObjects(zone)) do
			if cardIsLand(obj) then
				landZoneBaseline[color][obj.getGUID()] = true
			end
		end
	end
	refreshLandTrackerText(color)
end

