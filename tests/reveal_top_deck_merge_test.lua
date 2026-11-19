-- Run with lua5.2 tests/reveal_top_deck_merge_test.lua
-- Simulate old library Deck destruction before an async visual spawn callback.
local f = assert(io.open("src/lotus/sections/05_always-reveal-top-non-colliding-visual-clone.lua", "rb"))
local source = f:read("*a")
f:close()
assert(load(source, "@reveal-top", "t", _ENV))()
local pending = {}
local nextFrames = {}
Wait = {frames = function(fn) nextFrames[#nextFrames + 1] = fn end}
getObjectFromGUID = function() return nil end
local function library(guid, name, cardGuid)
    local obj = {type="Deck", dead=false, UI={getXmlTable=function() return {} end}}
    function obj.getGUID() return guid end
    function obj.isDestroyed() return obj.dead end
    function obj.hasTag() return false end
    function obj.getObjects()
        assert(not obj.dead, "reading destroyed Deck")
        return {{name=name, guid=cardGuid}}
    end
    function obj.getData()
        assert(not obj.dead, "reading destroyed Deck")
        return {ContainedObjects={{GUID=cardGuid, Name="Card", Transform={}}}}
    end
    function obj.getPosition()
        assert(not obj.dead, "position of destroyed Deck")
        return {x=0,y=1,z=0}
    end
    function obj.getRotation()
        assert(not obj.dead, "rotation of destroyed Deck")
        return {x=0,y=0,z=180}
    end
    function obj.getBounds()
        assert(not obj.dead, "bounds of destroyed Deck")
        return {center={x=0,y=1,z=0},size={x=2,y=0.5,z=3}}
    end
    function obj.addContextMenuItem() end
    return obj
end
local old = library("old111", "Old Top", "card01")
local replacement = library("new222", "New Top", "card02")
local active = old
local zone = {type="Scripting"}
function zone.hasTag(tag) return tag=="Library" or tag=="Blue" end
function zone.getObjects() return {active} end
function zone.positionToLocal() return {x=0,z=0} end
getObjectsWithTag = function(tag) return tag=="Library" and {zone} or {} end
spawnObjectData = function(params) pending[#pending+1] = params end
local function visual(guid)
    local obj = {dead=false, tags={}}
    function obj.getGUID() return guid end
    function obj.isDestroyed() return obj.dead end
    function obj.hasTag(tag) return obj.tags[tag] == true end
    function obj.addTag(tag) obj.tags[tag] = true end
    function obj.destruct() obj.dead=true end
    function obj.setLock() end
    function obj.setPosition(p) obj.pos=p end
    function obj.getPosition() return obj.pos or {x=0,y=0,z=0} end
    function obj.setRotation(r) obj.rot=r end
    function obj.getRotation() return obj.rot or {x=0,y=0,z=0} end
    local collider={enabled=true}
    collider.set=function(name,val)
        assert(name=="enabled")
        collider.enabled=val
    end
    collider.get=function(name)
        assert(name=="enabled")
        return collider.enabled
    end
    function obj.getComponentsInChildren(kind)
        if kind=="BoxCollider" then return {collider} end
        return {}
    end

    function obj.getComponent() return nil end
    return obj
end
RevealTop.enabled.Blue = true
RevealTop.poll()
assert(#pending == 1, "first clone not requested")
old.dead = true
active = replacement
local stale = visual("visual1")
assert(pcall(pending[1].callback_function, stale), "stale callback raised")
assert(#nextFrames == 1, "stale preview must wait outside the table")
nextFrames[1]()
assert(stale.dead and RevealTop.signatures.Blue == nil,
    "stale clone must be discarded and retried")
RevealTop.poll()
assert(#pending == 2, "new Deck should receive a fresh visual")
local correct = visual("visual2")
assert(pcall(pending[2].callback_function, correct), "new callback raised")
assert(not correct.dead and correct.tags[RevealTop.VISUAL_TAG],
    "current Deck should receive a valid visual")
assert(#nextFrames == 2, "replacement visual must wait for colliders")
nextFrames[2]()
assert(correct.pos ~= nil and correct.pos.y < 10,
    "verified visual should move from staging position to deck")
assert(RevealTop.visuals.Blue == correct,
    "verified visual should be registered for following")
print("Reveal Top deck-merge regression test passed")
