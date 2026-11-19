-- All preview positions must be radially outside their Library zones.
dofile("src/lotus/sections/05_always-reveal-top-non-colliding-visual-clone.lua")
local zones = {}
getObjectFromGUID = function(guid) return zones[guid] end
getObjectsWithTag = function() return {} end
local function makeZone(color, x, z, sizeX, sizeZ)
    local zone={type="Scripting"}
    zone.hasTag=function(tag) return tag=="Library" or tag==color end
    zone.getPosition=function() return {x=x,y=1,z=z} end
    zone.getBounds=function()
        return {size={x=sizeX,y=1,z=sizeZ}}
    end
    zones[RevealTop.LIBRARY_GUIDS[color]]=zone
    return zone
end
local function makeLibrary(x,z)
    local library={}
    library.isDestroyed=function() return false end
    library.getPosition=function() return {x=x,y=1,z=z} end
    library.getBounds=function()
        return {center={x=x,y=1,z=z},size={x=2.5,y=0.3,z=3.6}}
    end
    library.getRotation=function() return {x=0,y=0,z=180} end
    return library
end
for _, sample in ipairs({
    {color="Blue",x=11,z=5,width=5,depth=3},
    {color="White",x=-13,z=-6,width=6,depth=4},
}) do
    makeZone(sample.color,sample.x,sample.z,sample.width,sample.depth)
    local deck=makeLibrary(sample.x,sample.z)
    local preview=RevealTop.topPosition(deck,sample.color)
    local length=math.sqrt(sample.x*sample.x+sample.z*sample.z)
    local dx,dz=sample.x/length,sample.z/length
    local outward=(preview.x-sample.x)*dx+(preview.z-sample.z)*dz
    local zoneExtent=0.5*(math.abs(dx)*sample.width+
        math.abs(dz)*sample.depth)
    assert(outward>=zoneExtent+RevealTop.OUTSIDE_ZONE_GAP-0.01,
        "Preview is still in the Library zone: "..sample.color)
    assert(outward>=RevealTop.OUTSIDE_DECK_GAP-0.01,
        "Preview is close enough to merge with the deck")
    assert(outward>0,"Preview went inward instead of toward table edge")
end

local moved=makeLibrary(12,4)
local previewPosition={x=12,y=1,z=4}
local preview={
    isDestroyed=function()return false end,
    hasTag=function(tag)return tag==RevealTop.VISUAL_TAG end,
    getPosition=function()return previewPosition end,
    setPosition=function(p)previewPosition=p end,
    getRotation=function()return {x=0,y=0,z=0} end,
    setRotation=function()end
}
RevealTop.visuals.Blue=preview
RevealTop.follow("Blue",moved)
assert(previewPosition.x>12 and previewPosition.z>4,
    "Follow relocated the preview back over the deck")

-- A missing/dead zone must fail toward separation, never return deck center.
zones={}
local fallback=RevealTop.topPosition(makeLibrary(15,-7),"Blue")
local movedDist=math.sqrt((fallback.x-15)^2+(fallback.z+7)^2)
assert(movedDist>=RevealTop.OUTSIDE_DECK_GAP-0.01,
    "Missing zone left preview over library")

local f=assert(io.open("src/lotus/sections/05_always-reveal-top-non-colliding-visual-clone.lua","rb"))
local source=f:read("*a")
f:close()
assert(source:find("RevealTop.topPosition(library, color)",1,true))
assert(source:find("pcall(RevealTop.topPosition, info.library, color)",1,true))
assert(source:find("RevealTop.topPosition(fresh.library, color)",1,true))
print("Reveal Top stays outward and outside the library zone: OK")
