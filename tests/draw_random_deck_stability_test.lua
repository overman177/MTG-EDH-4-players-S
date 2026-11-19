-- Random extraction must not impart collision forces to the library.
local deck={type="Deck",locked=false,x=13,y=1,z=-6,drawn=0}
deck.isDestroyed=function()return false end
deck.getGUID=function()return "deck12" end
deck.getPosition=function()return {x=deck.x,y=deck.y,z=deck.z} end
deck.getObjects=function()return {{guid="card12"}} end
deck.setLock=function(value) deck.locked=value end
deck.takeObject=function(params)
    assert(params.guid=="card12" and params.index==nil)
    assert(params.position and params.position.y>=deck.y+5,
        "Extracted card could collide with its source deck")
    assert(params.position.x==deck.x and params.position.z==deck.z)
    assert(deck.locked,"Source deck not stabilized during extraction")
    local card={type="Card",spawning=false}
    card.isDestroyed=function()return false end
    card.deal=function(count,color,hand)
        assert(count==1 and color=="White" and hand==1)
        deck.drawn=deck.drawn+1
    end
    params.callback_function(card)
end
local zone={type="Scripting"}
zone.isDestroyed=function()return false end
zone.getGUID=function()return "zone12" end
zone.hasTag=function(tag)return tag=="Library" end
zone.getObjects=function(ignore)assert(ignore==true);return {deck} end
getObjectsWithTag=function(tag)
    if tag=="Library" then return {zone} end
    return {}
end
Player={White={getHandCount=function()return 1 end}}
broadcastToColor=function()end
local frameQueue={}
Wait={
    frames=function(callback,n)
        assert(n==8,"Unexpected deck lock release delay")
        frameQueue[#frameQueue+1]=callback
    end,
    condition=function(callback,ready)
        assert(ready())
        callback()
    end
}
local file=assert(io.open("src/lotus/sections/02_draw-random.lua","rb"))
local source=file:read("*a")
file:close()
local dr=assert(load(source.."\nreturn DrawRandom","@DrawRandom"))()
local x,z=deck.x,deck.z
dr.draw("White",nil,deck)
assert(deck.drawn==1 and deck.x==x and deck.z==z)
assert(deck.locked and #frameQueue==1)
frameQueue[1]()
assert(not deck.locked,"Deck lock not released after draw")
deck.locked=true
dr.draw("White",nil,deck)
assert(deck.drawn==2 and deck.locked, "Originally locked deck was changed")
assert(#frameQueue==1,"Originally locked deck must not schedule unlock")
print("Draw Random extraction cannot nudge the deck: OK")
