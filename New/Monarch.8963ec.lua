
-- ==========================================
-- MONARCH CROWN - CARD FOLLOW ANIMATION
-- ==========================================

-- GUID of The Monarch card
local CARD_GUID = "197ab6"

-- Animation settings
local CROWN_HEIGHT = 0.90
local FLOAT_HEIGHT = 0.15
local FLOAT_SPEED = 0.025
local ROTATION_SPEED = 0.25

-- Internal state
local phase = 0
local spinAngle = 0

local baseRotation = nil
local initialCardYaw = nil

function onLoad()
    -- Crown cannot be picked up separately
    self.setLock(true)
    self.interactable = false

    -- Preserve original crown orientation
    baseRotation = self.getRotation()

    local card = getObjectFromGUID(CARD_GUID)

    if card then
        initialCardYaw = card.getRotation().y
    else
        print("MONARCH: Card not found!")
    end
end

function onUpdate()
    local card = getObjectFromGUID(CARD_GUID)

    if not card then return end

    -- Read card position and rotation
    local cardPos = card.getPosition()
    local cardRot = card.getRotation()

    if not initialCardYaw then
        initialCardYaw = cardRot.y
    end

    -- Animation progression
    phase = phase + FLOAT_SPEED

    -- Floating animation (never below base height)
    local floatOffset =
        ((math.sin(phase) + 1) / 2)
        * FLOAT_HEIGHT

    -- Follow card position
    self.setPosition({
        x = cardPos.x,
        y = cardPos.y + CROWN_HEIGHT + floatOffset,
        z = cardPos.z
    })

    -- Crown rotation
    spinAngle =
        (spinAngle + ROTATION_SPEED) % 360

    -- Follow card yaw while rotating
    local cardYawOffset =
        cardRot.y - initialCardYaw

    self.setRotation({
        x = baseRotation.x,
        y = (
            baseRotation.y
            + cardYawOffset
            + spinAngle
        ) % 360,
        z = baseRotation.z
    })
end