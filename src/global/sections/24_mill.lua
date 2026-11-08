------------------------------------- MILL -------------------------------------
function playerMill(button, playerColor, alt)
	if button == data[playerColor]["millButton"] then
		if not alt then
			buttonPress(button, drawDelay * 0.75)
			mill1(playerColor)
		else
			buttonPress(button, drawDelay * nAlt)
			buttonCooldown(button, drawDelay * nAlt)
			Wait.time(function()
				mill1(playerColor)
			end, drawDelay, nAlt)
		end
	else
		warnNotYours(button, playerColor)
	end
end

function mill1(playerColor)
	local card = getCardFromZone(data[playerColor]["libraryZone"])
	if card ~= nil then
		local targPos, cardRot = mtgGetZonePlacement(playerColor, "graveyard", 3, false)
		if targPos == nil then return end
		--interactTrigger(card)
		card.setRotationSmooth(cardRot, false, true)
		card.setPositionSmooth(targPos, false, true)
		Wait.time(function()
			checkMoveSuccess(card, targPos, playerColor)
		end, 0.5)
	end
end

