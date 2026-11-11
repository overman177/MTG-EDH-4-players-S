-- MTG EDH Global — tag-aware compatibility patch
-- Compatible with Portable Helper: zone role/color tags are metadata, not
-- requirements for cards/decks. Never remove or automatically retag cards.

local function mtgSafeInit(name, callback)
    local ok, err = pcall(callback)
    if not ok then
        print("[MTG Global] Init " .. name .. " failed: " .. tostring(err))
    end
end

-- TTS event names are case-sensitive: onLoad, not onload.
function onLoad(saved)
    mtgSafeInit("settings", function() restoreSettings(saved) end)
    -- Display a non-blocking version notice after Global/Lotus UI initializes.
    mtgSafeInit("version banner", function()
        Wait.frames(mtgShowVersionBanner, 30)
    end)
    buildDataStructure()
    registerObjectGUIDs()
    mtgSafeInit("token zones", mtgRegisterTokenZones)
    mtgResolveTaggedZones()
    mtgSafeInit("buttons", buildTableButtons)
    mtgSafeInit("context menus", addZoneContextMenus)
    for _, guid in pairs({ "cb1610", "a7a029", "4c02f8", "a3e6a8", "9c553c", "eb479b", "3d4319", "540e21" }) do
        pcall(function()
            getObjectFromGUID(guid).interactable = false
        end)
    end
    Wait.frames(function()
        for _, guid in pairs({ "02e062", "de4346", "d936a8", "b93b40" }) do
            pcall(function()
                getObjectFromGUID(guid).interactable = false
            end)
        end
    end, 5)

    -- Flip hands on load; optional Encoder may not be available yet.
    Hands.disable_unused = false
    Wait.condition(function()
        local zones = Encoder.call("APIlistZones", {})
        for guid, zone in pairs(zones) do
            local target = getObjectFromGUID(guid)
            for _, obj in pairs(mtgZoneObjects(target)) do
                if obj.type == "Card" then
                    local rot = obj.getRotation()
                    rot[3] = 180
                    obj.setRotation(rot)
                end
            end
        end
    end, function()
        return Encoder ~= nil
    end)

    revealNrow = 12
    revealUp = 15.5
    revealUpS = 3.1
    revealRi = 1.5

    mtgSafeInit("land tracker", spawnLandTrackerText)
    mtgSafeInit("pregame", spawnKeepButtons)
    mtgSafeInit("fetchlands", initFetchlands)
    mtgSafeInit("sticker bag", initStickerBagMenu)

    -- Native zone events exclude tagged-incompatible cards. A low-frequency
    -- occupancy reconciliation restores those callbacks without tagging cards.
    Wait.frames(function()
        mtgSeedZoneSnapshots()
        mtgSafeInit("context menu refresh", addZoneContextMenus)
        Wait.time(mtgPollZoneSnapshots, 0.50, -1)
    end, 12)
    -- Non-destructive background scan after all table components have loaded.
    Wait.frames(BL_securityScanAll, 60)
end

-- Ensure data structure exists
function buildDataStructure()
	data = {
		White = { deck = nil, tokenZones = {} },
		Red = { deck = nil, tokenZones = {} },
		Yellow = { deck = nil, tokenZones = {} },
		Blue = { deck = nil, tokenZones = {} },
	}
end

-- Get pointers to in-game objects so we can script them
function registerObjectGUIDs()
	data["White"]["libraryZone"] = getObjectFromGUID("166036")
	data["Red"]["libraryZone"] = getObjectFromGUID("2365d0")
	data["Yellow"]["libraryZone"] = getObjectFromGUID("033b34")
	data["Blue"]["libraryZone"] = getObjectFromGUID("c04462")

	data["White"]["graveyard"] = getObjectFromGUID("68549d")
	data["Red"]["graveyard"] = getObjectFromGUID("07dd80")
	data["Yellow"]["graveyard"] = getObjectFromGUID("8b439a")
	data["Blue"]["graveyard"] = getObjectFromGUID("debc40")

	data["White"]["playmat"] = getObjectFromGUID("8b3401")
	data["Red"]["playmat"] = getObjectFromGUID("c20e3f")
	data["Yellow"]["playmat"] = getObjectFromGUID("129eaa")
	data["Blue"]["playmat"] = getObjectFromGUID("56cd9d")

	-- dedicated land scripting zone on each playmat (where lands are played)
	data["White"]["landZone"] = getObjectFromGUID("c24ef0")
	data["Red"]["landZone"] = getObjectFromGUID("772714")
	data["Yellow"]["landZone"] = getObjectFromGUID("00f87d")
	data["Blue"]["landZone"] = getObjectFromGUID("e63cad")

	-- command-zone scripting zones (one per player), used by the reset button to
	-- snapshot/restore commanders
	data["White"]["commandZone"] = getObjectFromGUID("8fc485")
	data["Red"]["commandZone"] = getObjectFromGUID("750cd5")
	data["Yellow"]["commandZone"] = getObjectFromGUID("c451cd")
	data["Blue"]["commandZone"] = getObjectFromGUID("879cc5")

	-- exile scripting zones (one per player); the reset button clears these too
	data["White"]["exileZone"] = getObjectFromGUID("d614cb")
	data["Red"]["exileZone"] = getObjectFromGUID("878032")
	data["Yellow"]["exileZone"] = getObjectFromGUID("ee5024")
	data["Blue"]["exileZone"] = getObjectFromGUID("bc8e3c")

	data["White"]["mulliganButton"] = getObjectFromGUID("3b07ae")
	data["Red"]["mulliganButton"] = getObjectFromGUID("c53ac6")
	data["Yellow"]["mulliganButton"] = getObjectFromGUID("47645d")
	data["Blue"]["mulliganButton"] = getObjectFromGUID("e0a3bc")

	data["White"]["untapButton"] = getObjectFromGUID("18fb5d")
	data["Red"]["untapButton"] = getObjectFromGUID("86e447")
	data["Yellow"]["untapButton"] = getObjectFromGUID("1f3e4a")
	data["Blue"]["untapButton"] = getObjectFromGUID("e2f7ae")

	data["White"]["drawButton"] = getObjectFromGUID("26775a")
	data["Red"]["drawButton"] = getObjectFromGUID("885f49")
	data["Yellow"]["drawButton"] = getObjectFromGUID("305c12")
	data["Blue"]["drawButton"] = getObjectFromGUID("b49d50")

	data["White"]["scryButton"] = getObjectFromGUID("614515")
	data["Red"]["scryButton"] = getObjectFromGUID("ffa67c")
	data["Yellow"]["scryButton"] = getObjectFromGUID("8a4c8b")
	data["Blue"]["scryButton"] = getObjectFromGUID("4e19c8")

	data["White"]["millButton"] = getObjectFromGUID("57914a")
	data["Red"]["millButton"] = getObjectFromGUID("da5d0d")
	data["Yellow"]["millButton"] = getObjectFromGUID("67b4a5")
	data["Blue"]["millButton"] = getObjectFromGUID("d06889")

	data["White"]["revealButton"] = getObjectFromGUID("d67eb4")
	data["Red"]["revealButton"] = getObjectFromGUID("0ad181")
	data["Yellow"]["revealButton"] = getObjectFromGUID("59ab68")
	data["Blue"]["revealButton"] = getObjectFromGUID("c489e1")

	-- life trackers identify their owner via their Description (a colour name)
	for _, guid in ipairs({ "23e485", "37e533", "395037", "448880" }) do
		local tracker = getObjectFromGUID(guid)
		if tracker ~= nil then
			local owner = tracker.getDescription()
			if data[owner] ~= nil then
				data[owner]["lifeTracker"] = tracker
			end
		end
	end

	-- Commander-damage trackers grouped by the player who *receives* the damage.
	-- A tracker's Description is its *source* colour (the dealer), not the
	-- recipient -- a player's own board holds one tracker per opponent, so the
	-- recipient is the colour missing from that cluster. The GUID lists below
	-- capture that recipient -> trackers mapping.
	data["White"]["commanderDamage"] = { "0f6598", "6b6e1f", "b748df" }
	data["Red"]["commanderDamage"] = { "4bfa09", "95eb63", "d5907a" }
	data["Yellow"]["commanderDamage"] = { "45331a", "484c38", "906d4b" }
	data["Blue"]["commanderDamage"] = { "8d172a", "bfcf4a", "f43e61" }
end

-- TokenZone spreaders are optional props. Never let a missing/misidentified
-- spreader interrupt Global.onLoad or any other required GUID registration.
function mtgRegisterTokenZones()
    local colors = { "White", "Red", "Yellow", "Blue" }
    for _, color in ipairs(colors) do
        local playerData = data and data[color]
        if type(playerData) == "table" then
            playerData.tokenZones = {}
        end
    end

    for _, guid in ipairs({ "031b64", "42728f", "51562f", "e6554f" }) do
        local ok, err = pcall(function()
            local obj = getObjectFromGUID(guid)
            if obj == nil then return end
            local owner, colorTags = nil, 0
            for _, color in ipairs(colors) do
                if obj.hasTag(color) then
                    owner, colorTags = color, colorTags + 1
                end
            end
            if colorTags ~= 1 then owner = nil end

            -- Untagged TokenZone props are associated with their nearest
            -- existing playmat. Only consider the four known player keys.
            if owner == nil then
                local pos = obj.getPosition()
                local nearest = math.huge
                for _, color in ipairs(colors) do
                    local playerData = data and data[color]
                    local mat = playerData and playerData.playmat
                    if mat ~= nil then
                        local matPos = mat.getPosition()
                        local dx, dz = pos.x - matPos.x, pos.z - matPos.z
                        local dist = dx * dx + dz * dz
                        if dist < nearest then
                            owner, nearest = color, dist
                        end
                    end
                end
            end
            local playerData = owner and data and data[owner]
            if type(playerData) ~= "table" then
                print("[MTG Global] TokenZone " .. guid .. " has no valid player; skipped.")
                return
            end
            if type(playerData.tokenZones) ~= "table" then
                playerData.tokenZones = {}
            end
            table.insert(playerData.tokenZones, obj)
        end)
        if not ok then
            print("[MTG Global] Optional TokenZone " .. guid
                .. " could not be registered: " .. tostring(err))
        end
    end
end


-------------------------------------------------------------------------------
-- TAG-AWARE ZONE LAYER
-- Roles: Library, Graveyard, Exile, Battlefield, CommanderZone
-- Colors: White, Red, Yellow, Blue. Both role and color must be on ONE zone.
-- Other tags (FetchPreview, MTG_Preview_InHand, controller tags, counters, etc.)
-- are left intact. The original fixed GUIDs are retained as fallbacks.
-------------------------------------------------------------------------------
local mtgZoneRoles = {
    libraryZone = "Library",
    graveyard = "Graveyard",
    exileZone = "Exile",
    playmat = "Battlefield",
    commandZone = "CommanderZone"
}
local mtgPlayerColors = { "White", "Red", "Yellow", "Blue" }

-- IMPORTANT: `true` means ignore tags, ONLY on Scripting Zones.
-- Deck/Bag getObjects() must retain the original container semantics.
function mtgZoneObjects(zone)
    if zone == nil then return {} end
    if zone.type == "Scripting" then
        return zone.getObjects(true) or {}
    end
    return zone.getObjects() or {}
end

function mtgResolveTaggedZones()
    for _, color in ipairs(mtgPlayerColors) do
        local playerData = data and data[color]
        if playerData ~= nil then
            for key, role in pairs(mtgZoneRoles) do
                local candidates = {}
                for _, zone in ipairs(getObjectsWithTag(role)) do
                    if zone.type == "Scripting" and zone.hasTag(color) then
                        table.insert(candidates, zone)
                    end
                end
                table.sort(candidates, function(a, b)
                    return a.getGUID() < b.getGUID()
                end)
                if #candidates > 0 then
                    local selected = candidates[1]
                    -- If the old GUID also has the correct tags, prefer it.
                    for _, zone in ipairs(candidates) do
                        if playerData[key] == zone then
                            selected = zone
                            break
                        end
                    end
                    playerData[key] = selected
                    if #candidates > 1 then
                        print("[MTG Global] Multiple " .. color .. "/" .. role
                            .. " zones; using " .. selected.getGUID())
                    end
                end
            end
        end
    end
end

local mtgZoneSnapshots = {}
local mtgZonesReady = false

local function mtgGetTrackedZones()
    local zones = {}
    if data == nil then return zones end
    for _, color in ipairs(mtgPlayerColors) do
        local p = data[color]
        if p ~= nil then
            for _, key in ipairs({ "libraryZone", "graveyard", "exileZone", "playmat", "landZone", "commandZone" }) do
                local zone = p[key]
                if zone ~= nil and zone.type == "Scripting" then
                    zones[zone.getGUID()] = zone
                end
            end
        end
    end
    return zones
end

local function mtgIsTrackedZone(zone)
    return zone ~= nil and mtgGetTrackedZones()[zone.getGUID()] ~= nil
end

local function mtgSnapshotObjects(zone)
    local found = {}
    for _, obj in ipairs(mtgZoneObjects(zone)) do
        if obj ~= nil and (obj.type == "Card" or obj.type == "Deck") then
            found[obj.getGUID()] = obj
        end
    end
    return found
end

function mtgSeedZoneSnapshots()
    mtgZoneSnapshots = {}
    for guid, zone in pairs(mtgGetTrackedZones()) do
        local present = {}
        for objectGUID, _ in pairs(mtgSnapshotObjects(zone)) do
            present[objectGUID] = true
        end
        mtgZoneSnapshots[guid] = present
    end
    mtgZonesReady = true
end

local function mtgDispatchZoneChange(zone, obj, entering)
    if zone == nil or obj == nil then return end
    if obj.type ~= "Card" and obj.type ~= "Deck" then return end
    if mtgIsTrackedZone(zone) then
        local guid, objGuid = zone.getGUID(), obj.getGUID()
        local occupied = mtgZoneSnapshots[guid]
        if occupied == nil then
            occupied = {}
            mtgZoneSnapshots[guid] = occupied
        end
        if entering then
            if occupied[objGuid] then return end
            occupied[objGuid] = true
        else
            if not occupied[objGuid] then return end
            occupied[objGuid] = nil
        end
    end
    if entering then
        mtgHandleZoneEnter(zone, obj)
    else
        mtgHandleZoneLeave(zone, obj)
    end
end

function mtgPollZoneSnapshots()
    if not mtgZonesReady then return end
    for guid, zone in pairs(mtgGetTrackedZones()) do
        local current = mtgSnapshotObjects(zone)
        local old = mtgZoneSnapshots[guid]
        if old == nil then
            old = {}
            mtgZoneSnapshots[guid] = old
        end
        -- Process exits first so transfers between tracked areas have a clean state.
        for objGuid, _ in pairs(old) do
            if current[objGuid] == nil then
                local obj = getObjectFromGUID(objGuid)
                if obj ~= nil then
                    mtgDispatchZoneChange(zone, obj, false)
                else
                    old[objGuid] = nil
                end
            end
        end
        for objGuid, obj in pairs(current) do
            if not old[objGuid] then
                mtgDispatchZoneChange(zone, obj, true)
            end
        end
    end
end

-- Optional manual refresh after editing zone tags (TTS console):
-- Global.call("mtgRefreshZoneTags")
function mtgRefreshZoneTags()
    mtgResolveTaggedZones()
    mtgSeedZoneSnapshots()
    addZoneContextMenus()
    print("[MTG Global] Zone tags rescanned.")
end

props = {
	White = {
		spawns = {
			main = { posX = "25.5", posZ = "-5", rotY = "180" },
			part = { posX = "22.5", posZ = "-5", rotY = "180" },
		},
	},

	Red = {
		spawns = {
			main = { posX = "-25.5", posZ = "-5", rotY = "180" },
			part = { posX = "-22.5", posZ = "-5", rotY = "180" },
		},
	},

	Yellow = {
		spawns = {
			main = { posX = "-25.5", posZ = "5", rotY = "0" },
			part = { posX = "-22.5", posZ = "5", rotY = "0" },
		},
	},

	Blue = {
		spawns = {
			main = { posX = "25.5", posZ = "5", rotY = "0" },
			part = { posX = "22.5", posZ = "5", rotY = "0" },
		},
	},
}

deckDirs = { White = -1, Red = 1, Yellow = -1, Blue = 1 }

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
function onPlayerDisconnect(player) -- flip cards in hand if disconnected
	for handInd = 1, player.getHandCount() do
		objs = player.getHandObjects(handInd)
		for _, obj in pairs(objs) do
			local rot = obj.getRotation()
			rot[3] = 180
			obj.setRotation(rot)
		end
	end
end

