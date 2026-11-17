---------------------------------- PERSISTENCE ---------------------------------
-- TTS serialises the Global script state via onSave; we stash playerSettings in
-- it and read it back in onload(saved). Tolerant of a nil / malformed blob.
-- Both casings are defined because this table's entry point is lower-case
-- onload(); whichever name TTS calls, the other is simply dead.
function saveSettings()
	return JSON.encode({
        playerSettings = playerSettings,
        enforcedSettings = enforcedSettings,
        mtgCardState = mtgCardStateSave()
    })
end

function restoreSettings(saved)
    local savedCardState = nil
	if saved ~= nil and saved ~= "" then
		local ok, decoded = pcall(JSON.decode, saved)
		if ok and type(decoded) == "table" then
			if type(decoded.playerSettings) == "table" then
				playerSettings = decoded.playerSettings
			end
			if type(decoded.enforcedSettings) == "table" then
				enforcedSettings = decoded.enforcedSettings
			end
            savedCardState = decoded.mtgCardState
		end
	end
    mtgCardStateLoad(savedCardState)
	initSettings()
	initEnforced()
end

function onSave()
	return saveSettings()
end

function onsave()
	return saveSettings()
end

