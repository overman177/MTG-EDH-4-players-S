--------------------------------------------------------------------------------
-- BLACK LOTUS SECURITY GUARD — lightweight, report-only heuristic.
-- Never changes, locks, or removes objects. Not a pre-execution sandbox.
-- Trusted GUIDs belong to this table build (NOT cryptographic verification).
--------------------------------------------------------------------------------
local blSecurityTrusted = {}
for guid in ([[02e062,031b64,06926c,0af44c,0b7776,0beb07,0c0a0a,0c0c5e,0e2b03,0f6598,16aed3,185063,1a649e,1c657c,21ac95,222541,23e485,24fc8d,25f80a,29d31b,29f427,2b5ee7,2db63a,2e1ed6,2e2fe6,2f714c,33b0a3,37e533,395037,3a8a34,3b2d18,3d7324,3da318,40b95f,42728f,448880,45331a,4563bf,47dc63,484c38,4bfa09,4db5e0,4e8c7b,5006a4,50cc93,5137aa,51562f,540e21,56a44e,57b8f3,5b0cc8,5cb175,5ce447,6a0c37,6b6e1f,6f8227,70339e,7071ce,716ee6,7a0067,7cf430,7d5edc,7de799,809133,82bf98,8963ec,8d172a,906d4b,908f60,91aaed,9243e9,93894a,94d36f,95eb63,96c4e8,988e5e,9c9b5d,9d380e,9d9dda,9df6a3,9ea771,9f351a,a2ce10,a42baa,a5fa7f,ad044a,ad84fe,ade398,ae12d3,af4074,b364b4,b3ec0b,b40ce7,b4f29e,b748df,b7ccfb,b8b8df,b93b40,ba4431,baffa9,bfcf4a,c2df33,c369d7,c5ea55,cd457d,cd83de,ce8ea5,d075c6,d1ae7b,d29299,d3959e,d5907a,d9bd81,d9fcbc,dc9c6d,dcbe3a,de4346,def0af,df09d5,e0d9cc,e2c813,e40450,e6554f,e76686,eb9703,ee33ec,f29c09,f43e61,f62d00,fb138f,fb6538,fb701a,fbe823,fcb7b5]]):gmatch("%x%x%x%x%x%x") do
    blSecurityTrusted[guid] = true
end

local blSecurityReported = {}
local blSecurityAlerts = 0
local blSecurityScanning = false
local blSecurityLastScan = -1000
local blSecurityLiveNotices = 0

-- Scanning all unknown Lua as "malicious" produced dozens of false alarms.
-- Flag only script-writing primitives or remote-code execution indicators.
-- Legitimate add-ons can use these too: results are WARNINGS, not verdicts.
local function blSecurityReason(lua)
    if type(lua) ~= "string" or lua == "" then return nil end
    if lua:find("setLuaScript%s*%(") or lua:find("script_code%s*=") then
        return "Possible Lua script replacement / propagation"
    end
    if lua:find("loadstring%s*%(") and lua:find("WebRequest%s*[%.:]") then
        return "Possible downloaded Lua execution"
    end
    if lua:find("LuaScript", 1, true)
        and (lua:find("spawnObjectJSON%s*%(") or lua:find("spawnObjectData%s*%(")) then
        return "Possible script-bearing JSON/data spawn"
    end
    return nil
end

local function blSecurityReport(key, reason)
    local fullKey = tostring(key) .. ":" .. reason
    if blSecurityReported[fullKey] then return end
    blSecurityReported[fullKey] = true
    blSecurityAlerts = blSecurityAlerts + 1
    print("[Black Lotus Guard] " .. tostring(key) .. ": " .. reason)

    -- At most two brief public notices outside manual/startup scans.
    if not blSecurityScanning and blSecurityLiveNotices < 2 then
        blSecurityLiveNotices = blSecurityLiveNotices + 1
        broadcastToAll("[Black Lotus Guard] Suspicious script capability found (" ..
            tostring(key) .. "). Host can run 'security scan' for details.",
            {1, 0.55, 0.2})
    end
end

local function blSecurityInspectLua(lua, key, guid)
    if blSecurityTrusted[guid] then return end
    local reason = blSecurityReason(lua)
    if reason ~= nil then blSecurityReport(key, reason) end
end

local function blSecurityInspectSaved(node, path, depth, budget)
    if type(node) ~= "table" or depth > 20 or budget.left <= 0 then return end
    budget.left = budget.left - 1
    local guid = type(node.GUID) == "string" and node.GUID or path
    blSecurityInspectLua(node.LuaScript, path, guid)
    for _, name in ipairs({"ContainedObjects", "States"}) do
        if type(node[name]) == "table" then
            for index, sub in pairs(node[name]) do
                blSecurityInspectSaved(sub, path .. "/" .. name .. "/" .. tostring(index),
                    depth + 1, budget)
            end
        end
    end
end

-- Some built-in table props are infinite token dispensers, counters, or
-- utility objects that look like containers but reject getObjects(). The TTS
-- engine logs red errors even if such calls are caught with pcall().
-- Keep getObjects() scanning for actual Deck/Bag containers; exempt ONLY the
-- known affected table props. Their own Lua is still scanned normally.
local blSecurityUninspectableGUIDs = {
    ["b653d2"] = true, -- Turn Skipper Puck
    ["b8b9ed"] = true, -- d6
    ["b9f545"] = true, -- Menace
    ["bc8aef"] = true, -- Rhystic Block Bag
    ["beb998"] = true, -- +X/+Y Counter
    ["c1840d"] = true, -- Vigilance
    ["c36338"] = true, -- First Strike
    ["c3ca32"] = true, -- Double Strike
    ["cbcea4"] = true, -- d4
    ["feadfa"] = true, -- Haste
    ["60df73"] = true, -- d6
    ["de6012"] = true, -- Renowned
}
local blSecurityUninspectableNames = {
    ["Turn Skipper Puck"] = true,
    ["d6"] = true, ["d4"] = true,
    ["Rhystic Block Bag"] = true, ["+X/+Y Counter"] = true,
    -- Keyword-token dispensers keep their names if their GUID changes.
    ["Frozen"] = true, ["Deathtouch"] = true, ["Defender"] = true,
    ["Double Strike"] = true, ["First Strike"] = true, ["Flying"] = true,
    ["Haste"] = true, ["Hexproof"] = true, ["Indestructible"] = true,
    ["Lifelink"] = true, ["Menace"] = true, ["Monstrous"] = true,
    ["Reach"] = true, ["Renowned"] = true, ["Trample"] = true,
    ["Vigilance"] = true, ["Stun"] = true, ["Exerted"] = true,
}

local function blSecurityIsContainer(obj)
    local t = obj.type
    if t ~= "Deck" and t ~= "Bag" and t ~= "Infinite"
        and t ~= "Custom_Model_Bag" and t ~= "Custom_Bag" then
        return false
    end

    local guid = obj.getGUID()
    -- Explicit GUID exceptions cover exceptional built-in props.
    if blSecurityUninspectableGUIDs[guid] then return false end

    -- Do not let a player evade deck scanning by naming a deck "Haste".
    -- Only exempt the listed table props, never regular card decks.
    if t ~= "Deck" and obj.getName ~= nil
        and blSecurityUninspectableNames[obj.getName()] then
        return false
    end

    return obj.getQuantity ~= nil and obj.getQuantity() > 0
end

-- Fast path: use TTS metadata; DO NOT serialize the object via getData().
-- getObjects() includes lua_script for contained cards; getStates() includes
-- lua_script for alternate states. No object is taken out of a deck.
function BL_securityInspectObject(obj, deep)
    if obj == nil then return end
    local guid = obj.getGUID()
    if type(guid) ~= "string" then return end
    if not blSecurityTrusted[guid] then
        blSecurityInspectLua(obj.getLuaScript(), "object/" .. guid, guid)
    end

    if blSecurityIsContainer(obj) then
        local contents = obj.getObjects()
        if type(contents) == "table" then
            for _, entry in ipairs(contents) do
                if type(entry) == "table" then
                    local childGUID = type(entry.guid) == "string" and entry.guid or guid
                    blSecurityInspectLua(entry.lua_script,
                        "contained/" .. guid .. "/" .. childGUID, childGUID)
                end
            end
        end
    end

    -- Most objects have no states. Avoid getStates() for them.
    if obj.getStateId and obj.getStateId() ~= -1 then
        local states = obj.getStates()
        if type(states) == "table" then
            for _, entry in pairs(states) do
                if type(entry) == "table" then
                    local stateGUID = type(entry.guid) == "string" and entry.guid or guid
                    blSecurityInspectLua(entry.lua_script,
                        "state/" .. guid .. "/" .. stateGUID, stateGUID)
                end
            end
        end
    end

    -- Expensive full serialization is ONLY available on explicit deep scans.
    -- It is needed for objects inside other objects inside bags/decks.
    if deep and (blSecurityIsContainer(obj) or
            (obj.getStateId and obj.getStateId() ~= -1)) then
        local data = obj.getData()
        if type(data) == "table" then
            local budget = {left = 4000}
            for _, field in ipairs({"ContainedObjects", "States"}) do
                if type(data[field]) == "table" then
                    for id, nested in pairs(data[field]) do
                        blSecurityInspectSaved(nested,
                            "deep/" .. guid .. "/" .. field .. "/" .. tostring(id),
                            1, budget)
                    end
                end
            end
        end
    end
end

local function blSecurityInspectSafe(obj, deep)
    local ok, err = pcall(BL_securityInspectObject, obj, deep)
    if not ok then
        -- Avoid chat/log floods for unavailable objects during reshuffles.
        if not blSecurityReported["error"] then
            blSecurityReported["error"] = true
            print("[Black Lotus Guard] Could not inspect one object: " .. tostring(err))
        end
    end
end

-- These events have no other Global handler in the current table build.
-- The spawn check is lightweight; no getData() or per-byte hashing occurs here.
function onObjectSpawn(obj)
    blSecurityInspectSafe(obj, false)
end

function onObjectStateChange(obj, oldStateGuid)
    blSecurityInspectSafe(obj, false)
end

-- On load: 2 objects every 3 frames, no chat if nothing is flagged.
-- Command: 'security scan' (lightweight), 'security deep scan' (explicitly
-- slower nested serialization). Running a scan never modifies table objects.
function BL_securityScanAll(requesterColor, deep)
    if blSecurityScanning then
        if requesterColor then
            broadcastToColor("[Black Lotus Guard] Scan already running.", requesterColor)
        end
        return
    end
    local now = os.time()
    if requesterColor and now - blSecurityLastScan < 10 then
        broadcastToColor("[Black Lotus Guard] Scan cooldown: try again shortly.",
            requesterColor)
        return
    end
    blSecurityLastScan = now
    blSecurityScanning = true
    local objects = getAllObjects()
    local index, scanned, before = 1, 0, blSecurityAlerts

    local function batch()
        local maxPerBatch = deep and 1 or 2
        for _ = 1, maxPerBatch do
            if index > #objects then break end
            blSecurityInspectSafe(objects[index], deep == true)
            scanned = scanned + 1
            index = index + 1
        end
        if index <= #objects then
            Wait.frames(batch, deep and 6 or 3)
            return
        end
        blSecurityScanning = false
        local found = blSecurityAlerts - before
        local label = "[Black Lotus Guard] " .. (deep and "Deep scan" or "Scan")
            .. ": " .. scanned .. " objects, " .. found ..
            " new suspicious script(s). This is not proof of host safety."
        if requesterColor then
            broadcastToColor(label, requesterColor, {0.8, 0.8, 0.8})
        elseif found > 0 then
            -- One startup summary; individual findings remain in scripting log.
            broadcastToAll("[Black Lotus Guard] Detected " .. found ..
                " suspicious script(s). See host scripting log.", {1, 0.55, 0.2})
        else
            print(label)
        end
    end
    Wait.frames(batch, 1)
end

-- Validate untrusted Scryfall importer JSON BEFORE calling spawnObjectJSON.
-- Accept ordinary Card/Deck payloads unchanged (including DFC states).
-- Reject script-bearing payloads rather than spawning partially broken cards.
function BL_securityValidateCardJSON(line)
    if type(line) ~= "string" or #line > 2097152 then
        return false, "Invalid or oversized card JSON"
    end
    local ok, data = pcall(JSON.decode, line)
    if not ok or type(data) ~= "table" then
        return false, "Invalid card JSON"
    end
    if data.Name ~= "Card" and data.Name ~= "Deck" then
        return false, "Unexpected imported object type"
    end
    local function walk(node, depth)
        if type(node) ~= "table" then return true end
        if depth > 32 then return false end
        for key, value in pairs(node) do
            if (key == "LuaScript" or key == "LuaScriptState" or key == "XmlUI")
                and type(value) == "string" and value ~= "" then
                return false
            end
            if type(value) == "table" and not walk(value, depth + 1) then
                return false
            end
        end
        return true
    end
    if not walk(data, 0) then
        return false, "Embedded script/UI data or excessive JSON nesting"
    end
    return true
end
