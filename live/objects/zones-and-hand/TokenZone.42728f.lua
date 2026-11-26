-- Token deck spreader. A deck dropped onto the token marker is rotated and spread after it settles.

-- TOKEN -> HAND DECK SPREADER
-- Put this script directly on the token object.

local SPREAD_DISTANCE = 0.55

-- Change this between 90 and -90 if it spreads
-- in the wrong vertical direction.
local SPREAD_ROTATION = -90

local busy = false


-- Wait for a deck to settle before spreading it; ignore unrelated collisions while busy.
function onCollisionEnter(info)
    if busy then return end

    local obj = info.collision_object

    if obj == nil then return end
    if obj.type ~= "Deck" then return end

    busy = true

    -- Wait for the deck to settle before moving it.
    Wait.frames(function()

        if obj == nil or obj.isDestroyed() then
            busy = false
            return
        end

        spreadDeck(obj)

    end, 2)
end


-- Orient the deck to the marker and spread its cards in the intended direction.
function spreadDeck(deck)

    -- Match the token's orientation, but turn the deck
    -- 90 degrees because deck.spread() spreads left/right.
    local tokenRotation = self.getRotation()

    deck.setRotation({
        0,
        tokenRotation.y + SPREAD_ROTATION,
        0
    })

    -- Wait for the rotation to apply before spreading.
    Wait.frames(function()

        if deck ~= nil and not deck.isDestroyed() then
            deck.spread(SPREAD_DISTANCE)
        end

        -- Keep the spread operation from triggering again on the individual cards.
        Wait.time(function()
            busy = false
        end, 1)

    end, 1)
end