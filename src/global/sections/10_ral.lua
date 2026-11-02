------------------------------------- RAL --------------------------------------
-- "Ral, Monsoon Mage" gets a small button cluster by the command zone, present
-- only when a game starts with Ral in the command zone (see command_buttons.lua)
-- and cleared at the next game start without Ral.
--
-- Top row = two clickable counters (Strm = storm, Ral = instants/sorceries cast),
-- centred over the bottom row of three ability buttons (flip + two placeholders).
-- Counters left-click +1, right-click -1, clamped at 0, like commander tax but in
-- steps of one.

RAL_COMMANDER_NAME = "Ral, Monsoon Mage"

-- layout (tune to taste). Columns are spaced along the zone's right axis, rows
-- along its forward axis.
ralColGap = 1.7 -- horizontal gap between adjacent columns (world units)
ralRowOffset = 0.4 -- half the vertical gap between the two rows
ralButtonWidth = 900
ralButtonHeight = 425
ralButtonFont = 210

-- the bottom-row ability buttons (left to right). flip works; rest are placeholders.
ralAbilities = {
	{
		click_function = "playerCoinFlip",
		label = "flip",
		tooltip = "                  [b]Ral, Monsoon Mage[/b]\n[i]left click[/i] to flip a coin",
	},
	{
		click_function = "playerRalUlt",
		label = "ult",
		tooltip = "                  [b]Ral ultimate[/b]\nexile the top 8 of your library;\ninstants & sorceries go to a row\non top of your board",
	},
	{
		click_function = "playerPif",
		label = "pif",
		tooltip = "                  [b]Past in Flames[/b]\nmove instants & sorceries from your\ngraveyard to a row on top of your board\n(flashback)",
	},
}

-- the top-row counters (left to right: storm, instants/sorceries)
ralCounterDefs = {
	{ key = "storm", name = "Strm", click_function = "ralStormCounter" },
	{ key = "spells", name = "Ral", click_function = "ralSpellCounter" },
}

-- per-color counter values, (re)set to zero whenever the grid is spawned
ralCounts = {}

-- cards staged by the ult (freecast) and pif (flashback) this turn, per color, so
-- they can be resolved when that player's turn ends (see ralEndOfTurnCleanup)
ralFreecastCards = {}
ralFlashbackCards = {}

-- game-start hook: present the Ral grid iff the player has Ral in their command
-- zone right now. Clear first so a reload can't leave duplicates.
function refreshRalButton(color)
	if data[color] == nil then
		return
	end
	-- clear every Ral button (abilities + counters) so a reload can't duplicate them
	for _, b in ipairs(ralAbilities) do
		removeCommandZoneButton(color, b.click_function)
	end
	for _, def in ipairs(ralCounterDefs) do
		removeCommandZoneButton(color, def.click_function)
	end
	if not getSetting(color, "commanderQOL") or not commandZoneHasCommander(color, RAL_COMMANDER_NAME) then
		return
	end
	ralCounts[color] = { storm = 0, spells = 0 }
	addRalGrid(color)
end

-- place the cluster: top row = two counters (centred), bottom row = three
-- abilities. The zone's forward axis is inverted here (the cluster is built under
-- the zone), so the top row uses -ralRowOffset and the bottom row +ralRowOffset.
function addRalGrid(color)
	-- top row: the two counters, centred over the three abilities below
	local counterCols = { -ralColGap / 2, ralColGap / 2 }
	for i, def in ipairs(ralCounterDefs) do
		addCommandZoneButton(color, {
			click_function = def.click_function,
			label = def.name .. ": " .. ralCounts[color][def.key],
			tooltip = def.name .. " -- [i]left click[/i] +1, [i]right click[/i] -1",
			right = counterCols[i],
			forward = -ralRowOffset,
			width = ralButtonWidth,
			height = ralButtonHeight,
			font_size = ralButtonFont,
		})
	end
	-- bottom row: the three ability buttons, centred on the zone
	local abilityCols = { -ralColGap, 0, ralColGap }
	for i, b in ipairs(ralAbilities) do
		addCommandZoneButton(color, {
			click_function = b.click_function,
			label = b.label,
			tooltip = b.tooltip,
			right = abilityCols[i],
			forward = ralRowOffset,
			width = ralButtonWidth,
			height = ralButtonHeight,
			font_size = ralButtonFont,
		})
	end
end

-- bump a counter by delta (clamped at 0) and refresh its label
function ralBump(color, def, delta)
	if ralCounts[color] == nil then
		return
	end
	ralCounts[color][def.key] = math.max(0, ralCounts[color][def.key] + delta)
	setCommandZoneButtonLabel(color, def.click_function, def.name .. ": " .. ralCounts[color][def.key])
end

-- adjust one counter (+1 left click, -1 right click, clamped at 0) and refresh
-- its label. Like commander tax, anyone at the table may click it.
function ralAdjustCounter(obj, alt, def)
	local owner = commandZoneOwnerOf(obj)
	if owner == nil then
		return
	end
	ralBump(owner, def, alt and -1 or 1)
end

function ralStormCounter(obj, color, alt)
	ralAdjustCounter(obj, alt, ralCounterDefs[1])
end

-- the instants/sorceries counter also feeds storm, so adjust both by the same step
function ralSpellCounter(obj, color, alt)
	local owner = commandZoneOwnerOf(obj)
	if owner == nil then
		return
	end
	local delta = alt and -1 or 1
	ralBump(owner, ralCounterDefs[2], delta) -- instants/sorceries
	ralBump(owner, ralCounterDefs[1], delta) -- also bump storm
end

-- placeholder Ral abilities -- no-op until they're implemented
function ralPlaceholder() end

-- button handler: only the owning player may flip. A tails costs the flipper
-- 1 life. Announce the result to the table. (Counters are not auto-bumped.)
function playerCoinFlip(obj, clickerColor, alt)
	local ownerColor = commandZoneOwnerOf(obj)
	if ownerColor == nil then
		return
	end
	if clickerColor ~= ownerColor then
		Player[clickerColor].broadcast("Only " .. ownerColor .. " may flip this coin.")
		return
	end
	if math.random(2) == 1 then
		broadcastToAll(ownerColor .. " flips a coin: Heads", stringColorToRGB(ownerColor))
	else
		loseLife(ownerColor, 1, "coin flip") -- tails: the flipper loses 1 life
		broadcastToAll(ownerColor .. " flips a coin: Tails (-1 life)", stringColorToRGB(ownerColor))
	end
end

