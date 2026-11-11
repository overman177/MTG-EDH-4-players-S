-- Black Lotus Security Guard regression tests (Lua 5.2).
-- Run from repository root: lua5.2 tests/security_guard_test.lua

local public, private = {}, {}
broadcastToAll = function(message) public[#public + 1] = tostring(message) end
broadcastToColor = function(message, color) private[#private + 1] = {message, color} end
getAllObjects = function() return {} end
Wait = {frames = function(callback) callback() end}

local responses = {
    clean = {Name = "Card", Nickname = "Island", States = {["2"] = {Name = "Card"}}},
    cleanDeck = {Name = "Deck", ContainedObjects = {{Name = "Card"}, {Name = "Card"}}},
    scripted = {Name = "Card", LuaScript = "function onLoad() end"},
    stateScripted = {Name = "Card", States = {["2"] = {Name = "Card", LuaScript = "bad"}}},
    nestedScripted = {Name = "Deck", ContainedObjects = {{Name = "Card", LuaScript = "bad"}}},
    xml = {Name = "Card", XmlUI = "<Panel/>"},
    state = {Name = "Card", LuaScriptState = "nonempty"},
    badType = {Name = "Custom_Token"},
}
JSON = {decode = function(text)
    if responses[text] then return responses[text] end
    error("Invalid JSON")
end}

dofile("src/global/sections/39_security-guard.lua")

local function valid(payload, expected)
    local ok, reason = BL_securityValidateCardJSON(payload)
    assert(ok == expected, payload .. ": " .. tostring(reason))
end
valid("clean", true)
valid("cleanDeck", true)
valid("scripted", false)
valid("stateScripted", false)
valid("nestedScripted", false)
valid("xml", false)
valid("state", false)
valid("badType", false)
valid("not-json", false)
valid(string.rep("A", 2097153), false)

local code = "function onLoad() getObjectFromGUID('123456').setLuaScript('payload') end"
local untrusted = {
    tag = "Custom", type = "Custom",
    getGUID = function() return "abcdef" end,
    getLuaScript = function() return code end,
    getStates = function() return nil end,
}
onObjectSpawn(untrusted)
assert(#public == 1, "Unknown scripted object must be reported")
assert(public[1]:find("setLuaScript", 1, true), "Must report worm indicator")
onObjectSpawn(untrusted)
assert(#public == 1, "Duplicate alerts must be suppressed")

-- Encoder is a bundled trusted GUID in both release inventories.
local bundledCode = "function onLoad() end"
local trusted = {
    tag = "Custom", type = "Custom",
    getGUID = function() return "02e062" end,
    getLuaScript = function() return bundledCode end,
    getStates = function() return nil end,
}
onObjectSpawn(trusted)
assert(#public == 1, "Known table scripts must not be quarantined or warned on first scan")
bundledCode = "function onLoad() print('updated') end"
onObjectSpawn(trusted)
assert(#public == 2, "A known script changed after baseline must be flagged")

local deck = {
    tag = "Container", type = "Deck",
    getGUID = function() return "f0f0f0" end,
    getLuaScript = function() return "" end,
    getStates = function() return nil end,
    getData = function() return {
        ContainedObjects = {
            {GUID = "e0e0e0", Name = "Card", LuaScript = "function onLoad() end"},
        },
    } end,
}
onObjectSpawn(deck)
assert(#public == 3, "Nested scripted cards must be reported")
onObjectStateChange(deck, "oldstate")
assert(#public == 3, "No duplicate reports on state changes")

getAllObjects = function() return {untrusted, trusted, deck} end
BL_securityScanAll("Blue")
assert(#private == 1, "Manual scans should send summary to requester")
assert(private[1][2] == "Blue")
assert(private[1][1]:find("Scanned 3 objects", 1, true))

print("Security guard tests passed.")
