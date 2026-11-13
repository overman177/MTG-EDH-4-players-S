-- Offline checks: The One Ring hover behavior and animated boot banner.
local f = assert(io.open("live/objects/game-mechanics/THE ONE RING.2d70e1.lua", "rb"))
local ringSource = f:read("*a")
f:close()
assert(ringSource:find('CARD_GUID = "d9fcbc"', 1, true))
local card = {
    pos = {x=3, y=2, z=-5},
    rot = {x=0, y=35, z=0}
}
function card.getPosition() return card.pos end
function card.getRotation() return card.rot end
function getObjectFromGUID(guid)
    assert(guid == "d9fcbc")
    return card
end
local currentPosition = nil
local currentRotation = nil
local locked = false
self = {
    getRotation = function() return {x=12, y=21, z=34} end,
    setLock = function(state) locked = state end,
    setPosition = function(pos) currentPosition = pos end,
    setRotation = function(rot) currentRotation = rot end
}
assert(load(ringSource))()
onLoad()
assert(locked and self.interactable == false and self.tooltip == false)
onUpdate()
assert(currentPosition.x == 3 and currentPosition.z == -5)
assert(currentPosition.y > 2.90 and currentPosition.y < 3.06)
assert(currentRotation.x == 12 and currentRotation.z == 34)
card.pos = {x=-7, y=4, z=8}
card.rot.y = 95
onUpdate()
assert(currentPosition.x == -7 and currentPosition.z == 8 and currentPosition.y > 4.90)
assert(currentRotation.y > 81)
card = nil
onUpdate() -- missing card is harmless, including on a new scene load
local showCalls, hideCalls, changed, scheduled = {}, {}, {}, {}
UI = {
    getCustomAssets = function() return {{name="MTG_Cinematic_Logo",url="https://example.invalid/logo.png"}} end,
    setAttribute = function(id, attribute, value)
        changed[id .. ":" .. attribute] = value
    end,
    show = function(id) table.insert(showCalls, id) end,
    hide = function(id) table.insert(hideCalls, id) end
}
Wait = {time = function(fn, delay) table.insert(scheduled, {fn=fn, delay=delay}) end}
dofile("src/global/sections/32_patch-notes.lua")
mtgShowVersionBanner()
assert(showCalls[1] == "MTG_CinematicSplash")
assert(changed["MTG_SplashVersion:text"]:find(VERSION, 1, true))
assert(changed["MTG_SplashArtwork:active"] == "false")
assert(#scheduled >= 28)
local original = scheduled
for _,task in ipairs(original) do task.fn() end
assert(changed["MTG_SplashProgress:percentage"] == "100")
assert(changed["MTG_SplashStatus:text"] == "READY TO PLAY")
assert(hideCalls[#hideCalls] == "MTG_CinematicSplash")
-- A rerun invalidates queued work from the previous intro.
scheduled = {}
mtgShowVersionBanner()
local first = scheduled[1].fn
mtgSkipLoadingScreen()
local before = #showCalls
first()
assert(#showCalls == before)
assert(hideCalls[#hideCalls] == "MTG_CinematicSplash")
local x = assert(io.open("src/ui/sections/08_lotus-settings.xml", "rb"))
local xmlText = x:read("*a")
x:close()
assert(xmlText:find('id="MTG_CinematicSplash"', 1, true))
assert(xmlText:find('onClick="mtgSkipLoadingScreen"', 1, true))
assert(xmlText:find('image="MTG_Cinematic_Logo"', 1, true))
print("Ring follow and cinematic startup tests passed.")
