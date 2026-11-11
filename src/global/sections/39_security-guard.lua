--------------------------------------------------------------------------------
-- BLACK LOTUS SECURITY GUARD (REPORT-ONLY)
-- Looks for unexpected object Lua and worm-like script operations. Never edits,
-- locks, destroys, or reloads an object. It cannot stop onLoad code that ran
-- before onObjectSpawn, or protect players from a malicious TTS host.
--------------------------------------------------------------------------------
local blSecurityTrusted = {}
for guid in ([[02e062,031b64,06926c,0af44c,0b7776,0beb07,0c0a0a,0c0c5e,0e2b03,0f6598,16aed3,185063,1a649e,1c657c,21ac95,222541,23e485,24fc8d,25f80a,29d31b,29f427,2b5ee7,2db63a,2e1ed6,2e2fe6,2f714c,33b0a3,37e533,395037,3a8a34,3b2d18,3d7324,3da318,40b95f,42728f,448880,45331a,4563bf,47dc63,484c38,4bfa09,4db5e0,4e8c7b,5006a4,50cc93,5137aa,51562f,540e21,56a44e,57b8f3,5b0cc8,5cb175,5ce447,6a0c37,6b6e1f,6f8227,70339e,7071ce,716ee6,7a0067,7cf430,7d5edc,7de799,809133,82bf98,8963ec,8d172a,906d4b,908f60,91aaed,9243e9,93894a,94d36f,95eb63,96c4e8,988e5e,9c9b5d,9d380e,9d9dda,9df6a3,9ea771,9f351a,a2ce10,a42baa,a5fa7f,ad044a,ad84fe,ade398,ae12d3,af4074,b364b4,b3ec0b,b40ce7,b4f29e,b748df,b7ccfb,b8b8df,b93b40,ba4431,baffa9,bfcf4a,c2df33,c369d7,c5ea55,cd457d,cd83de,ce8ea5,d075c6,d1ae7b,d29299,d3959e,d5907a,d9bd81,d9fcbc,dc9c6d,dcbe3a,de4346,def0af,df09d5,e0d9cc,e2c813,e40450,e6554f,e76686,eb9703,ee33ec,f29c09,f43e61,f62d00,fb138f,fb6538,fb701a,fbe823,fcb7b5]]):gmatch("%x%x%x%x%x%x") do
    blSecurityTrusted[guid] = true
end
local blSecurityReported = {}
local blSecurityBaselines = {}
local blSecurityAlertCount = 0
local blSecurityScanning = false
local blSecurityLastScan = -1000

local blSecurityPatterns = {
    { "setLuaScript%s*%(", "setLuaScript" },
    { "script_code%s*=", "script_code assignment" },
    { "spawnObjectJSON%s*%(", "spawnObjectJSON" },
    { "spawnObjectData%s*%(", "spawnObjectData" },
    { "loadstring%s*%(", "loadstring" },
    { "WebRequest%s*[%.:]", "WebRequest" },
}

local function blSecurityFingerprint(code)
    code = code:gsub("\r\n", "\n")
    local a, b = 1, 0
    for i = 1, #code do
        a = (a + code:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return tostring(#code) .. ":" .. tostring(a) .. ":" .. tostring(b)
end

local function blSecurityReport(key, reason)
    if blSecurityReported[key] then return end
    blSecurityReported[key] = true
    blSecurityAlertCount = blSecurityAlertCount + 1
    local message = "[Black Lotus Guard] " .. tostring(key) .. ": " .. reason
    print(message)
    -- Limit public chat noise. No card names are disclosed (hands are private).
    if blSecurityAlertCount <= 8 then
        broadcastToAll(message, {1, 0.55, 0.2})
    elseif blSecurityAlertCount == 9 then
        broadcastToAll("[Black Lotus Guard] Further alerts are in the script log. Type 'security scan' for a new scan.", {1, 0.55, 0.2})
    end
end

local function blSecurityInspectLua(code, key, trusted)
    if type(code) ~= "string" or not code:find("%S") then return end
    local fingerprint = blSecurityFingerprint(code)
    if trusted then
        -- Detect changes after the first observation. This is NOT an official
        -- release hash: a table already infected on load may pass this check.
        if blSecurityBaselines[key] == nil then
            blSecurityBaselines[key] = fingerprint
        elseif blSecurityBaselines[key] ~= fingerprint then
            blSecurityReport(key .. ":" .. fingerprint, "Trusted object Lua changed since the first scan")
        end
        return
    end

    local indicators = {}
    for _, rule in ipairs(blSecurityPatterns) do
        if code:find(rule[1]) then
            table.insert(indicators, rule[2])
        end
    end
    local reason = "Unexpected executable Lua attached to an unrecognized object"
    if #indicators > 0 then
        reason = reason .. " (indicators: " .. table.concat(indicators, ", ") .. ")"
    end
    blSecurityReport(key .. ":" .. fingerprint, reason)
end

local function blSecurityInspectData(node, path, depth, budget)
    if type(node) ~= "table" or depth > 24 or budget.remaining <= 0 then return end
    budget.remaining = budget.remaining - 1
    local guid = type(node.GUID) == "string" and node.GUID or path
    if type(node.LuaScript) == "string" then
        blSecurityInspectLua(node.LuaScript, "nested/" .. tostring(guid), blSecurityTrusted[guid] == true)
    end
    -- TTS serializes cards inside decks/bags and alternate states here.
    for _, field in ipairs({"ContainedObjects", "States"}) do
        local children = node[field]
        if type(children) == "table" then
            for id, child in pairs(children) do
                blSecurityInspectData(child, path .. "/" .. field .. "/" .. tostring(id), depth + 1, budget)
            end
        end
    end
end

function BL_securityInspectObject(obj)
    if obj == nil then return end
    local guid = obj.getGUID()
    if type(guid) ~= "string" then return end
    local script = obj.getLuaScript()
    blSecurityInspectLua(script, "object/" .. guid, blSecurityTrusted[guid] == true)

    local isContainer = obj.tag == "Deck" or obj.tag == "Bag"
        or obj.tag == "Container" or obj.type == "Infinite"
    local okStates, states = pcall(function() return obj.getStates() end)
    if isContainer or (okStates and states ~= nil) then
        local okData, data = pcall(function() return obj.getData() end)
        if okData and type(data) == "table" then
            -- Root script was already checked; inspect only nested contents.
            for _, field in ipairs({"ContainedObjects", "States"}) do
                local children = data[field]
                if type(children) == "table" then
                    local budget = {remaining = 12000}
                    for id, child in pairs(children) do
                        blSecurityInspectData(child, guid .. "/" .. field .. "/" .. tostring(id), 1, budget)
                    end
                end
            end
        end
    end
end

local function blSecurityInspectSafe(obj)
    local ok, err = pcall(BL_securityInspectObject, obj)
    if not ok then
        print("[Black Lotus Guard] Scan error: " .. tostring(err))
    end
end

-- No existing Global handlers use these events in the 4p/6p release.
function onObjectSpawn(obj)
    blSecurityInspectSafe(obj)
end

function onObjectStateChange(obj, oldStateGuid)
    blSecurityInspectSafe(obj)
end

-- Called once after Global.onLoad, or manually with chat: security scan.
-- Batch work to avoid freezing a large EDH table with many objects/decks.
function BL_securityScanAll(requesterColor)
    if blSecurityScanning then
        if requesterColor then broadcastToColor("[Black Lotus Guard] Scan already running.", requesterColor) end
        return
    end
    local now = os.time()
    if now - blSecurityLastScan < 10 then
        if requesterColor then broadcastToColor("[Black Lotus Guard] Scan cooldown: try again shortly.", requesterColor) end
        return
    end
    blSecurityLastScan = now
    blSecurityScanning = true
    local objects = getAllObjects()
    local i, scanned, before = 1, 0, blSecurityAlertCount
    local function batch()
        for _ = 1, 12 do
            if i > #objects then
                blSecurityScanning = false
                local newAlerts = blSecurityAlertCount - before
                local message = "[Black Lotus Guard] Scanned " .. scanned
                    .. " objects; " .. newAlerts .. " new alert(s). "
                    .. "This is a heuristic check, not proof of a safe host."
                if requesterColor then
                    broadcastToColor(message, requesterColor, {0.85, 0.85, 0.85})
                elseif newAlerts > 0 then
                    broadcastToAll(message, {1, 0.55, 0.2})
                else
                    print(message)
                end
                return
            end
            blSecurityInspectSafe(objects[i])
            scanned = scanned + 1
            i = i + 1
        end
        Wait.frames(batch, 1)
    end
    batch()
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
