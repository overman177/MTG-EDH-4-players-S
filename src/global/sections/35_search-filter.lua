-------------------------------- SEARCH FILTER ---------------------------------
-- The player panel scrolls; the search box at the top filters it. Each setting
-- row has a stable id (row_<key>) plus a bag of keywords. Typing hides every row
-- whose keywords don't contain the query, and hides the section headers while a
-- query is active (they'd otherwise float above empty space).
settingsSearchRows = {
	{ id = "row_oppDrawTriggers", text = "opponent draw trigger alerts triggers" },
	{ id = "row_drawSkipReminder", text = "draw step skip reminder state based" },
	{ id = "row_abilityRestrictions", text = "cant activate ability reminder cannot state based" },
	{ id = "row_searchRestrictions", text = "tutor search restriction blocks fetch state based" },
	{ id = "row_cmdrDamageAutoLife", text = "commander damage adjusts life automation" },
	{ id = "row_seedbornUntap", text = "seedborn muse untap state based" },
	{ id = "row_dfcLandFlip", text = "flip dfc double faced land face automation" },
	{ id = "row_fetchSurveil", text = "fetched land surveil scry automation fetch" },
	{ id = "row_fetchEntersTapped", text = "fetched land enters tapped automation fetch" },
	{ id = "row_landTracker", text = "land entered tracker display" },
	{ id = "row_fetchPreviews", text = "fetchland previews display fetch" },
	{ id = "row_fetchFromClone", text = "show all possible fetchables clone display fetch" },
	{ id = "row_ownerHighlight", text = "highlight foreign cards owner belongs other player mat glow display" },
	{ id = "row_commanderQOL", text = "commander qol buttons etali ral" },
	{ id = "row_keywordTokens", text = "keyword tokens frozen flying apply drop card game" },
	{ id = "row_goblinStickers", text = "goblin stickers game" },
	{ id = "row_keepPregameFlow", text = "keep pregame flow game" },
	{ id = "row_revealResetSecs", text = "reveal reset seconds misc" },
}

settingsSearchHeaders = {
	"hdr_triggers", "hdr_stateBased", "hdr_automation",
	"hdr_display", "hdr_commander", "hdr_game", "hdr_misc",
}

-- restore every row + header to visible (no active query)
function clearSettingsSearch()
	for _, r in ipairs(settingsSearchRows) do
		UI.setAttribute(r.id, "active", "true")
	end
	for _, h in ipairs(settingsSearchHeaders) do
		UI.setAttribute(h, "active", "true")
	end
end

-- InputField handler: filter the panel to rows matching the query. Headers are
-- hidden while filtering since a section may end up empty.
function settingsSearch(player, value, id)
	local q = (value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if q == "" then
		clearSettingsSearch()
		return
	end
	for _, h in ipairs(settingsSearchHeaders) do
		UI.setAttribute(h, "active", "false")
	end
	for _, r in ipairs(settingsSearchRows) do
		UI.setAttribute(r.id, "active", r.text:find(q, 1, true) ~= nil and "true" or "false")
	end
end

-- host panel mirrors the player panel: same row ids prefixed "hostrow_", same
-- keyword bags. The legend row is never hidden so the ENF/ON columns stay labelled.
hostSearchRows = {
	{ id = "hostrow_oppDrawTriggers", text = "opponent draw trigger alerts triggers" },
	{ id = "hostrow_drawSkipReminder", text = "draw step skip reminder state based" },
	{ id = "hostrow_abilityRestrictions", text = "cant activate ability reminder cannot state based" },
	{ id = "hostrow_searchRestrictions", text = "tutor search restriction blocks fetch state based" },
	{ id = "hostrow_cmdrDamageAutoLife", text = "commander damage adjusts life automation" },
	{ id = "hostrow_seedbornUntap", text = "seedborn muse untap state based" },
	{ id = "hostrow_dfcLandFlip", text = "flip dfc double faced land face automation" },
	{ id = "hostrow_fetchSurveil", text = "fetched land surveil scry automation fetch" },
	{ id = "hostrow_fetchEntersTapped", text = "fetched land enters tapped automation fetch" },
	{ id = "hostrow_landTracker", text = "land entered tracker display" },
	{ id = "hostrow_fetchPreviews", text = "fetchland previews display fetch" },
	{ id = "hostrow_fetchFromClone", text = "show all possible fetchables clone display fetch" },
	{ id = "hostrow_ownerHighlight", text = "highlight foreign cards owner belongs other player mat glow display" },
	{ id = "hostrow_commanderQOL", text = "commander qol buttons etali ral" },
	{ id = "hostrow_keywordTokens", text = "keyword tokens frozen flying apply drop card game" },
	{ id = "hostrow_goblinStickers", text = "goblin stickers game" },
	{ id = "hostrow_keepPregameFlow", text = "keep pregame flow game" },
}

hostSearchHeaders = {
	"hosthdr_triggers", "hosthdr_stateBased", "hosthdr_automation",
	"hosthdr_display", "hosthdr_commander", "hosthdr_game",
}

function clearHostSettingsSearch()
	for _, r in ipairs(hostSearchRows) do
		UI.setAttribute(r.id, "active", "true")
	end
	for _, h in ipairs(hostSearchHeaders) do
		UI.setAttribute(h, "active", "true")
	end
end

function hostSettingsSearch(player, value, id)
	local q = (value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if q == "" then
		clearHostSettingsSearch()
		return
	end
	for _, h in ipairs(hostSearchHeaders) do
		UI.setAttribute(h, "active", "false")
	end
	for _, r in ipairs(hostSearchRows) do
		UI.setAttribute(r.id, "active", r.text:find(q, 1, true) ~= nil and "true" or "false")
	end
end

