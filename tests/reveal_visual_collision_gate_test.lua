-- Collision gate: cloned preview must never touch the library before TTS
-- confirms that its Unity collider has been disabled.
local read=assert(io.open("src/lotus/sections/05_always-reveal-top-non-colliding-visual-clone.lua","rb"))
assert(load(read:read("*a"),"@reveal-top","t",_ENV))()
read:close()
local staging, spawnCallback, frameQueue
frameQueue={}
Wait={frames=function(fn,n) frameQueue[#frameQueue+1]=fn end}
local source = {isDestroyed=function()return false end}
local cardGuid="card1"
RevealTop.prepareClone=function()return {Name="Card",Tags={RevealTop.VISUAL_TAG}} end
RevealTop.topPosition=function()return {x=3,y=2,z=4} end
RevealTop.faceUpRotation=function()return {x=0,y=0,z=0} end
RevealTop.inspect=function()return {signature="original",library=source} end
spawnObjectData=function(p)
    staging=p.position
    spawnCallback=p.callback_function
end
RevealTop.enabled.White=true
RevealTop.versions.White=1
RevealTop.paused.White=nil
local function makeVisual(withCollider)
    local obj={destroyed=false,vis=true,position=nil}
    obj.isDestroyed=function()return obj.destroyed end
    obj.hasTag=function(tag)return tag==RevealTop.VISUAL_TAG end
    obj.addTag=function() end
    obj.setLock=function()end
    obj.setPosition=function(p)obj.position=p end
    obj.setRotation=function()end
    obj.getGUID=function()return cardGuid end
    obj.destruct=function()obj.destroyed=true end
    local col={enabled=true}
    col.set=function(name,v)col.enabled=v end
    col.get=function(name)return col.enabled end
    obj.getComponentsInChildren=function(kind)
        if withCollider and kind=="BoxCollider" then return {col} end
        return {}
    end
    obj.getComponent=function()return nil end
    return obj
end
local full={library=source,signature="original"}
RevealTop.spawnVisual("White",full)
assert(staging and staging.y>12,"clone spawned dangerously close to deck")
local bad=makeVisual(false)
spawnCallback(bad)
assert(#frameQueue==1,"clone should wait for component initialization")
frameQueue[1]()
assert(bad.destroyed,"unverified clone must be destroyed")
assert(bad.position==nil,"unsafe clone moved near deck")
assert(RevealTop.visuals.White==nil,"unsafe clone entered visual registry")
frameQueue={}
RevealTop.versions.White=2
RevealTop.spawnVisual("White",full)
local good=makeVisual(true)
spawnCallback(good)
assert(good.position==nil,"clone moved before collider validation")
assert(#frameQueue==1)
frameQueue[1]()
assert(not good.destroyed and good.position and good.position.y==2)
assert(RevealTop.visuals.White==good,"safe clone not displayed")
print("Reveal Top collision-gated preview: OK")
