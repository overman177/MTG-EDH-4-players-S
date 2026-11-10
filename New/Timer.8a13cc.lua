function onLoad(saved_data)
  owner=self.getDescription()
  self.setLock(true)
  self.interactable=false

  pos=self.getPosition()
  pos[2]=0
  self.setPosition(pos)

  timerOn=true

  ownerCol=Color.fromString(owner)

  bpars={
    click_function='null',
    function_owner=self,
    label='',
    width=0,
    height=0,
    font_size=500,
    color={0,0,0,0},
    font_color={ownerCol.r,ownerCol.g,ownerCol.b,100}
  }

  bpars_s1=bpars
  bpars_s2=bpars
  bpars_co=bpars
  bpars_m1=bpars
  bpars_m2=bpars

  bpars_s1.position=vector(1,1,0)
  self.createButton(bpars_s1)
  bpars_s2.position=vector(0.4,1,0)
  self.createButton(bpars_s2)
  bpars_co.position=vector(0,1,-0.05)
  bpars_co.font_size=400
  self.createButton(bpars_co)
  bpars_m1.position=vector(-0.4,1,0)
  bpars_m1.font_size=500
  self.createButton(bpars_m1)
  bpars_m2.position=vector(-1,1,0)
  self.createButton(bpars_m2)

  turnN=0
  if saved_data ~= "" then
    turnN=tonumber(saved_data)
  end

  bpars_t=bpars
  bpars_t.font_size=400
  bpars_t.label=''
  bpars_t.position=vector(-0.2,1,-1.2)
  self.createButton(bpars_t)

  bpars_tc=bpars
  bpars_tc.click_function='modTurn'
  bpars_tc.font_size=500
  bpars_tc.width=0
  bpars_tc.height=0
  bpars_tc.label=''
  bpars_tc.position=vector(1.2,1,-1.2)
  self.createButton(bpars_tc)

end

function updateSave()
  self.script_state = tostring(turnN)
end

function modTurn(obj,ply,alt)
  turnN=turnN + (alt and -1 or 1)
  self.editButton({index=6,label=turnN})
  updateSave()
end

function onPlayerTurn(player)
  if player~=nil and player.color==owner then

    tdiff=0
    timerID=Wait.time(function()
      tdiff=tdiff+1
      mins=math.floor(tdiff/60)
      secs=tdiff-mins*60
      secStr=tostring(secs)
      minStr=tostring(mins)
      if string.len(secStr)<2 then
        secStr='0'..secStr
      end
      if string.len(minStr)<2 then
        minStr=' '..minStr
      end
      timeStr=minStr..':'..secStr
      updateButtons(timeStr)
    end,1,5999)

    turnN=turnN+1
    updateSave()
    if timerOn then
      self.editButton({index=5,label='turn'})
      self.editButton({index=6,width=400,height=400,label=turnN})
    end

  else

    if timerID~=nil then
      pcall(function() Wait.stop(timerID) end)
    end
    updateButtons('     ')

    self.editButton({index=5,label=''})
    self.editButton({index=6,width=0,height=0,label=''})

  end
end

function updateButtons(str)
  if timerOn then
    self.editButton({index=4,label=str:sub(1,1)})
    self.editButton({index=3,label=str:sub(2,2)})
    self.editButton({index=2,label=str:sub(3,3)})
    self.editButton({index=1,label=str:sub(4,4)})
    self.editButton({index=0,label=str:sub(5,5)})
  else
    self.editButton({index=4,label=''})
    self.editButton({index=3,label=''})
    self.editButton({index=2,label=''})
    self.editButton({index=1,label=''})
    self.editButton({index=0,label=''})
    self.editButton({index=5,label=''})
    self.editButton({index=6,width=0,height=0,label=''})
  end
end

function onChat(msg,ply)
  if msg:lower()=='timers on' then
    timerOn=true
  end
  if msg:lower()=='timers off' then
    timerOn=false
    updateButtons('     ')
    self.editButton({index=5,label=''})
    self.editButton({index=6,width=0,height=0,label=''})
  end

  if msg:lower():find('reset life') then
    turnN=0
    updateSave()
    if Turns.turn_color==owner then
      self.editButton({index=6,width=400,height=400,label=turnN})
    end
  end

end