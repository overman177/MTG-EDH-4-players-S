-- Lua 5.2: two-key combat targeting, short Undo and five-second Clear.
local holdSeconds={White=5,Blue=5}
Settings={combatEnabledByColor={White=true,Blue=true,Red=true,Yellow=true},
    getUndoHold=function(color) return holdSeconds[color] or 5 end}
local cards, updates, now, jobs = {}, 0, 0, {}
Wait = {time=function(fn,delay)
    assert(delay>=1 and delay<=10, "undo hold must use a valid configured duration")
    jobs[#jobs+1]={fn=fn,at=now+delay}
end}
local function advance(dt)
    now=now+dt
    local run={}
    for _,job in ipairs(jobs) do if job.at<=now then run[#run+1]=job end end
    for _,job in ipairs(run) do
        for i,stored in ipairs(jobs) do
            if stored==job then table.remove(jobs,i);break end
        end
        job.fn()
    end
end
local function card(guid)
    local o={tag="Card",guid=guid}
    o.getGUID=function() return guid end
    o.isDestroyed=function() return false end
    cards[guid]=o
    return o
end
function getObjectFromGUID(guid) return cards[guid] end
function printToColor() end
dofile("src/lotus/sections/06_combat-targeting.lua")
Combat.updated=function() updates=updates+1 end
local atk=card("a11111");local atk2=card("b22222")
local d1=card("d11111");local d2=card("d22222");local d3=card("d33333");local d4=card("d44444")
local function draw(color,def,attacker)
    Combat.hotkey(color,def,nil,false)
    Combat.hotkey(color,attacker,nil,true)
end
local function count(attacker) return Combat.countDefenders(Combat.links[attacker.guid]) end
local function down(color) Combat.undoHotkey(color,nil,nil,false) end
local function up(color) Combat.undoHotkey(color,nil,nil,true) end

draw("White",d1,atk);draw("White",d2,atk);draw("White",d3,atk)
draw("Blue",d4,atk);draw("Blue",d2,atk2)
assert(count(atk)==4 and count(atk2)==1,"multiple defenders and owners")
draw("White",d1,atk);draw("White",atk,atk)
assert(count(atk)==4,"drawing cannot remove links")

-- Tap: undo is deferred until release, and its timer must become stale.
down("White")
assert(count(atk)==4,"keydown alone should not undo")
advance(0.2)
up("White")
assert(count(atk)==3 and Combat.links[atk.guid].defenders[d3.guid]==nil,
    "short press undoes last surviving White arrow")
advance(10)
assert(count(atk)==3 and count(atk2)==1,"expired short-press timer is harmless")

-- Hold: no undo while held less than 5s; then clear only the owner's arrows.
draw("White",d3,atk)
down("White")
advance(4.9)
assert(count(atk)==4,"hold under threshold changes nothing")
down("White") -- repeat key-down from key-repeat must not reset timer
advance(0.1)
assert(count(atk)==1 and count(atk2)==1,"five-second hold clears White only")
assert(Combat.links[atk.guid].defenders[d4.guid]=="Blue","Blue owns surviving arrow")
assert(Combat.undoHeld.White and Combat.undoHeld.White.cleared,"hold remains marked until release")
draw("White",d1,atk)
down("White") -- key-repeat after clear must not start a second timer
up("White")
assert(count(atk)==2,"releasing after long hold cannot undo a new arrow")
assert(Combat.undo("White") and count(atk)==1,"future short/normal undo still works")

-- Two players holding different keys concurrently must not interfere.
draw("White",d1,atk)
draw("Blue",d1,atk2)
down("White");down("Blue")
advance(1)
up("White")
assert(count(atk)==1 and count(atk2)==2,"White short undo leaves Blue alone")
advance(4)
assert(count(atk)==0 and count(atk2)==0,"Blue long hold clears only Blue")
up("Blue")
assert(not next(Combat.links),"no extra action on Blue long-hold release")

-- Manual clear or a disabled toggle cancels a pending hold and its timer.
draw("White",d1,atk);draw("White",d2,atk)
down("White")
Combat.clear("White")
draw("White",d3,atk)
advance(6)
up("White")
assert(count(atk)==1,"manual clear cancels held timer and keyup")
down("White")
Settings.combatEnabledByColor.White=false
Combat.clear("White") -- Settings.toggleGeneral calls this when disabling
Settings.combatEnabledByColor.White=true
draw("White",d1,atk)
advance(5)
up("White")
assert(count(atk)==1,"disabling cancels hold even after re-enable")
assert(updates>0)
-- Separate threshold for each seat; it is sampled once at key-down.
holdSeconds.White=2
holdSeconds.Blue=8
draw("White",d2,atk)
draw("Blue",d3,atk2)
down("White");down("Blue")
advance(2)
assert(count(atk)==0 and count(atk2)==1,"White clears after 2s, Blue stays")
assert(count(atk2)>=1,"Blue's 8s timer has not fired after 2s")
advance(5.9)
assert(count(atk2)>=1,"Blue arrows remain before 8s")
advance(0.1)
assert(count(atk2)==0,"Blue clears at its own configured 8s")
up("White");up("Blue")
assert(not next(Combat.links),"long hold respects each player and timer")
print("Combat two-hotkey configurable hold/ownership tests passed.")
