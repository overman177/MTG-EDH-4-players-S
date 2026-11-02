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
		local gravPos = data[playerColor]["graveyard"].getPosition()
		local targPos = { x = gravPos.x, y = 3, z = gravPos.z }
		--interactTrigger(card)
		local cardRot = card.getRotation()
		cardRot.z = 0
		card.setRotationSmooth(cardRot, false, true)
		card.setPositionSmooth(targPos, false, true)
		Wait.time(function()
			checkMoveSuccess(card, targPos, playerColor)
		end, 0.5)
	end
end

