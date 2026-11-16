-- Regression tests for transient TTS objects during deck merges/draws.
-- Run from repository root: lua5.2 tests/draw_random_lifecycle_test.lua

local messages = {}
function log(message) messages[#messages + 1] = message end
function broadcastToColor(message, color) messages[#messages + 1] = message end
Player = { White = { getHandCount = function() return 1 end } }

local zones = {}
function getObjectsWithTag(tag)
    local result = {}
    for _, zone in ipairs(zones) do
        if zone.tags[tag] then result[#result + 1] = zone end
    end
    return result
end
Wait = {
    frames = function() end,
    time = function() end,
    condition = function(callback, ready)
        if ready() then callback() end
    end
}

local function newZone(guid, tags)
    local z = {
        type = "Scripting", guid = guid, tags = tags,
        objects = {}, destroyed = false, fail = false
    }
    z.isDestroyed = function() return z.destroyed end
    z.getGUID = function() return z.guid end
    z.hasTag = function(t) return z.tags[t] == true end
    z.getObjects = function(ignoreTags)
        assert(ignoreTags == true, "zones must include untagged decks")
        if z.fail then error("transient zone reference") end
        return z.objects
    end
    return z
end

local function newDeck(guid)
    local d = { type = "Deck", guid = guid, destroyed = false, menus = 0 }
    d.isDestroyed = function() return d.destroyed end
    d.getGUID = function() return d.guid end
    d.addContextMenuItem = function(label, callback)
        assert(label == "Draw Random")
        d.menus = d.menus + 1
        d.menu = callback
    end
    d.getObjects = function() return {{guid = "inside-card"}} end
    d.takeObject = function(p)
        assert(p.guid == "inside-card" and p.index == nil)
        local card = {type = "Card", spawning = false}
        card.isDestroyed = function() return false end
        card.deal = function(count, color, hand)
            assert(count == 1 and color == "White" and hand == 1)
            d.dealt = (d.dealt or 0) + 1
        end
        p.callback_function(card)
    end
    return d
end

-- dofile() cannot return the private local table. Load the same module
-- with a one-line test-only export; production script stays unchanged.
local f = assert(io.open("src/lotus/sections/02_draw-random.lua", "rb"))
local contents = f:read("*a")
f:close()
local script = assert(load(contents .. "\nreturn DrawRandom", "@02_draw-random.lua"))
local dr = script()

local library = newZone("zlib", { Library = true })
local grave = newZone("zgrave", { Graveyard = true })
zones = { library, grave }

-- A transient Deck appearing for only one scan must never get a menu.
local fleeting = newDeck("fleeting")
library.objects = {fleeting}
dr.onEnterZone(library, fleeting) -- event cannot bypass the buffer
assert(fleeting.menus == 0)
dr.scan()
assert(fleeting.menus == 0)
library.objects = {}
dr.scan()
assert(fleeting.menus == 0 and dr.candidates.fleeting == nil)

-- Reentry starts a new streak; duplicate zones within one scan only count once.
local stable = newDeck("stable")
library.objects = {stable}
grave.objects = {stable}
dr.scan()
assert(stable.menus == 0 and dr.candidates.stable.count == 1)
dr.scan()
assert(stable.menus == 1 and dr.registered.stable)
dr.scan()
assert(stable.menus == 1, "no duplicate context menus on repeat scan")

-- The menu is retained but cannot draw outside supported zones.
library.objects, grave.objects = {}, {}
assert(not dr.isEligible(stable))
stable.menu("White", nil, stable)
assert(stable.dealt == nil and #messages >= 1)
grave.objects = {stable}
assert(dr.isEligible(stable))
stable.menu("White", nil, stable)
assert(stable.dealt == 1)

-- Invalid references from a zone snapshot can throw even on isDestroyed
-- or getGUID; all should be ignored without interrupting other decks.
local nullRef = {type = "Deck"}
nullRef.isDestroyed = function() error("Object reference not set") end
nullRef.getGUID = function() error("invalid native reference") end
local badGuid = {type = "Deck", isDestroyed = function() return false end}
badGuid.getGUID = function() error("destroyed just after check") end
local newer = newDeck("newer")
library.objects = {nullRef, badGuid, newer}
grave.objects = {}
dr.scan()
assert(newer.menus == 0)
dr.scan()
assert(newer.menus == 1, "valid deck must survive invalid neighbors")

-- A zone failing to enumerate should not abort the scan of other zones.
library.fail = true
grave.objects = {newDeck("grave-stable")}
local valid = grave.objects[1]
dr.scan()
dr.scan()
assert(valid.menus == 1, "unaffected zones still register decks")
library.fail = false

-- Destroy notification permits replacing an old deck GUID without duplicates.
stable.destroyed = true
dr.onDestroy(stable)
assert(dr.registered.stable == nil)
local replacement = newDeck("stable")
library.objects = {replacement}
grave.objects = {}
dr.scan()
assert(replacement.menus == 0)
dr.scan()
assert(replacement.menus == 1)

-- Delayed callbacks must not try to use destroyed Cards.
replacement.takeObject = function(params)
    local deadCard = {type = "Card"}
    deadCard.isDestroyed = function() return true end
    params.callback_function(deadCard)
end
replacement.menu("White", nil, replacement)
assert(replacement.menus == 1)

-- A destroyed Deck in the same frame is not eligible.
replacement.destroyed = true
assert(not dr.isEligible(replacement))
assert(not dr.registerDeck(replacement))
print("Draw Random transient-deck lifecycle tests passed.")
