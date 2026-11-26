-- Energy counter. Each seat has its own physical counter; the value is stored on that object, and Lotus manages visibility separately.

MIN_VALUE = 0
MAX_VALUE = 99

-- Restore the saved amount and create the controls.
function onload(saved_data)
  val = 0
  self.setColorTint("Red") 
  if saved_data ~= "" then
    local loaded_data = JSON.decode(saved_data)

    val = loaded_data[1]

  end

  createAll()
end

-- Save the current value in the object's script state.
function updateSave()
  local data_to_save = {val}
  saved_data = JSON.encode(data_to_save)
  self.script_state = saved_data
end

-- Build the physical display and click controls.
function createAll()
    local displayVal = (val == 0) and "" or tostring(val)

	self.createButton({
    label=displayVal,
    click_function="null",
    tooltip="Energy Counter",
    function_owner=self,
    position={0-0.05,0.1,-0.1},
    height=0,
    width=0,
    alignment = 3,
    scale={x=0.75, y=0.75, z=0.75},
    font_size=800,
    font_color={1,1,1,95},
    color={0,0,0,0}
    })

  self.createButton({
    label=displayVal,
    click_function="add_subtract",
    tooltip="Energy Counter",
    function_owner=self,
    position={0,0.15,-0.1},
    height=500,
    width= 500,
    alignment = 3,
    scale={x=0.75, y=0.75, z=0.75},
    font_size=800,
    font_color={1,1,1},
    color={0,0,0,0}
    })

end

-- Clear the existing counter controls.
function removeAll()
  self.removeButton(0)
  self.removeButton(1)

end

-- Rebuild the counter controls using the current value.
function reloadAll()
  removeAll()
  createAll()

  updateSave()
end

-- Adjust the count according to the click direction and configured limits.
function add_subtract(_obj, _color, alt_click)
  mod = alt_click and -1 or 1
  new_value = math.min(math.max(val + mod, MIN_VALUE), MAX_VALUE)
  if val ~= new_value then
    val = new_value
    if val > 0 then
      self.setColorTint({0,0,0,254})
    else
      self.setColorTint("Red")
    end
    updateVal()
    updateSave()
  end
end

-- Refresh the displayed count and the object's saved state.
function updateVal()
  -- Keep zero visually blank whenever the display is rebuilt.
  local displayVal = (val == 0) and "" or tostring(val)


  self.editButton({
    index = 0,
    label = displayVal,

  })

  self.editButton({
    index = 1,
    label = displayVal,

  })
end



-- No-op callback for a display-only control.
function null()
end

self.max_typed_number=999
-- Handle direct numeric input for the counter.
function onNumberTyped(col,int)
  val = int
  updateVal()
  updateSave()
end