-- =============================================================
-- MODULE 2/4: PLAYMATS
--
-- Chat:  playmat https://example.com/picture.png
--        playmat none
--

-- =============================================================

local Playmats = {
    CONFIG = {
        scaleX = 2.30,
        scaleY = 0.01,
        scaleZ = 2.70,
        forwardOffset = 24.50,
        sideOffset = 4.5,
        height = 0.96,
        rotationY = 0,
        locked = true,
        interactable = false,
        meshURL = "https://steamusercontent-a.akamaihd.net/ugc/1661229755220411391/27AA7C44FB7D2F2E20F96618E6CD9671C5EE8341/"
    },
    ART_TAG = "MTG_Portable_ArtPlaymat",
    guids = {},            -- player color -> spawned playmat GUID
    generations = {},      -- cancel overlapping replacement requests
    PLAYER_COLORS = {"White", "Red", "Yellow", "Blue"}
}


-- Battlefield scripting zones, rather than player hands, define the exact
-- position, rotation and footprint of each artwork playmat.
function Playmats.getBattlefieldZone(color)
    local matches = {}
    for _, zone in ipairs(getObjectsWithTag("Battlefield") or {}) do
        if zone.type == "Scripting" and zone.hasTag(color) then
            matches[#matches + 1] = zone
        end
    end
    -- Ambiguous zones must never cause a mat to land on the wrong board.
    if #matches ~= 1 then return nil end
    return matches[1]
end

function Playmats.fitToBattlefield(mat, color)
    local zone = Playmats.getBattlefieldZone(color)
    if zone == nil or mat == nil or mat.isDestroyed() then return false end

    local zoneScale = zone.getScale()
    local bounds = mat.getBoundsNormalized()
    if bounds == nil or bounds.size == nil
        or bounds.size.x <= 0.001 or bounds.size.z <= 0.001 then
        return false
    end

    local current = mat.getScale()
    mat.setScale({
        x = current.x * zoneScale.x / bounds.size.x,
        y = current.y,
        z = current.z * zoneScale.z / bounds.size.z
    })

    -- Scripting zones are volumes: use their x/z center, not their y center.
    -- Keep the artwork on the tabletop, below cards and counters.
    local position = zone.getPosition()
    mat.setPosition({position.x, Playmats.CONFIG.height, position.z})
    local rot = zone.getRotation()
    mat.setRotation({0, rot.y + Playmats.CONFIG.rotationY, 0})
    mat.setLock(Playmats.CONFIG.locked)
    mat.interactable = Playmats.CONFIG.interactable
    return true
end

function Playmats.alignExisting()
    for _, color in ipairs(Playmats.PLAYER_COLORS) do
        local mat = Playmats.getOwnedMat(color)
        if mat ~= nil then
            pcall(function() Playmats.fitToBattlefield(mat, color) end)
        end
    end
end


function Playmats.load(savedData)
    Playmats.guids = {}
    Playmats.generations = {}

    if type(savedData) ~= "string" or savedData == "" then
        return
    end

    local ok, decoded = pcall(JSON.decode, savedData)
    if not ok or type(decoded) ~= "table" then
        return
    end

    local savedGuids = decoded.playmats or decoded
    if type(savedGuids) ~= "table" then
        return
    end

    for color, guid in pairs(savedGuids) do
        if type(color) == "string" and type(guid) == "string" then
            Playmats.guids[color] = guid
        end
    end
end

function Playmats.save()
    return JSON.encode({
        version = HELPER_VERSION,
        playmats = Playmats.guids,
        settings = Settings and Settings.export() or nil,
        commanderFirstShown = Preview.commanderFirstShown,
        revealTopEnabled = RevealTop and RevealTop.enabled or {}
    })
end


function Playmats.persist()
    self.script_state = Playmats.save()
end

function Playmats.getOwnedMat(color)
    local guid = Playmats.guids[color]
    if type(guid) ~= "string" then return nil end
    local obj = getObjectFromGUID(guid)
    if obj == nil then return nil end

    if obj.hasTag(Playmats.ART_TAG) or obj.getName() == "Art Playmat" then
        return obj
    end
    -- A stale GUID should never delete a non-playmat object.
    return nil
end

function Playmats.remove(color)
    -- Invalidate any spawn callback from an earlier playmat command.
    Playmats.generations[color] = (Playmats.generations[color] or 0) + 1

    local existing = Playmats.getOwnedMat(color)
    Playmats.guids[color] = nil
    Playmats.persist()

    if existing ~= nil then
        existing.destruct()
    end
end

function Playmats.makeJSON(imageURL)
    local c = Playmats.CONFIG
    -- JSON.encode escapes unusual characters in URLs correctly.
    return JSON.encode({
        Name = "Custom_Model",
        Transform = {
            posX = 0, posY = 0, posZ = 0,
            rotX = 0, rotY = 0, rotZ = 0,
            scaleX = c.scaleX,
            scaleY = c.scaleY,
            scaleZ = c.scaleZ
        },
        Nickname = "Art Playmat",
        ColorDiffuse = {r = 1, g = 1, b = 1},
        Locked = c.locked,
        CustomMesh = {
            MeshURL = c.meshURL,
            DiffuseURL = imageURL,
            MaterialIndex = 3,
            TypeIndex = 4,
            CustomShader = {
                SpecularColor = {r = 1, g = 1, b = 1},
                SpecularIntensity = 0,
                SpecularSharpness = 2,
                FresnelStrength = 0
            }
        }
    })
end

function Playmats.create(color, imageURL)
    local player = Player[color]
    if player == nil then return end

    local zone = Playmats.getBattlefieldZone(color)
    if zone == nil then
        player.broadcast("[FF0000]Playmat: exactly one Battlefield zone tagged "
            .. color .. " is required.")
        return
    end

    local c = Playmats.CONFIG
    local center = zone.getPosition()
    local matPos = {center.x, c.height, center.z}
    local zoneRot = zone.getRotation()
    local matRot = {0, zoneRot.y + c.rotationY, 0}
    local json = Playmats.makeJSON(imageURL)

    -- Don't delete the current mat until a replacement was spawned.
    Playmats.generations[color] = (Playmats.generations[color] or 0) + 1
    local generation = Playmats.generations[color]

    local okSpawn, err = pcall(function()
        spawnObjectJSON({
            json = json,
            position = matPos,
            rotation = matRot,
            callback_function = function(obj)
                if obj == nil then return end
                if Playmats.generations[color] ~= generation then
                    obj.destruct() -- superseded by a newer command
                    return
                end

                local old = Playmats.getOwnedMat(color)
                -- Make the new mat safe to delete / find by this module.
                obj.setName("Art Playmat")
                obj.addTag(Playmats.ART_TAG)
                obj.interactable = c.interactable
                obj.setLock(c.locked)

                -- Wait for TTS to instantiate the custom mesh before measuring
                -- its actual world-size. Bounds, not scale, determine the fit.
                Wait.frames(function()
                    if obj == nil or obj.isDestroyed()
                        or Playmats.generations[color] ~= generation then return end
                    local ok, fitted = pcall(function()
                        return Playmats.fitToBattlefield(obj, color)
                    end)
                    if not ok or not fitted then
                        player.broadcast("[FF0000]Playmat: unable to measure artwork mesh.")
                    end
                end, 15)

                -- Save the new GUID BEFORE destroying the old mat.
                Playmats.guids[color] = obj.getGUID()
                Playmats.persist()
                if old ~= nil and old ~= obj then
                    old.destruct()
                end
            end
        })
    end)

    if not okSpawn then
        player.broadcast("[FF0000]Playmat spawn failed: " .. tostring(err))
        return
    end
    player.broadcast(
        "[FFFFFF]Setting playmat image:\n[3366CC]" .. imageURL ..
        "\n[999999]Type [i]playmat none[/i] to remove it."
    )
end

function Playmats.onChat(message, player)
    if type(message) ~= "string" or player == nil then return end
    local imageURL = message:match("^[Pp]laymat%s+(.+)$")
    if imageURL == nil then return end

    -- Trim only leading/trailing whitespace; no recursive non-greedy Lua pattern.
    imageURL = imageURL:gsub("^%s+", ""):gsub("%s+$", "")
    local color = player.color

    if imageURL:lower() == "none" then
        Playmats.remove(color)
        player.broadcast("[999999]Art playmat removed.")
    elseif imageURL ~= "" then
        Playmats.create(color, imageURL)
    end

    -- Hide commands from ordinary game chat.
    return false
end

