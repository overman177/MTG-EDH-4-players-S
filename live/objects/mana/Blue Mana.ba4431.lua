MIN_VALUE = 0
MAX_VALUE = 99


function onload(saved_data)
    bcolor = self.getColorTint()
    bcolor[4] = 100
     val = 0

    if saved_data ~= "" then
        local loaded_data = JSON.decode(saved_data)
        val = loaded_data[2]
    end
    ttText = self.getName()
    createAll()
end

function updateSave()
    local data_to_save = {1, val}
    saved_data = JSON.encode(data_to_save)
    self.script_state = saved_data
end

function createAll()
    bpars={
      label=tostring(val),
      click_function="add_subtract",
      tooltip=ttText,
      function_owner=self,
      position={0,0.1,0},
      height=100,
      width=100,
      alignment = 3,
      scale={x=2, y=2, z=2},
      font_size=500,
      font_color={0,0,0,100},
      color={0,0,0,0}
      }

  for i=-1,1,2 do
    for j=-1,1,2 do
      bpars.position={i*.1,0.1,j*.1}
      self.createButton(bpars)
    end
  end

  bpars.position={0,0.15,0}
  bpars.height=500
  bpars.width=500
  bpars.font_color=bcolor
  self.createButton(bpars)

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
    for ind=0,4 do
        self.editButton({index = ind, label = tostring(val)})
    end
end


self.max_typed_number=999
function onNumberTyped(col,int)
  val = int
  updateVal()
  updateSave()
end