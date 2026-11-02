------------------------------------ DISPLAY ------------------------------------


-- Do not assume the land tracker is button index 0 when other modules add UI.
function mtgSetLandTrackerText(mat, label)
    for _, b in ipairs(mat.getButtons() or {}) do
        if b.click_function == "null" and b.tooltip == "MTG_LandTracker" then
            mat.editButton({ index = b.index, label = label })
            return
        end
    end
    -- Fallback for saves made before the patch.
    for _, b in ipairs(mat.getButtons() or {}) do
        if b.click_function == "null" and (b.label or ""):find("Lands this turn", 1, true) then
            mat.editButton({ index = b.index, label = label })
            return
        end
    end
end

function refreshLandTrackerText(color)
	local mat = data[color]["playmat"]
	if mat == nil then
		return
	end
	-- blank the display entirely when the owner has the tracker turned off
	if not getSetting(color, "landTracker") then
		mtgSetLandTrackerText(mat, "")
		return
	end
	local names = {}
	for _, e in ipairs(landsEnteredThisTurn[color] or {}) do
		table.insert(names, e.name)
	end
	local label
	if #names == 0 then
		label = "Lands this turn: none"
	else
		label = "Lands this turn (" .. #names .. "):\n" .. table.concat(names, "\n")
	end
	mtgSetLandTrackerText(mat, label)
end
