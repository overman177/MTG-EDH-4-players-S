-- The One Ring: floating ornament for The Ring emblem/card.
-- The physical Ring card has GUID d9fcbc in the 4- and 6-player tables.
-- Preserve original model tilt; follow the card without collisions or chat spam.
local CARD_GUID = "d9fcbc"
local RING_HEIGHT = 0.90
local FLOAT_HEIGHT = 0.15
local FLOAT_SPEED = 0.025
local ROTATION_SPEED = 0.25

local phase, spinAngle = 0, 0
local baseRotation, initialCardYaw = nil, nil

function onLoad()
    self.setLock(true)
    self.interactable = false
    self.tooltip = false

    baseRotation = self.getRotation()
    local card = getObjectFromGUID(CARD_GUID)
    if card then
        initialCardYaw = card.getRotation().y
    end
end

function onUpdate()
    local card = getObjectFromGUID(CARD_GUID)
    if not card then return end

    local position = card.getPosition()
    local rotation = card.getRotation()
    if not baseRotation then baseRotation = self.getRotation() end
    if not initialCardYaw then initialCardYaw = rotation.y end

    phase = phase + FLOAT_SPEED
    local bob = ((math.sin(phase) + 1) / 2) * FLOAT_HEIGHT
    spinAngle = (spinAngle + ROTATION_SPEED) % 360

    self.setPosition({
        x = position.x,
        y = position.y + RING_HEIGHT + bob,
        z = position.z
    })
    self.setRotation({
        x = baseRotation.x,
        y = (baseRotation.y + rotation.y - initialCardYaw + spinAngle) % 360,
        z = baseRotation.z
    })
end
