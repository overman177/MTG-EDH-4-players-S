-- Run with lua5.2 tests/preview_pipeline_test.lua
local f = assert(io.open("src/lotus/sections/00_card-preview.lua", "r"))
local source = f:read("*a")
f:close()
source = source:gsub("local Preview = {", "Preview = {", 1)
assert(load(source, "@card-preview", "t", _ENV))()
local assets, attributes, writes, frameQueue = {}, {}, 0, {}
UI = {
    loading = false,
    getCustomAssets = function() return assets end,
    setCustomAssets = function(next) assets = next; writes = writes + 1 end,
    setAttribute = function(id, key, value) attributes[id.."."..key] = value end
}
Wait = {
    frames = function(fn) frameQueue[#frameQueue+1] = fn end,
    condition = function(fn, ready) if ready() then fn() else error("load delay") end end,
    time = function() return 123 end,
    stop = function() end
}
local function drainOnce()
    local functions = frameQueue
    frameQueue = {}
    for _, fn in ipairs(functions) do fn() end
end
local present = false
local card = {tag="Card", is_face_down=false, tags={}, face="https://example.com/a.png"}
function card.getGUID() return "a1b2c3" end
function card.isDestroyed() return false end
function card.getName() return "Example Creature\nCreature 2CMC" end
function card.getCustomObject() return {face=card.face} end
function card.getPosition() return {x=0,y=1,z=0} end
function card.getZones() return {} end
function card.hasTag(name) return card.tags[name] == true end
function card.addTag(name) card.tags[name] = true end
function card.removeTag(name) card.tags[name] = nil end
local battlefield = {
    type="Scripting",
    hasTag=function(name) return name=="Battlefield" or name=="Blue" end,
    getObjects=function() return present and {card} or {} end
}
getObjectsWithTag = function(name)
    return name=="Battlefield" and {battlefield} or {}
end
Player = {Blue={getHandObjects=function() return {} end}}
Preview.onEnterZone({type="Hand"}, card)
assert(card.hasTag(Preview.HAND_TAG))
Preview.onDrop("Blue", card)
drainOnce()
assert(card.hasTag(Preview.HAND_TAG))
present = true
drainOnce()
assert(not card.hasTag(Preview.HAND_TAG))
assert(attributes["MTG_CastDisplay.active"] == "true")
assert(attributes["MTG_CastImage.image"] == "MTG_CAST_PREVIEW_1")
assert(writes == 1)
local same, isNew = Preview.assetForFace(card.face)
assert(same=="MTG_CAST_PREVIEW_1" and not isNew and writes==1)
local another, fresh = Preview.assetForFace("https://example.com/b.png")
assert(another=="MTG_CAST_PREVIEW_2" and fresh and writes==2)

local commander = "b1b2c3"
function card.getGUID() return commander end
present = false
card.addTag(Preview.HAND_TAG)
Preview.commanderPending[commander] = "Blue"
Preview.onDrop("Blue", card)
drainOnce()
assert(Preview.commanderPending[commander]=="Blue")
present = true
drainOnce()
assert(Preview.commanderPending[commander]==nil)
assert(Preview.commanderFirstShown[commander]==true)
assert(not card.hasTag(Preview.HAND_TAG))

card.tags = {}
function card.getZones() return {{type="Hand"}} end
Preview.onPickUp("Blue", card)
assert(card.hasTag(Preview.HAND_TAG))

assets = {{name="unrelated_image",url="https://example.com/other.png"}}
for i=1,Preview.ASSET_CACHE_LIMIT do
    assets[#assets+1]={name="MTG_CAST_PREVIEW_"..i,url="https://example.com/"..i}
end
local _, added=Preview.assetForFace("https://example.com/new.png")
assert(added and #assets==Preview.ASSET_CACHE_LIMIT+1)
assert(assets[1].name=="unrelated_image")
print("Preview pipeline tests passed")
