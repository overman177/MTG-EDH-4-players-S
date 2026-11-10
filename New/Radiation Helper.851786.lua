--[[
    Radiation Counter Script
    =========================
    
    This script implements a "Radiation" counter for Tabletop Simulator that processes
    radiation by milling cards from a player's library and applying life loss for
    non-land cards milled.
    
    Features:
    - Left click: Increment radiation counter value
    - Right click: Process radiation (mill cards, lose life for non-lands, decrement counter)
    - Type: Set radiation value directly
    - Sequential card milling with proper synchronization
    - Card type detection (land vs non-land)
    - Life loss integration with Life Tracker objects
    - Broadcast summary to all seated players
    
    Authors: etherb0x + Cursor/Claude
    
    Intended for use with:
    - pi's MTG EDH 4-player mod
    - Life Tracker objects for life management
    - Encoder system for property management
    - Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=2296042369
    
    Last updated for pi's table version: 02/11/2025
--]]

-- TODO: Re-add encoder-based options when Encoder API is stable:
--   - Mill modifier: flat number to add to cards milled (default 0)
--   - Mill multiplier: multiplier for radiation amount (default 1.0)
--   - Life loss toggle: enable/disable life loss during processing (default ON)

-- User Variables
MIN_VALUE = 0
MAX_VALUE = 99

local TOOLTIP_INSTRUCTIONS = '           [b]Radiation[/b]'..'\n       [i]left click[/i]'..'\n -increment counter'..'\n\n       [i]right click[/i]'..'\n  -process radiation\n(mill cards, lose life \nfor non-lands)'..'\n\n       [i]type[/i]'..'\n  -set value directly'


function onload(saved_data)
  light_mode = true
  tooltip_show = false
  val = 0

  if saved_data ~= "" then
    local loaded_data = JSON.decode(saved_data)
    light_mode = loaded_data[1]
    val = loaded_data[2]
    tooltip_show = loaded_data[3]
  end

  createAll()
end

-- ---- UI / Button Management ----

function updateSave()
  local data_to_save = {light_mode, val, tooltip_show}
  saved_data = JSON.encode(data_to_save)
  self.script_state = saved_data
end

function createAll()
    s_color = {0.5, 0.5, 0.5, 95}

    if light_mode then
        f_color = {0.9,0.9,0.9,100}
    else
        f_color = {0.1,0.1,0.1,100}
    end

    if tooltip_show then
        ttText = "     " .. val .. "\n" .. self.getName() .. "\n\n" .. TOOLTIP_INSTRUCTIONS
    else
        ttText = TOOLTIP_INSTRUCTIONS
    end

	self.createButton({
    label=tostring(val),
    click_function="null",
    tooltip=ttText,
    function_owner=self,
    position={0-0.1,0.1,0.2+0.1},
    height=0,
    width=0,
    alignment = 3,
    scale={x=1.5, y=1.5, z=1.5},
    font_size=800,
    font_color={1-f_color[1],1-f_color[2],1-f_color[3],95},
    color={0,0,0,0}
    })

  self.createButton({
    label=tostring(val),
    click_function="add_subtract",
    tooltip=ttText,
    function_owner=self,
    position={0,0.15,0.2},
    height=600,
    width= 600,
    alignment = 3,
    scale={x=1.5, y=1.5, z=1.5},
    font_size=800,
    font_color=f_color,
    color={0,0,0,0}
    })

  lightButtonText = "swap text color"
  self.createButton({
    label=lightButtonText,
    tooltip='Toggle light/dark text color',
    click_function="swap_fcolor",
    function_owner=self,
    position={0,-0.075,-0.25},
    rotation={180,180,0},
    height=150,
    width=1200,
    scale={x=1, y=1, z=1},
    font_size=150,
    font_color=s_color,
    color={0,0,0,0}
  })


  self.createButton({
    label='reset',
    tooltip='Reset counter to 0',
    click_function="reset_val",
    function_owner=self,
    position={0,-0.075,0.25},
    rotation={180,180,0},
    height=250,
    width=1200,
    scale={x=1, y=1, z=1},
    font_size=250,
    font_color=s_color,
    color={0,0,0,0}
  })

  setTooltips()
end

function removeAll()
  self.removeButton(0)
  self.removeButton(1)
  self.removeButton(2)
  self.removeButton(3)
end

function reloadAll()
  removeAll()
  createAll()
  setTooltips()
  updateSave()
end

function swap_fcolor(_obj, _color, alt_click)
  light_mode = not light_mode
  reloadAll()
end

function swap_align(_obj, _color, alt_click)
  center_mode = not center_mode
  reloadAll()
end

function editName(_obj, _string, value)
  self.setName(value)
  setTooltips()
end

function add_subtract(_obj, _color, alt_click)
  if alt_click then
    -- Right-click: process radiation
    if val > 0 then
      processRadiation(_obj, _color)
    end
  else
    -- Left-click: increment
    mod = 1
    new_value = math.min(math.max(val + mod, MIN_VALUE), MAX_VALUE)
    if val ~= new_value then
      val = new_value
      updateVal()
      updateSave()
    end
  end
end

function updateVal()
  if tooltip_show then
    ttText = "     " .. val .. "\n" .. self.getName() .. "\n\n" .. TOOLTIP_INSTRUCTIONS
  else
    ttText = TOOLTIP_INSTRUCTIONS
  end

  self.editButton({
    index = 0,
    label = tostring(val),
    tooltip = ttText
  })

  self.editButton({
  	index = 1,
  	label = tostring(val),
  	tooltip = ttText
	})

end

function reset_val()
  val = 0
  updateVal()
  updateSave()
end

function setTooltips()
  if tooltip_show then
    ttText = "     " .. val .. "\n" .. self.getName() .. "\n\n" .. TOOLTIP_INSTRUCTIONS
  else
    ttText = TOOLTIP_INSTRUCTIONS
  end

  self.editButton({
    index = 0,
    label = tostring(val),
    tooltip = ttText
  })
end

function null()
end

self.max_typed_number=999
function onNumberTyped(col,int)
  val = int
  updateVal()
  updateSave()
end

-- ---- Radiation Processing ----

-- Helper function to find the player whose library to mill (closest to this counter)
function getRadiationOwner(playerColor)
  -- Find the player closest to this radiation counter
  local radPos = self.getPosition()
  local closestPlayer = playerColor
  local minDist = math.huge
  
  for _, p in pairs(Player.getPlayers()) do
    if p.seated then
      local pPos = p.getPointerPosition()
      if pPos then
        local dist = math.sqrt(
          math.pow(pPos.x - radPos.x, 2) +
          math.pow(pPos.y - radPos.y, 2) +
          math.pow(pPos.z - radPos.z, 2)
        )
        if dist < minDist then
          minDist = dist
          closestPlayer = p.color
        end
      end
    end
  end
  
  return closestPlayer
end

-- Helper function to detect if a card is a land
function isLandCard(card)
  if card == nil then return false end
  local name = card.getName()
  if name == nil then return false end
  return name:match("Land") ~= nil
end

-- Helper function to extract card name from full name string
function getCardName(card)
  if card == nil then return "Unknown" end
  local fullName = card.getName()
  if fullName == nil then return "Unknown" end
  
  -- Extract just the first line (card name before any newlines)
  -- Card names might have format: "Card Name\nType\nCMC" or "Card Name (Type)"
  local firstLine = fullName:match("^([^\n\r]+)")
  if firstLine then
    -- Extract just the card name (before parentheses, CMC, or any other info)
    -- Remove anything after parentheses, numbers (CMC), or special markers
    local nameMatch = firstLine:match("^([^(0-9]+)") or firstLine:match("^([^%d]+)")
    if nameMatch then
      -- Trim whitespace and remove any trailing special characters
      local cleaned = nameMatch:match("^%s*(.-)%s*$")
      -- Remove any trailing dashes, colons, etc.
      cleaned = cleaned:match("^(.-)[%-:;]*$") or cleaned
      return cleaned
    end
    -- If no match, just return first line trimmed
    return firstLine:match("^%s*(.-)%s*$")
  end
  
  -- Fallback: return first line of full name
  return fullName:match("^([^\n\r]+)") or "Unknown"
end

-- Helper function to extract card type from name string
function getCardType(card)
  if card == nil then return "Unknown" end
  local name = card.getName()
  if name == nil then return "Unknown" end
  
  -- Extract type from card name
  -- Format might be: "Card Name (Type - Subtype)" or "Card Name\nType\nCMC"
  -- First try to get type from parentheses
  local typeMatch = name:match("%(([^)]+)%)")
  if typeMatch then
    -- Clean up the type string
    return typeMatch:match("^%s*(.-)%s*$")
  end
  
  -- If no parentheses, check if there's a second line with type info
  local lines = {}
  for line in name:gmatch("([^\n]+)") do
    table.insert(lines, line)
  end
  
  -- If we have multiple lines, the second line might be the type
  if #lines >= 2 then
    local secondLine = lines[2]
    -- Remove any CMC info from the type line (format might be "Type" or "Type X CMC")
    secondLine = secondLine:match("^([^0-9]+)") or secondLine
    -- Check if it looks like a type (contains "Land", "Creature", "Artifact", etc.)
    if secondLine:match("Land") or secondLine:match("Creature") or 
       secondLine:match("Artifact") or secondLine:match("Enchantment") or
       secondLine:match("Planeswalker") or secondLine:match("Instant") or
       secondLine:match("Sorcery") then
      -- Clean up the type string
      local cleaned = secondLine:match("^%s*(.-)%s*$")
      -- Remove any trailing CMC references or other junk
      cleaned = cleaned:gsub("%s*%d+%s*CMC.*$", "")
      cleaned = cleaned:gsub("%s*%(.*%)%s*$", "")
      return cleaned:match("^%s*(.-)%s*$")
    end
  end
  
  -- Fallback: check if it's a land
  if isLandCard(card) then
    return "Land"
  end
  
  return "Unknown"
end

-- Helper function to decrease life via Life Tracker
function loseLife(playerColor, amount)
  -- Find the Life Tracker for this player
  local lifeTracker = nil
  for _, obj in pairs(getAllObjects()) do
    if obj.getName() == "Life Tracker" then
      local desc = obj.getDescription()
      if desc == playerColor then
        lifeTracker = obj
        break
      end
    end
  end
  
  if lifeTracker == nil then return end
  
  -- Ensure Life Tracker is initialized
  pcall(function()
    lifeTracker.call("onload", lifeTracker.script_state)
  end)
  
  -- Decrease life by calling valueChange2 (simulates clicking down arrow)
  for i = 1, amount do
    pcall(function()
      lifeTracker.call("valueChange2", lifeTracker, playerColor, false)
    end)
    Wait.frames(function() end, 1)
  end
end

-- Core function: mill cards from library, apply life loss for non-lands, decrement counter
function processRadiation(_obj, playerColor)
  if val <= 0 then return end
  
  -- Play sound effect
  pcall(function()
    -- Option 1: AssetBundle (uncomment if using)
    -- self.AssetBundle.playTriggerEffect(0)
    -- Option 2: Direct audio (uncomment if using)
    -- self.playSound({url = "radiation.wav"})
  end)
  
  -- Cards to mill: 1:1 with radiation value (see TODO for encoder-based modifiers)
  local cardsToMill = math.max(0, val)
  
  -- Determine owner
  local ownerColor = getRadiationOwner(playerColor)
  
  -- Get library and graveyard zones
  local data = Global.getVar('data')
  if data == nil then return end
  
  local libraryZone = data[ownerColor] and data[ownerColor]["libraryZone"]
  local graveyard = data[ownerColor] and data[ownerColor]["graveyard"]
  
  if libraryZone == nil or graveyard == nil then
    Player[playerColor].broadcast("Error: Could not find library or graveyard zones", {1, 0, 0})
    return
  end
  
  -- Get player name
  local ownerName = ownerColor
  if Player[ownerColor] and Player[ownerColor].steam_name then
    ownerName = Player[ownerColor].steam_name
  end
  
  -- Print local message
  print("Processing Radiation for " .. ownerName .. "...")
  
  -- Track statistics
  local totalMilled = 0
  local nonLandsMilled = 0
  local lifeLost = 0
  local cardsProcessed = {}
  
  -- Process cards sequentially
  local function processNextCard(cardIndex)
    if cardIndex > cardsToMill then
      -- All cards processed, show completion message locally
      print("\\RADIATION PROCESSING COMPLETE")
      
      -- Broadcast to all seated players
      local cardText = totalMilled == 1 and "card" or "cards"
      local broadcastMsg = string.format(
        "%s: Milled %d %s, %d nonland, %d life lost. New radiation is %d.",
        ownerName,
        totalMilled,
        cardText,
        nonLandsMilled,
        lifeLost,
        val
      )
      
      for _, p in pairs(Player.getPlayers()) do
        if p.seated then
          p.broadcast(broadcastMsg, {1, 1, 1})
        end
      end
      
      return
    end
    
    -- Get card from library
    local card = Global.call("getCardFromZone", libraryZone)
    
    if card == nil then
      -- Library is empty, show completion message locally
      print("\\RADIATION PROCESSING COMPLETE")
      
      -- Broadcast to all seated players
      local cardText = totalMilled == 1 and "card" or "cards"
      local broadcastMsg = string.format(
        "%s: Milled %d %s, %d nonland, %d life lost. New radiation is %d.",
        ownerName,
        totalMilled,
        cardText,
        nonLandsMilled,
        lifeLost,
        val
      )
      
      for _, p in pairs(Player.getPlayers()) do
        if p.seated then
          p.broadcast(broadcastMsg, {1, 1, 1})
        end
      end
      
      return
    end
    
    -- Mill the card
    local gravPos = graveyard.getPosition()
    local targPos = {x = gravPos.x, y = 3, z = gravPos.z}
    local cardRot = card.getRotation()
    cardRot.z = 0
    card.setRotationSmooth(cardRot, false, true)
    card.setPositionSmooth(targPos, false, true)
    
    -- Get card info
    local cardName = getCardName(card)
    local cardType = getCardType(card)
    local isLand = isLandCard(card)
    
    -- Print card details locally (clean format, no extra spacing)
    print("- " .. cardName .. " (" .. cardType .. ")")
    
    -- Update statistics
    totalMilled = totalMilled + 1
    table.insert(cardsProcessed, {name = cardName, type = cardType, isLand = isLand})
    
    -- Process life loss and radiation decrement for non-lands
    if not isLand then
      nonLandsMilled = nonLandsMilled + 1
      
      loseLife(ownerColor, 1)
      lifeLost = lifeLost + 1
      
      -- Decrement radiation counter
      val = math.max(0, val - 1)
      updateVal()
      updateSave()
    end
    
    -- Wait for card movement, then process next card
    Wait.time(function()
      Global.call("checkMoveSuccess", card, targPos, ownerColor)
      processNextCard(cardIndex + 1)
    end, 0.3)
  end
  
  -- Start processing
  processNextCard(1)
end