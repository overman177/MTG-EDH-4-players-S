--------------------------------- LAND TRACKER ---------------------------------
-- Per-player land / mana display. This will eventually replace the standalone
-- Land_Zone_Manager object. For now it renders text anchored to each player's
-- playmat zone (same spot the old manager used) and tracks the lands that have
-- entered each player's land zone this turn.
--
-- "A land entering the battlefield this turn" = a land card (see cardIsLand) that
-- enters that player's landZone and was NOT in the landZone when their turn
-- began. The lands' names are listed in the display.

-- screen-space placement copied from the old Land_Zone_Manager.createButtons
landTrackerHeight = 0.10 -- local Y above the zone
landTrackerPosZ = 0.6 -- local Z (further "forward")
landTrackerSpacing = 0.05 -- gap between stacked lines

-- per-color state
landsEnteredThisTurn = {} -- color -> array of { guid, name } entered this turn
landZoneBaseline = {} -- color -> set of land guids present at this player's turn start
glowingLands = {} -- card objects currently glowing (lands played this turn)

-- create the display on every playmat zone and initialise tracking state
function spawnLandTrackerText()
	for color, _ in pairs(data) do
		createLandTrackerButtons(color)
		landsEnteredThisTurn[color] = {}
		landZoneBaseline[color] = {}
	end
	-- the active player's turn is already underway on load, so snapshot their
	-- baseline now (we missed their onPlayerTurnStart)
	if Turns ~= nil and Turns.turn_color ~= nil and data[Turns.turn_color] ~= nil then
		resetLandTracker(Turns.turn_color)
	end
	for color, _ in pairs(data) do
		refreshLandTrackerText(color)
	end
end

function createLandTrackerButtons(color)
	local mat = data[color]["playmat"]
	if mat == nil then
		return
	end
	-- Remove only the old land-tracker display, not third-party/helper buttons.
    local indices = {}
    for _, button in ipairs(mat.getButtons() or {}) do
        if button.click_function == "null" and
            (button.tooltip == "MTG_LandTracker" or
             (button.label or ""):find("Lands this turn", 1, true)) then
            table.insert(indices, button.index)
        end
    end
    table.sort(indices, function(a, b) return a > b end)
    for _, index in ipairs(indices) do mat.removeButton(index) end

	-- text is scaled by the inverse of the zone scale so it renders at a
	-- consistent size regardless of how big the playmat zone is
	local scale = mat.getScale()
	local textScale = { 1 / scale.x, 1 / scale.y, 1 / scale.z }

	-- White/Yellow display on the right, Blue/Red on the left (old layout)
	local posX = 0.5
	if color == "Blue" or color == "Red" then
		posX = -0.5
	end

	-- land-tracker display (index may vary when other modules add buttons)
	mat.createButton({
		click_function = "null",
		function_owner = Global,
		label = "Lands this turn: none",
        tooltip = "MTG_LandTracker",
		position = { posX, landTrackerHeight, landTrackerPosZ },
		scale = textScale,
		width = 0,
		height = 0,
		font_size = 250,
		font_color = { 1, 1, 1 },
	})
end

