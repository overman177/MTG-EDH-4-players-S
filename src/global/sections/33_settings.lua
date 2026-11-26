-- Player and host preference defaults and effective setting lookup.

--------------------------------- SETTINGS -------------------------------------
-- Per-player settings. Each player opens a private settings panel from the gear
-- button in their UI; the panel is shown only to them via the same visibility
-- rules the Scryfall panels use (visibleOpenRules / visibleCloseRules). Values
-- are stored per colour in playerSettings and persisted across save/load.
--
-- Note: the panel is a single shared widget set. A toggle always writes to the
-- *acting* player's settings (player.color), so storage stays correctly
-- per-player; only the on-screen toggle states would be shared if two players
-- happened to have the panel open at the same instant.

-- default value for every setting, applied to each colour on load
settingsDefaults = {
	oppDrawTriggers = false, -- notify this player about draw triggers (theirs / others')
	                         -- default off: feature is unfinished / somewhat buggy
	drawSkipReminder = true, -- warn (and stop the draw) on a "skip your draw step" card
	abilityRestrictions = false, -- remind on tapping a permanent whose activated abilities are prohibited
	                             -- default off: feature is unfinished / somewhat buggy
	searchRestrictions = true, -- block fetchland resolution when a tutor/search-hate card is in play
	landTracker = true,      -- track / show lands entered this turn on this player's mat
	fetchPreviews = true,    -- float library-land previews above this player's fetchlands
	fetchFromClone = false,  -- read those previews from the game-start deck clone instead of
	                         -- the live library, so an opponent's hidden removal (Praetor's
	                         -- Grasp, etc.) can't leak which land left. Off = live library.
	ownerHighlight = true,   -- glow cards on this player's mat that belong to someone else, in the owner's colour
	commanderQOL = true,     -- spawn the per-commander QOL buttons (Etali trigger, Ral grid)
	cmdrDamageAutoLife = true, -- commander-damage tracker deltas auto-adjust this player's life
	seedbornUntap = true,    -- this player's Seedborn Muse untaps their board on others' untap steps
	dfcLandFlip = true,      -- flip a double-faced card to its land back face in the land zone
	fetchSurveil = false,    -- auto-surveil/scry when a fetched land has an ETB surveil/scry trigger
	fetchEntersTapped = false, -- tap a fetched land whose text (or the fetchland) says it enters tapped
	keywordTokens = true,    -- dropping a keyword token (Frozen, Flying, ...) on a card applies that keyword
	goblinStickers = true,   -- deal goblin sticker cards when a "_____ Goblin" starts in the library
	keepPregameFlow = false, -- show the centre-mat Keep button and run the pregame-action announcement
	revealResetSecs = 30,    -- seconds of inactivity before the reveal count resets
}

-- panel toggle id -> settings key it controls
settingsToggleIds = {
	setOppDrawTriggers = "oppDrawTriggers",
	setDrawSkipReminder = "drawSkipReminder",
	setAbilityRestrictions = "abilityRestrictions",
	setSearchRestrictions = "searchRestrictions",
	setLandTracker = "landTracker",
	setFetchPreviews = "fetchPreviews",
	setFetchFromClone = "fetchFromClone",
	setOwnerHighlight = "ownerHighlight",
	setCommanderQOL = "commanderQOL",
	setCmdrDamageAutoLife = "cmdrDamageAutoLife",
	setSeedbornUntap = "seedbornUntap",
	setDfcLandFlip = "dfcLandFlip",
	setFetchSurveil = "fetchSurveil",
	setFetchEntersTapped = "fetchEntersTapped",
	setKeywordTokens = "keywordTokens",
	setGoblinStickers = "goblinStickers",
	setKeepPregameFlow = "keepPregameFlow",
}

-- colour -> { key = value }
playerSettings = playerSettings or {}

settingsColors = { "White", "Red", "Yellow", "Blue" }

-- settings the host can enforce on everyone (booleans only). When a key is
-- enforced, getSetting returns the enforced value for every colour and each
-- player's own toggle for it is greyed out. Defaults: nothing enforced, all
-- enforced values false.
enforceableKeys = {
	"oppDrawTriggers",
	"drawSkipReminder",
	"abilityRestrictions",
	"searchRestrictions",
	"landTracker",
	"fetchPreviews",
	"fetchFromClone",
	"ownerHighlight",
	"commanderQOL",
	"cmdrDamageAutoLife",
	"seedbornUntap",
	"dfcLandFlip",
	"fetchSurveil",
	"fetchEntersTapped",
	"keywordTokens",
	"goblinStickers",
	"keepPregameFlow",
}

-- key -> { enforced = bool, value = bool }
enforcedSettings = enforcedSettings or {}

-- Initialize the host's enforcement settings.
function initEnforced()
	enforcedSettings = enforcedSettings or {}
	for _, key in ipairs(enforceableKeys) do
		local e = enforcedSettings[key] or {}
		if e.enforced == nil then
			e.enforced = false
		end
		if e.value == nil then
			e.value = false
		end
		enforcedSettings[key] = e
	end
end

-- pull the settings key out of a host-panel widget id ("hostEnf_<key>" /
-- "hostVal_<key>"), or nil if the prefix doesn't match
function hostKeyFromId(id, prefix)
	if id ~= nil and id:sub(1, #prefix) == prefix then
		return id:sub(#prefix + 1)
	end
	return nil
end

-- fill in any missing colours / keys with defaults; called from onload after any
-- saved state has been restored
function initSettings()
	playerSettings = playerSettings or {}
	for _, color in ipairs(settingsColors) do
		playerSettings[color] = playerSettings[color] or {}
		for key, def in pairs(settingsDefaults) do
			if playerSettings[color][key] == nil then
				playerSettings[color][key] = def
			end
		end
	end
end

-- read a setting for a colour. A host-enforced setting overrides every player's
-- own value; otherwise fall back to the player's value, then the default.
function getSetting(color, key)
	local e = enforcedSettings[key]
	if e ~= nil and e.enforced then
		return e.value
	end
	local s = playerSettings[color]
	if s ~= nil and s[key] ~= nil then
		return s[key]
	end
	return settingsDefaults[key]
end

