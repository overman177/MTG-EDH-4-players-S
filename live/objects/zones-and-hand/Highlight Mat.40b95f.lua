-- Read the seat color from the description and make the mat transparent and non-interactive.
-- Turn highlight mat. The description identifies its seat; only the active player's mat is tinted.

function onLoad()
  self.setColorTint({1, 1, 1, 0})
	self.interactable=false
  thisplayer = self.getDescription()
end

-- Tint the mat only while its own player has the turn.
function onPlayerTurn(player)
  if player==nil then
    self.setColorTint({1, 1, 1, 0})
    return
  elseif player.color==thisplayer then
	  local rgb = stringColorToRGB(player.color)
	  local color = {rgb["r"], rgb["g"], rgb["b"], 0.05}
	  self.setColorTint(color)
    startTime = os.time()
	else
	  self.setColorTint({1, 1, 1, 0})
	end
end