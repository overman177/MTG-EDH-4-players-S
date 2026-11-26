-- Draw button and single-card draw logic.

------------------------------------- DRAW -------------------------------------
-- a draw within this many seconds of pressing untap-all counts as the turn's
-- draw step, so a "skip your draw step" card should stop it
skipDrawWindow = 5

-- the display name of a face-up card on this player's playmat that makes them
-- skip their draw step, or nil if they control none
function skipDrawStepCard(playerColor)
	local mat = data[playerColor]["playmat"]
	if mat == nil then
		return nil
	end
	for _, obj in ipairs(mtgZoneObjects(mat)) do
		if obj.type == "Card" and not obj.is_face_down then
			local desc = (obj.getDescription() or ""):lower()
			if desc:find("skip your draw step", 1, true) or desc:find("skip your next draw step", 1, true) then
				return mainCardName(obj.getName())
			end
		end
	end
	return nil
end

-- Handle the Draw button and alternate-click count.
function playerDraw(button, playerColor, alt)
	if button == data[playerColor]["drawButton"] then
		if not alt then
			buttonPress(button, drawDelay * 0.75)
			-- if this draw is the turn's draw step (pressed soon after untap) and a
			-- card forces this player to skip it, remind them instead of drawing.
			-- the draw step is a single draw, so consume the window either way.
			local drawStep = lastUntapPress[playerColor] ~= nil
				and (os.time() - lastUntapPress[playerColor]) <= skipDrawWindow
			lastUntapPress[playerColor] = nil
			if drawStep and getSetting(playerColor, "drawSkipReminder") then
				local skipper = skipDrawStepCard(playerColor)
				if skipper ~= nil then
					broadcastToColor(
						"Draw skipped: " .. skipper .. " makes you skip your draw step. (alt-click to draw anyway.)",
						playerColor,
						{ 0.9, 0.3, 0.3 }
					)
					return
				end
			end
			draw1(playerColor)
			announceDrawTriggers(playerColor, 1, drawStep)
		else
			buttonPress(button, drawDelay * nAlt)
			buttonCooldown(button, drawDelay * nAlt)
			Wait.time(function()
				draw1(playerColor)
			end, drawDelay, nAlt)
			-- an explicit multi-draw isn't the draw-for-turn
			announceDrawTriggers(playerColor, nAlt, false)
		end
	else
		warnNotYours(button, playerColor)
	end
end

-- Draw one card from the player's library.
function draw1(playerColor)
	local card = getCardFromZone(data[playerColor]["libraryZone"])
	if card ~= nil then
		--interactTrigger(card)
		Wait.condition(function()
			card.deal(1, playerColor, 1)
		end, function()
			return not card.spawning
		end)
	end
end

