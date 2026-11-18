--===========================================================================
--Unpack Deckbox Section
--===========================================================================
playerPos = {
    ["White"]   = { 1,  1, -1},
    ["Red"]     = {-1,  1, -1},
    ["Yellow"]  = {-1,  1,  1},
    ["Blue"]    = { 1,  1,  1},
  }
playerRot = {
    ["White"]   = vector(0, 180, 0),
    ["Red"]     = vector(0, 180, 0),
    ["Yellow"]  = vector(0, 0,   0),
    ["Blue"]    = vector(0, 0,   0),
  }
markers = {
    ["cmd1"]  = {nil,   "Commander 1",  "Blue",   vector(0,0,0)},
    ["cmd2"]  = {nil,   "Commander 2",  "Teal",   vector(0,0,0)},
    ["libr"]  = {nil,   "Library",      "White",  vector(0,0,0)},
    ["tkns"]  = {nil,   "Tokens",       "Red",    vector(0,0,0)}
  }
saveBtnInd = -1
lastPly = nil
cmdr = 0
lib = -1

function onLoad(sd)
  params = {
    click_function = "unpackDeck",
    label          = "Unpack",
    tooltip        = "Unpack the deck",
    function_owner = self,
    position       = {0,3.725,-0.75},
    rotation       = {0,0,0},
    width          = 1000,
    height         = 1000,
    font_size      = 250,
    color          = {0,0,0,0},
    font_color     = {1,1,1,1}
  }

  self.createButton(params)
  params.height = 0
  params.width = 0
  params.color = {0,0,0,1}
  self.createButton(params)

  self.addContextMenuItem("Select Color",
    function() selectColor() end,
    false)

  self.addContextMenuItem("Setup Unpack",
    function() setupUnpack() end,
    false)



    updateUnpack()
end

function checkMemo()
  if self.memo ~= nil then
    local temp = JSON.decode(self.memo)
    for i,m in pairs(markers) do
      m[4] = temp[i]
    end
    return true
  else
    return false
  end
end

function setupUnpack()
  local hasMemo = checkMemo()
  local typ = "BlockRectangle"
  local rot = self.getRotation()
  local pos = self.getPosition()
  pos:add(vector(5,0,0))

  for i, m in pairs(markers) do
    local mPos = hasMemo and vector(m[4].x, m[4].y, m[4].z) or pos
    mPos:add(vector(0,1,0))
    m[1] = spawnObject({
      type              =  typ,
      position          =  mPos,
      rotation          =  rot,
      snap_to_grid      =  true,
      sound             =  false
    })
    m[1].setName(m[2])
    m[1].setColorTint(m[3])
    m[1].use_hands = true
    m[1].use_grid = true
    m[4] = m[1].getPosition()
    pos:add(vector(2.5,0,0))
  end

  self.createButton({
    click_function =  "btnSaveUnpack",
    function_owner =  self,
    label          =  "Save Unpack",
    position       =  {0,3,2},
    width          =  2500,
    height         =  500,
    font_size      =  350,
    color          =  {1,1,1,1},
    font_color     =  {0,0,0,1},
    tooltip        =  "Save the location of each unpack marker"
  })
  saveBtnInd = #self.getButtons()
end

function btnSaveUnpack(_, color, alt)
  if alt then
    for i,m in pairs(markers) do
      m[1].destruct()
    end
    broadcastToColor("Cancelled Setup", color, color)
    self.removeButton(saveBtnInd - 1)
    return false
  end
  local markerPos = {}
  for i,m in pairs(markers) do
    mPos = m[1].getPosition()
    mPos = vector(mPos[1], mPos[2], mPos[3])
    mPos:scale(playerPos[color][1], playerPos[color][2], playerPos[color][3])
    markerPos[i] = mPos
    m[1].destruct()
  end
  self.memo = JSON.encode(markerPos)
  self.removeButton(saveBtnInd - 1)
  saveBtnInd = -1
  broadcastToColor("Unpack Locations Saved", color, color)
end

function updateUnpack()
  local test = self.getCustomObject()["mesh"] == mono
  pos = test and {0,1.75,-0.55} or {0,3.725,-0.75}
  self.editButton({
    index = 0,
    position = pos
  })
  self.editButton({
    index = 1,
    position = pos
  })
end

function doNothing() end

function unpackDeck(_, ply, alt)
  cmdr = 0
  local hasMemo = checkMemo()
  if not hasMemo then
    broadcastToColor("Please Setup Unpack", ply, ply)
    return false
  end
  lastPly = ply
  contents = self.getObjects()
  rot = playerRot[ply]
  for i, obj in pairs(contents) do
    self.takeObject({
      callback_function = function(obj)
          placeObj(obj)
        end,
      smooth            = false,
      flip              = false,
      position          = self.getPosition():add(vector(4,5,0))
    })
  end
end

function placeObj(obj)
  local color = lastPly
  obj.setRotation(playerRot[color])
  if obj.type == "Deck" then
    local cnt = #obj.getObjects()
    if cnt > 95 then
      move2lib(obj, color)
    else
      move2tkn(obj, color)
    end
  else
    local name = obj.getName()
    if string.find(name, "Legendary") == nil then
      move2tkn(obj, color)
    else
      cmdr = cmdr + 1
      move2cmd(obj, color)
    end
  end
end

function move2lib(obj, color)
		local pos = markers["libr"][4]
    pos = vector(pos.x, pos.y, pos.z)
    pos:scale(playerPos[color][1], playerPos[color][2], playerPos[color][3])
    obj.setPositionSmooth(pos, false, false)
end

function move2cmd(obj, color)
		local pos = nil
    if cmdr == 1 then
      pos = markers["cmd1"][4]
    else
      pos = markers["cmd2"][4]
    end
    pos = vector(pos.x, pos.y, pos.z)
    pos:scale(playerPos[color][1], playerPos[color][2], playerPos[color][3])
    obj.setPositionSmooth(pos, false, false)
end

function move2tkn(obj, color)
  local pos = markers["tkns"][4]
  pos = vector(pos.x, pos.y, pos.z)
  pos:scale(playerPos[color][1], playerPos[color][2], playerPos[color][3])
  if obj.type == "Deck" then
    local offset = 1
    contents = obj.getObjects()
    for i in pairs(contents) do
      obj.takeObject({
        callback_function = function() end,
        smooth            = false,
        flip              = false,
        position          = pos,
        rotation          = playerRot[color]
      })
    end
  else
    obj.setPositionSmooth(pos, false, false)
  end
end



--===========================================================================
--Deck Box Color Change Sectiopn
--===========================================================================
dbLid = "c"
dbFront = ""
dbSide = ""
model = mono
applyInd = -1
cnvrtClr = {
    ["c"] = "White",
    ["w"] = "White",
    ["u"] = "Blue",
    ["b"] = "Black",
    ["r"] = "Red",
    ["g"] = "Green",
    ["m"] = "White"
  }

function selectColor()
  local sym = {}
  sym["w"]= {
    ["lbl"] = "White",
    ["clr"] = "White",
    ["fnt"] = "Black",
  }
  sym["u"]= {
    ["lbl"] = "Blue",
    ["clr"] = "Blue",
    ["fnt"] = "White",
  }
  sym["b"]= {
    ["lbl"] = "Black",
    ["clr"] = "Black",
    ["fnt"] = "White",
  }
  sym["r"]= {
    ["lbl"] = "Red",
    ["clr"] = "Red",
    ["fnt"] = "Black",
  }
  sym["g"]= {
    ["lbl"] = "Green",
    ["clr"] = "Green",
    ["fnt"] = "Black",
  }
  sym["c"]= {
    ["lbl"] = "Colorless",
    ["clr"] = "Grey",
    ["fnt"] = "White",
  }
  sym["m"]= {
    ["lbl"] = "Multi",
    ["clr"] = "Yellow",
    ["fnt"] = "Black",
  }

  local xPos = 4.5
  local test = self.getCustomObject()["mesh"] == mono

  local yPos = test and 1 or 3
  local zPos = 3
  params ={
    function_owner = self,-- Object (required),
    position       =  {-xPos,yPos,zPos},
    rotation       =  {0,0,0},
    width          =  2000,
    height         =  500,
    font_size      =  400,
    click_function = "doNothing",
    color          =  "Orange",
    label          =  "1: LID",
    tooltip        =  "Select Below"
  }

  self.createButton(params)
  local cnt = 0
  for i in pairs(sym) do
    cnt = cnt + 1
    local funcName = "dbLid" .. i
    local func = function(obj, ply, alt) setDbLid(i,ply) end
    self.setVar(funcName, func)
    params.click_function = funcName
    params.position       = {-xPos,yPos,zPos+cnt}
    params.label          = sym[i].lbl
    params.color          = sym[i].clr
    params.font_color     = sym[i].fnt
    params.tooltip        = "Lid Color"
    self.createButton(params)
  end

  params.click_function = "doNothing"
  params.color          = "Orange"
  params.label          = "2: FRONT"
  params.font_color     = {0,0,0,1}
  params.tooltip        = "Select Below"
  params.position       = {0,yPos,zPos}
  self.createButton(params)

  local cnt = 0
  for i in pairs(sym) do
    cnt = cnt + 1
    if cnt < 6 then
      local funcName = "dbFront" .. i
      local func = function(obj, ply, alt) setDbFront(i,ply) end
      self.setVar(funcName, func)
      params.click_function = funcName
      params.position       = {0,yPos,zPos+cnt}
      params.label          = sym[i].lbl
      params.color          = sym[i].clr
      params.font_color     = sym[i].fnt
      params.tooltip        = "Lid Color"
      self.createButton(params)
    end
  end

  params.click_function = "doNothing"
  params.color          = "Orange"
  params.label          = "3: SIDE"
  params.font_color     = {0,0,0,1}
  params.tooltip        = "Select Below"
  params.position       = {xPos,yPos,zPos}
  self.createButton(params)


  local cnt = 0
  for i in pairs(sym) do
    cnt = cnt + 1
    if cnt < 6 then
      local funcName = "dbSide" .. i
      local func = function(obj, ply, alt) setDbSide(i,ply) end
      self.setVar(funcName, func)
      params.click_function = funcName
      params.position       = {xPos,yPos,zPos+cnt}
      params.label          = sym[i].lbl
      params.color          = sym[i].clr
      params.font_color     = sym[i].fnt
      params.tooltip        = "Side Color"
      self.createButton(params)
    end
  end

  params.click_function = "btnUpdateDeckbox"
  params.color          = "Brown"
  params.font_color     = "White"
  params.label          = "Apply - "..dbLid..dbFront..dbSide
  params.tooltip        = "Select Below"
  params.position       = {0,yPos,zPos-1}
  params.width          = 6300
  self.createButton(params)

  applyInd = #self.getButtons()
end

function updateApply()
  self.editButton({
    index          = applyInd-1,
    label          = "Apply - "..dbLid..dbFront..dbSide
  })
end

function setDbLid(sym,ply)
  dbLid   = sym
  dbFront = ""
  dbSide  = ""
  updateApply()
end

function setDbFront(sym,ply)
  if dbLid == "c" or dbLid == "m" then
    broadcastToColor("Cannot combine with Colorless or Multi", ply, ply)
    return
  end
  if sym == dbLid then sym = "" end
  dbFront = sym
  dbSide = ""
  updateApply()
end

function setDbSide(sym,ply)
  if dbLid == "c" or dbLid == "m" then
    broadcastToColor("Cannot combine with Colorless or Multi", ply, ply)
    return
  end
  if sym == dbLid or sym == dbFront or dbFront == "" then sym = "" end
  dbSide = sym
  updateApply()
end

function btnUpdateDeckbox(_, ply, alt)
  if alt then
    broadcastToColor("Cancelled Color Select", ply, ply)
    self.reload()
    return
  end
  local mdl = dbFront == "" and mono or duo
  if mdl == mono then
    self.setColorTint(cnvrtClr[dbLid])
  else
    self.setColorTint("White")
  end
  local diff = deckboxes[dbLid..dbFront..dbSide]
  self.setCustomObject({
    mesh = mdl,
    diffuse = diff
  })
  model = mdl
  broadcastToColor("Loading Deckbox: "..dbLid..dbFront..dbSide, ply, ply)
  self.reload()
end


--===========================================================================
--Deckbox Models and Diffuse Images
--===========================================================================
deckboxes = {}
--Deckbox Models
mono = "https://steamusercontent-a.akamaihd.net/ugc/16294693691804414674/BADB419691AEAE37207A9B539BCA13C837DF0406/"
duo  = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333384879/F7C11D3869AFA2447F07B4A8168A4E745834A4BD/"
tri  = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333384879/F7C11D3869AFA2447F07B4A8168A4E745834A4BD/"


--Colorless
deckboxes["c"] = "https://www.dropbox.com/s/o53xastt2846bmt/DeckBox.jpg?dl=1"
deckboxes["m"] = "https://steamusercontent-a.akamaihd.net/ugc/1871804141032985418/238B6D200F339E5A6F2D5A0EEE9C589A09390774/"

--Monocolor
deckboxes["w"] = "https://www.dropbox.com/s/h5dbgwaxz4v60b8/DeckBox_White.jpg?dl=1"
deckboxes["u"] = "https://www.dropbox.com/s/acspj8cs4hukzz4/DeckBox_Blue.jpg?dl=1"
deckboxes["b"] = "https://www.dropbox.com/s/6me42djeef86jem/DeckBox_Black.jpg?dl=1"
deckboxes["r"] = "https://www.dropbox.com/s/pjppwrsgaua0hx9/DeckBox_Red.jpg?dl=1"
deckboxes["g"] = "https://www.dropbox.com/s/gh62dupskxx3xb4/DeckBox_Green.jpg?dl=1"

--2 Color (Lid-Box)
deckboxes["wu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333457116/C2AC8452400499BD418FEE5650B2E404A877B9C0/"
deckboxes["wb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333455862/A99DC4AD9F849BC442B8D3945BFB1A3ADAE703B6/"
deckboxes["wr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333452802/3EC6A68A2EC1EC2A304708E20A707122060D1AE9/"
deckboxes["wg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333433827/E65BD46B87F78DDDB91D1C786D1E368677122B86/"

deckboxes["uw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333458079/82FA1CE215DAE17821BD81913827810C23D07D60/"
deckboxes["ub"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333410032/63592CBD32467714655F1E92F475687CA6D86A4A/"
deckboxes["ur"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333412768/86BBEADFB0A972ADAD23AD636E16DC40B736A69D/"
deckboxes["ug"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333417754/0BD075A0D2DA3F2313A918C63D6BB915E3979982/"

deckboxes["bw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333454883/02BE5D713D75069A1FE92C4D0999F828420E351B/"
deckboxes["bu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333409008/BCF672C1372B33164DE00DC9AA8C93BD6E89EF2D/"
deckboxes["br"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333404885/E9FDC69D4226DD2129E2FF5FD4DC78F98A0E6063/"
deckboxes["bg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333387467/0918F7CC9EBF12F88BA75C00C380990DA9389451/"

deckboxes["rw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333453805/6A2BFA2236F342B9CD5229D750CC11955E19431F/"
deckboxes["ru"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333413655/7B4FD99CC3D0E2212031525E4009DB0E2AE19D89/"
deckboxes["rb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333406001/E98BD70C255E4DD1E4E712C7F2EEF72553EEE3D1/"
deckboxes["rg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333448267/BC46D3B3EC67203C82AD1BF9C1217ABF53774F32/"

deckboxes["gw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333432732/3A77FE4E5B3B55AEA7EA088FFE381B3C2240A90C/"
deckboxes["gu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333418855/7E3C4B915B479BB56C292D6EE22B485A732BBDE2/"
deckboxes["gb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333396261/9AF6673AE5E8A3A8BAB08A3A0F1E07369541B31E/"
deckboxes["gr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423148333447338/CAD435F0635A21469268EFB9524C64B71F7ED5E0/"


--3 Color (Lid-Front-Side)
deckboxes["wub"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585116111/3ABF741F386698B5DA4968BE2F3857E4F1AC9B10/"
deckboxes["wur"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585111957/691D56941E5F7F41F5509995786A9D13DF20838C/"
deckboxes["wug"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585175168/AA92DD662E9AB0753B535466E312F960BED783ED/"

deckboxes["wbu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585118439/2D9AEC269B60D1821119B90A70D5BF4288E9F2DA/"
deckboxes["wbr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585079729/09A1191BB71BAFA36991D1A4743ACC68454F544F/"
deckboxes["wbg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585071802/A650051B7BE06BBE6985DA5825245F813F30C0AD/"

deckboxes["wru"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585110002/6A5F8468CB926551001F6AE368FEA200E58261D6/"
deckboxes["wrb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423033471707549/2AEDF6F88333CD2EF5AEA5F692F5F0EA67A657FF/"
deckboxes["wrg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585187735/40DACD7C9C6BE36A5E40B815D60576753675DCC5/"

deckboxes["wgu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585178379/DAE606882C31A001CAF18B8296D761A35EFFDFE1/"
deckboxes["wgb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585070953/5DEDA3DAFB39D6C1350AFB2FE5965BFC9B9EA67B/"
deckboxes["wgr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585186963/4D1E1063C5766ADEAA247FB259C7833AA1F3357E/"

deckboxes["uwb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585120416/076D60816C5BE3D4018AA83E7CFF4BD33B36DDCD/"
deckboxes["uwr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585100606/A09314CDAA20DE9948B998047DDFB31F2F37D8B7/"
deckboxes["uwg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585172135/209BD26AFBC613492021B0ADCCBA83B5A1426DF3/"

deckboxes["ubw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585172135/209BD26AFBC613492021B0ADCCBA83B5A1426DF3/"
deckboxes["ubr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585090023/BECA164138D575038D3374ABFEB435F90802C326/"
deckboxes["ubg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585059915/43A1C7841183621BDAE42D53E3D5DE1A0B100BEE/"

deckboxes["urw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585099007/B1A139F1B15C55F354B550D694ACB3E808D8EBC8/"
deckboxes["urb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585091374/02663D413D99E4E45AB07EE8534AB33D1E8F2204/"
deckboxes["urg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585147009/2D5D13A44ABFA390C787D62543F65E9EA552B7EA/"

deckboxes["ugw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585153132/EB31B5C42BF710E0FB766C9C0B351A95BD80F934/"
deckboxes["ugb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585061058/0F9D63D73EF5799C41333CCF4E739B42F16E568A/"
deckboxes["ugr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585156376/60AC6C0DFDC77BBB9C883F4FDB0589450F12C5BA/"

deckboxes["bwu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585122533/F83CF9A2315896B5E00F127870AFF261F116EEEA/"
deckboxes["bwr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585083723/AAA974CC5F9CDF4E06C931663E195E484D16AD6C/"
deckboxes["bwg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423033471705857/CD428E010FBF2FE27CD7FCFB1C55CB336AE4C758/"

deckboxes["buw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585124139/E2C6B01D4EF760AA97135E5D807B7DA007389006/"
deckboxes["bur"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585093346/2977904989B349FACC1B17F6AAAB47F44EEB33AD/"
deckboxes["bug"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585065705/12D46BC40852AF12C9B5C1A5EE212D6B3AAAEBED/"

deckboxes["brw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585082907/65AC46106DFA4D15E9174978207D9632107A3AF1/"
deckboxes["bru"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585092417/6A4BA18BF2EFB32F0B0AD5794AD97B215228D16F/"
deckboxes["brg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585134603/43CDAD2124F85B096BD59747F1DC242D8E39432D/"

deckboxes["bgw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585070147/4A941631903E1267991CCFEF09A4B4A0917287CE/"
deckboxes["bgu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585064736/D845089205C90A32F30037E549FF3AA40E36C00C/"
deckboxes["bgr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585135639/B6D5C6D8B44CE66424044EC52A77AF13CA684786/"

deckboxes["rwu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585104103/A6E522CC3DD8B8DAE7B9477B271F16FC93D4CA1C/"
deckboxes["rwb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585084721/2CA63CAEA1E3E349E8AC30875BCC543006E7345C/"
deckboxes["rwg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585185199/15558E995E69847A294421A6D78421494F4A8B46/"

deckboxes["ruw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585105358/649AB427C5E9833D388754EEB4FD101197309D53/"
deckboxes["rub"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585094382/D535B15CA4FE7212CD48151A2FC117A9BCDC6C07/"
deckboxes["rug"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585159855/E25B8657D0BCF00186ABDBDE8C31301BA167C094/"

deckboxes["rbw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585085530/CAC32D975EC77BD9F983425E89D10AE77A8D5D3F/"
deckboxes["rbu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585096463/1AF961C2DC672CE84AF92827044A46E5BC1F135D/"
deckboxes["rbg"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585131180/E16AFB229242CDBABDB79242FADB1347D5471422/"

deckboxes["rgw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585186161/635A6152178DC671FF41BBE5A87EB45F1CB2E91B/"
deckboxes["rgu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585157812/E0343EEE21EDDBECE2C358C989DEE0C708B99960/"
deckboxes["rgb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585128626/BE903BCD723B8C8C2A6590033081ED6A077545DB/"

deckboxes["gwu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585173825/3A5B6197A8B225794A09DD473AB007919A99C767/"
deckboxes["gwb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585073673/0A32004B3FC8F6EB85962CC1CD3DA390C86DC3B2/"
deckboxes["gwr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585184404/16CEE9D483E5D0E46436F6B2EC99896C95FBFDBA/"

deckboxes["guw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585177089/E08F128F8565410AE8EC25DE127AD7925FFB9DDC/"
deckboxes["gub"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423033471703977/5FAFC0CF685712C84E978BE38911C060D0D7A5E0/"
deckboxes["gur"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585163119/23F21B9E06BCE82D37DBF2A67B6E69458508FC91/"

deckboxes["gbw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585072930/F1BCA70F3DA328A18DCE5AD203B6ECDE52D381CC/"
deckboxes["gbu"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585058826/2083063F92555C7A85D16F4F957EBECE9D835CCE/"
deckboxes["gbr"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585132368/FB35AA01F1F7BE8CD89276C60032457159B4D4A3/"

deckboxes["grw"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585181077/D679C0AFA0CEEBE86BAABBB32143EB3F135A5F7A/"
deckboxes["gru"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585164617/BDEB34373197D18711165624499B047E655DFDB2/"
deckboxes["grb"] = "https://steamusercontent-a.akamaihd.net/ugc/1734423300585133567/CD6FACDE5EE1821D75E43730A9DD97972C7BF2DF/"

--===========================================================================
--DEBUG Utility Functions
--===========================================================================
function pDump(t)
  print(dump(t))
end

function dump(o)
  if type(o) == 'table' then
    local s = '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..']' .. dump(v) .. ','
    end
    return (s .. '} \n')
  else
    return tostring(o)
  end
end