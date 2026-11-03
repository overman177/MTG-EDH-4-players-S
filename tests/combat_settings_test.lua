-- Lua 5.2: per-seat Undo hold preference, persistence and General UI shape.
local attrs, persists = {}, 0
UI={setAttribute=function(id,key,value)
    attrs[id]=attrs[id] or {}
    attrs[id][key]=value
end}
Playmats={persist=function() persists=persists+1 end}
self={getGUID=function() return "185063" end}
dofile("src/lotus/sections/03_edh-settings.lua")

-- Prior saves have no hold preference. Every player gets a 5s default.
Settings.normalize()
for _,c in ipairs(Settings.OWNERS) do
    assert(Settings.getUndoHold(c)==5,"default hold threshold for "..c)
end
Settings.menuOwner="White"
Settings.changeUndoHold({color="White"},"7","lotus_combat_hold_slider")
assert(Settings.getUndoHold("White")==7 and persists==1,"owner slider saves")
assert(Settings.getUndoHold("Blue")==5,"other seat not affected")
assert(attrs.lotus_combat_hold_value.text=="7 s","value label reflects slider")
Settings.changeUndoHold({color="White"},"7","lotus_combat_hold_slider")
assert(persists==1,"same value must not resave")
Settings.changeUndoHold({color="Blue"},"2","lotus_combat_hold_slider")
Settings.changeUndoHold({color="White"},"2","not_a_slider")
assert(Settings.getUndoHold("Blue")==5 and Settings.getUndoHold("White")==7,
    "only owner and correct slider id accepted")
Settings.changeUndoHold("White","99","lotus_combat_hold_slider")
assert(Settings.getUndoHold("White")==10,"max clamp")
Settings.changeUndoHold("White","0","lotus_combat_hold_slider")
assert(Settings.getUndoHold("White")==1,"min clamp")
Settings.changeUndoHold("White","bad","lotus_combat_hold_slider")
assert(Settings.getUndoHold("White")==5,"invalid value defaults")
Settings.changeUndoHold("White","8","lotus_combat_hold_slider")

Settings.syncUI()
assert(attrs.lotus_combat_hold_slider.value=="8","slider reflects current owner")
assert(attrs.lotus_combat_hold_value.text=="8 s","label reflects current owner")
Settings.menuOwner="Blue"
Settings.syncUI()
assert(attrs.lotus_combat_hold_slider.value=="5","switching seats resyncs slider")
Settings.changeUndoHold("Blue","3","lotus_combat_hold_slider")
assert(Settings.getUndoHold("White")==8 and Settings.getUndoHold("Blue")==3,
    "personal settings remain distinct")

local export=Settings.export()
assert(export.combatUndoHoldSecondsByColor.White==8 and
       export.combatUndoHoldSecondsByColor.Blue==3,"saved payload contains values")
Settings.combatUndoHoldSecondsByColor={}
assert(Settings.import({combatUndoHoldSecondsByColor={
    White=export.combatUndoHoldSecondsByColor.White,
    Blue=export.combatUndoHoldSecondsByColor.Blue,
    Red=123
}}),"can import per-player threshold alone")
assert(Settings.getUndoHold("White")==8 and Settings.getUndoHold("Blue")==3)
assert(Settings.getUndoHold("Red")==10 and Settings.getUndoHold("Yellow")==5,
    "import clamps bad values and normalizes defaults")

local function findNode(node,id)
    if node.attributes and node.attributes.id==id then return node end
    for _,child in ipairs(node.children or {}) do
        local found=findNode(child,id)
        if found then return found end
    end
end
local tab=Settings.generalTab()
assert(findNode(tab,"lotus_combat_bind"),"game keys button remains")
local function assertAbsentText(node,phrase)
    if node.attributes and type(node.attributes.text)=="string" then
        assert(not node.attributes.text:find(phrase,1,true),
            "redundant combat description must not be shown")
    end
    for _,child in ipairs(node.children or {}) do assertAbsentText(child,phrase) end
end
assertAbsentText(tab,"DRAW: defender to attacker.")
assertAbsentText(tab,"1-10 seconds  |")

assert(not findNode(tab,"lotus_combat_undo") and
       not findNode(tab,"lotus_combat_clear"),"obsolete buttons are absent")
assert(findNode(tab,"MTG_Settings_GeneralContent_v155"),"new General tab version")
local slider=findNode(tab,"lotus_combat_hold_slider")
assert(slider and slider.tag=="Slider","hold duration is a slider")
assert(slider.attributes.minValue=="1" and slider.attributes.maxValue=="10" and
       slider.attributes.wholeNumbers=="true","valid whole-second range")
assert(slider.attributes.onValueChanged=="185063/settingsCombatHoldChanged",
       "slider routed to Lotus callback")
print("Combat hold slider, persistence, seat isolation and UI tests passed.")
