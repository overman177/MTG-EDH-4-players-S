-- Regression: random draws from revealed libraries pause visual clones safely.
dofile("src/lotus/sections/05_always-reveal-top-non-colliding-visual-clone.lua")

local removed, dealt, callbacks, refreshed = 0, 0, {}, 0
local clone = {dead=false}
clone.isDestroyed=function() return clone.dead end
clone.hasTag=function(tag) return tag==RevealTop.VISUAL_TAG end
clone.destruct=function() removed=removed+1; clone.dead=true end

local deck = {type="Deck"}
deck.isDestroyed=function() return false end
deck.getGUID=function() return "deck123" end
deck.getObjects=function() return {{guid="one234",name="Test Card"}} end
deck.takeObject=function(params)
    assert(params.guid=="one234")
    local card={type="Card",spawning=false}
    card.isDestroyed=function() return false end
    card.deal=function(count,color,hand)
        assert(count==1 and color=="Blue" and hand==1)
        dealt=dealt+1
    end
    params.callback_function(card)
end
local zone={type="Scripting"}
zone.isDestroyed=function() return false end
zone.getGUID=function() return "zone999" end
zone.hasTag=function(tag) return tag=="Library" end
zone.getObjects=function(ignore) assert(ignore==true); return {deck} end
getObjectsWithTag=function(tag)
    if tag=="Library" then return {zone} end
    if tag=="LotusRT_Blue" then return {clone} end
    return {}
end
Wait={
    frames=function(callback,frames)
        assert(frames==45)
        callbacks[#callbacks+1]=callback
    end,
    condition=function(callback,ready)
        if ready() then callback() end
    end
}
Player={Blue={getHandCount=function() return 1 end}}
broadcastToColor=function() end
RevealTop.enabled.Blue=true
RevealTop.visuals.Blue=clone
RevealTop.findLibrary=function(color)
    if color=="Blue" then return deck end
end
RevealTop.poll=function() refreshed=refreshed+1 end

local f=assert(io.open("src/lotus/sections/02_draw-random.lua","rb"))
local drawSource=f:read("*a")
f:close()
local DrawRandom=assert(load(drawSource.."\nreturn DrawRandom","@DrawRandom.lua"))()
DrawRandom.draw("Blue",nil,deck)
assert(dealt==1 and removed==1, "first draw must deal once and remove preview")
assert(RevealTop.paused.Blue==true, "preview should pause during deck mutation")
assert(refreshed==0 and #callbacks==1, "preview refreshed before draw stabilized")
DrawRandom.draw("Blue",nil,deck)
assert(dealt==2 and #callbacks==2, "second draw should work before first pause ends")
callbacks[1]()
assert(RevealTop.paused.Blue==true, "stale callback must not resume preview")
callbacks[2]()
assert(not RevealTop.paused.Blue and refreshed==1, "latest draw should refresh once")

local stale={type="Deck", getGUID=function() error("expired Unity object") end}
assert(pcall(RevealTop.onDestroy, stale), "destroyed deck callback must be safe")
assert(not RevealTop.suspendDuringDraw({isDestroyed=function() return false end}),
    "non-library objects must not pause the reveal")
print("4P Draw Random + Reveal Top integration test passed")
