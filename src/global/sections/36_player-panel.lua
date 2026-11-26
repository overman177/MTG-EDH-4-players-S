-- Player settings UI callbacks and related display updates.

-------------------------------- PLAYER PANEL ----------------------------------
-- set each per-player toggle's enabled state to match host enforcement: an
-- enforced setting is locked (non-interactable) and shows the enforced value; an
-- unenforced setting is editable and, when a viewer colour is given, shows that
-- player's own value.
function applyEnforcementToPlayerPanel(color)
	for id, key in pairs(settingsToggleIds) do
		local e = enforcedSettings[key]
		if e ~= nil and e.enforced then
			UI.setAttribute(id, "isOn", e.value and "True" or "False")
			UI.setAttribute(id, "interactable", "false")
		else
			UI.setAttribute(id, "interactable", "true")
			if color ~= nil then
				UI.setAttribute(id, "isOn", getSetting(color, key) and "True" or "False")
			end
		end
	end
end

-- reflect the opening player's stored settings into the shared widgets, lock any
-- host-enforced ones, then show the panel only to them
function openSettings(player)
	if player == nil or player.color == "Grey" then
		return
	end
	local color = player.color
	applyEnforcementToPlayerPanel(color)
	UI.setAttribute("setRevealResetSecs", "text", tostring(getSetting(color, "revealResetSecs")))
	-- start every open with an empty search box and all rows shown
	UI.setAttribute("settingsSearchInput", "text", "")
	clearSettingsSearch()
	visibleOpenRules(color, "SettingsPanel")
end

-- Close the Global player settings panel.
function closeSettings(player)
	visibleCloseRules(player, "SettingsPanel")
end

-- a toggle changed: write the acting player's setting (ignored if the host has
-- enforced it)
function settingsToggle(player, value, id)
	local key = settingsToggleIds[id]
	if key == nil or player == nil then
		return
	end
	local e = enforcedSettings[key]
	if e ~= nil and e.enforced then
		-- locked by the host; snap the widget back to the enforced value
		UI.setAttribute(id, "isOn", e.value and "True" or "False")
		return
	end
	playerSettings[player.color] = playerSettings[player.color] or {}
	local on = (value == "True" or value == true)
	playerSettings[player.color][key] = on
	UI.setAttribute(id, "isOn", on and "True" or "False")
	-- the land tracker + fetch previews are passive, so refresh them the moment they
	-- are toggled (fetchFromClone changes the preview source, so refresh it too)
	if key == "landTracker" then
		refreshLandTrackerText(player.color)
	elseif key == "fetchPreviews" or key == "fetchFromClone" then
		refreshFetchPreviewsForColor(player.color)
	elseif key == "keepPregameFlow" then
		refreshKeepButton(player.color)
	end
end

