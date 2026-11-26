-- Host-only settings, enforcement and associated UI callbacks.

--------------------------------- HOST PANEL -----------------------------------
-- second, host-only menu: per setting an "enforced" toggle and a "value" toggle.
-- Enforcing a setting forces it on every player (via getSetting) and greys out
-- their own toggle; unenforcing hands control back to each player.

-- Refresh the land displays after a settings change.
function refreshAllLandTrackers()
	for _, color in ipairs(settingsColors) do
		refreshLandTrackerText(color)
	end
end

-- Refresh the pregame controls after a settings change.
function refreshAllKeepButtons()
	for _, color in ipairs(settingsColors) do
		refreshKeepButton(color)
	end
end

-- Open the host-only settings panel.
function openHostSettings(player)
	if player == nil then
		return
	end
	if not player.host then
		broadcastToColor("Host settings are host-only.", player.color, { 0.9, 0.5, 0.2 })
		return
	end
	for _, key in ipairs(enforceableKeys) do
		local e = enforcedSettings[key]
		UI.setAttribute("hostEnf_" .. key, "isOn", e.enforced and "True" or "False")
		UI.setAttribute("hostVal_" .. key, "isOn", e.value and "True" or "False")
		-- the value only matters while enforced, so lock it otherwise
		UI.setAttribute("hostVal_" .. key, "interactable", e.enforced and "true" or "false")
	end
	-- start every open with an empty search box and all rows shown
	UI.setAttribute("hostSearchInput", "text", "")
	clearHostSettingsSearch()
	visibleOpenRules(player.color, "HostSettingsPanel")
end

-- Close the host settings panel.
function closeHostSettings(player)
	visibleCloseRules(player, "HostSettingsPanel")
end

-- Change whether the host forces this preference on all players.
function hostToggleEnforced(player, value, id)
	if player == nil or not player.host then
		return
	end
	local key = hostKeyFromId(id, "hostEnf_")
	if key == nil or enforcedSettings[key] == nil then
		return
	end
	local on = (value == "True" or value == true)
	enforcedSettings[key].enforced = on
	UI.setAttribute(id, "isOn", on and "True" or "False")
	UI.setAttribute("hostVal_" .. key, "interactable", on and "true" or "false")
	applyEnforcementToPlayerPanel(nil)
	if key == "landTracker" then
		refreshAllLandTrackers()
	elseif key == "fetchPreviews" or key == "fetchFromClone" then
		refreshAllFetchPreviews()
	elseif key == "keepPregameFlow" then
		refreshAllKeepButtons()
	end
end

-- Change the value of a host-controlled setting.
function hostToggleValue(player, value, id)
	if player == nil or not player.host then
		return
	end
	local key = hostKeyFromId(id, "hostVal_")
	if key == nil or enforcedSettings[key] == nil then
		return
	end
	local on = (value == "True" or value == true)
	enforcedSettings[key].value = on
	UI.setAttribute(id, "isOn", on and "True" or "False")
	applyEnforcementToPlayerPanel(nil)
	if key == "landTracker" then
		refreshAllLandTrackers()
	elseif key == "fetchPreviews" or key == "fetchFromClone" then
		refreshAllFetchPreviews()
	elseif key == "keepPregameFlow" then
		refreshAllKeepButtons()
	end
end

-- reveal-reset timeout committed
function settingsRevealReset(player, value, id)
	if player == nil then
		return
	end
	local n = tonumber(value)
	if n == nil or n < 1 then
		n = settingsDefaults.revealResetSecs
	end
	n = math.floor(n)
	playerSettings[player.color] = playerSettings[player.color] or {}
	playerSettings[player.color].revealResetSecs = n
	UI.setAttribute("setRevealResetSecs", "text", tostring(n))
end
