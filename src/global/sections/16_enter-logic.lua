---------------------------------- ENTER LOGIC ----------------------------------

-- which player's land zone is this, if any
function landZoneColor(zone)
	for color, _ in pairs(data) do
		if data[color]["landZone"] == zone then
			return color
		end
	end
	return nil
end

-- called from onObjectEnterZone (see context_menus.lua). Records a land that
-- entered a land zone and didn't start the turn there.
function trackLandEnter(zone, obj)
	-- ignore fetchland preview copies (see fetchland.lua)
	if obj ~= nil and obj.hasTag("FetchPreview") then
		return
	end
	-- a face-down card isn't a land on the battlefield (morph/manifest/face-down
	-- drop), even though its hidden name still matches cardIsLand
	if obj ~= nil and obj.is_face_down then
		return
	end
	local color = landZoneColor(zone)
	if color == nil or not cardIsLand(obj) then
		return
	end
	-- respect the owner's land-tracker setting
	if not getSetting(color, "landTracker") then
		return
	end
	-- wait for the card to come to rest before counting it: a card being drawn
	-- animates through the land zone without stopping, and must not be counted as
	-- a land played this turn. whenSettledInZone skips it if it left in transit.
	whenSettledInZone(obj, zone, function()
		registerLandEntered(color, obj)
	end)
end

-- record a land that has actually settled in a player's land zone this turn
function registerLandEntered(color, obj)
	-- re-check: it may have been flipped face-down between entering and settling
	if obj.is_face_down then
		return
	end
	local guid = obj.getGUID()
	-- ignore lands that were already in the zone when the turn began
	if landZoneBaseline[color] and landZoneBaseline[color][guid] then
		return
	end
	landsEnteredThisTurn[color] = landsEnteredThisTurn[color] or {}
	-- don't list the same card twice (e.g. nudged out and back in)
	for _, e in ipairs(landsEnteredThisTurn[color]) do
		if e.guid == guid then
			return
		end
	end
	table.insert(landsEnteredThisTurn[color], { guid = guid, name = mainCardName(obj.getName()) })
	-- glow the land grey until the end of the turn
	obj.highlightOn({ 0.5, 0.5, 0.5 })
	table.insert(glowingLands, obj)
	refreshLandTrackerText(color)
end

