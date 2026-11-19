-- Reveal Top previews must run alongside the library-zone side edge.
-- Six-seat rotation must not introduce a diagonal displacement.
dofile("src/lotus/sections/05_always-reveal-top-non-colliding-visual-clone.lua")
local zones = {}
getObjectFromGUID = function(guid) return zones[guid] end
getObjectsWithTag = function() return {} end
local function axis(yaw)
    local rad=math.rad(yaw)
    return math.cos(rad),-math.sin(rad)
end
local function makeZone(color,x,z,yaw,width)
    local zone={type="Scripting"}
    zone.hasTag=function(tag) return tag=="Library" or tag==color end
    zone.getPosition=function() return {x=x,y=1,z=z} end
    zone.getTransformRight=function()
        local rx,rz=axis(yaw)
        return {x=rx,y=0,z=rz}
    end
    zone.getBoundsNormalized=function()
        return {size={x=width,y=1,z=4}}
    end
    -- A generous world AABB must not override the local normalized width.
    zone.getBounds=function() return {size={x=8,y=1,z=8}} end
    zones[RevealTop.LIBRARY_GUIDS[color]]=zone
    return zone
end
local function makeLibrary(x,z,yaw,width)
    local library={}
    library.isDestroyed=function() return false end
    library.getPosition=function() return {x=x,y=1,z=z} end
    library.getRotation=function() return {x=0,y=yaw,z=180} end
    library.getTransformRight=function()
        local rx,rz=axis(yaw)
        return {x=rx,y=0,z=rz}
    end
    library.getBoundsNormalized=function()
        return {size={x=width,y=0.3,z=3.5}}
    end
    library.getBounds=function()
        return {center={x=x,y=1,z=z},size={x=width,y=0.3,z=3.5}}
    end
    return library
end
for _, sample in ipairs({
    {color="Blue",x=11,z=5,yaw=0},
    {color="White",x=-13,z=-6,yaw=0},
    {color="Red",x=3,z=15,yaw=60},
    {color="Yellow",x=-15,z=3,yaw=120},
}) do
    local deck=makeLibrary(sample.x,sample.z,sample.yaw,2.5)
    makeZone(sample.color,sample.x,sample.z,sample.yaw,3.0)
    local view=RevealTop.topPosition(deck,sample.color)
    local rx,rz=axis(sample.yaw)
    if sample.x*rx+sample.z*rz<0 then rx,rz=-rx,-rz end
    local dx,dz=view.x-sample.x,view.z-sample.z
    local sideways=dx*rx+dz*rz
    local longitudinal=dx*(-rz)+dz*rx
    assert(math.abs(longitudinal)<0.001,
        "Preview drifts diagonally off the zone axis for "..sample.color)
    local expected=math.max(RevealTop.OUTSIDE_DECK_GAP,
        2.5+RevealTop.PREVIEW_EDGE_GAP,
        1.5+1.25+RevealTop.OUTSIDE_ZONE_GAP)
    assert(math.abs(sideways-expected)<0.01,
        "Preview is not adjacent to the Library zone for "..sample.color)
    assert(sideways-1.25>=1.5+RevealTop.OUTSIDE_ZONE_GAP-0.01,
        "Preview still overlaps the Library zone")
    assert(sideways<3.2, "Preview spaced too far from the zone")
end

-- Off-center libraries remain next to their deck without diagonal drift.
makeZone("Blue",11,5,0,3)
local shifted=makeLibrary(12,3,0,2.5)
local shiftedPos=RevealTop.topPosition(shifted,"Blue")
assert(math.abs(shiftedPos.z-3)<0.001,
    "Preview must retain the deck's lengthwise alignment")
assert(shiftedPos.x>12, "Wrong outward side for offset library")

-- Existing visual follows the same axis after a deck moves.
local objPos={x=0,y=0,z=0}
local visual={
    isDestroyed=function()return false end,
    hasTag=function(tag)return tag==RevealTop.VISUAL_TAG end,
    getPosition=function()return objPos end,
    setPosition=function(p)objPos=p end,
    getRotation=function()return {x=0,y=0,z=0} end,
    setRotation=function()end
}
RevealTop.visuals.Blue=visual
RevealTop.follow("Blue",shifted)
assert(math.abs(objPos.z-3)<0.001 and objPos.x>12,
    "Follow should retain local sideways alignment")

-- No zone: preserve separation and use the library's own local right axis.
zones={}
local fallback=makeLibrary(-15,-5,0,2.5)
local fp=RevealTop.topPosition(fallback,"Blue")
assert(fp.x<-17.4 and math.abs(fp.z+5)<0.001)

print("Reveal Top zone-aligned sideways positioning: OK")
