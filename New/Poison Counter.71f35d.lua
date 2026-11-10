MIN_VALUE = 0
MAX_VALUE = 10

function onload(saved_data)
  val = 0

  if saved_data ~= "" then
    local loaded_data = JSON.decode(saved_data)
    val = loaded_data[1]

  end
  createAll()
end

function updateSave()
  local data_to_save = {val}
  saved_data = JSON.encode(data_to_save)
  self.script_state = saved_data
end

function createAll()
    local displayVal = (val == 0) and "" or tostring(val)

	self.createButton({
    label=displayVal,
    click_function="null",
    tooltip="Poison Counter",
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
    tooltip="Poison Counter",
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

function removeAll()
  self.removeButton(0)
  self.removeButton(1)
end

function reloadAll()
  removeAll()
  createAll()
  updateSave()
end


function add_subtract(_obj, _color, alt_click)
  mod = alt_click and -1 or 1
  new_value = math.min(math.max(val + mod, MIN_VALUE), MAX_VALUE)
  if val ~= new_value then
    val = new_value
    updateVal()
    updateSave()
  end
end

function updateVal()
  -- This ensures any time the buttons are refreshed, 0 becomes ""
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

function null()
end

self.max_typed_number=999
function onNumberTyped(col,int)
  val = int
  updateVal()
  updateSave()
end