-- Black Lotus Guard tests. Run: lua5.2 tests/security_guard_test.lua
local public, private, dataCalls = {}, {}, 0
broadcastToAll = function(message) public[#public + 1] = tostring(message) end
broadcastToColor = function(message, color) private[#private + 1] = {message, color} end
Wait = {frames = function(callback) callback() end}

local fixtures = {
    clean = {Name="Card", States={["2"]={Name="Card"}}},
    cleanDeck = {Name="Deck", ContainedObjects={{Name="Card"}}},
    scripted = {Name="Card", LuaScript="onLoad()"},
    stateScripted = {Name="Card", States={["2"]={LuaScript="onLoad()"}}},
    nestedScripted = {Name="Deck", ContainedObjects={{LuaScript="onLoad()"}}},
    xml = {Name="Card", XmlUI="<Panel/>"},
    state = {Name="Card", LuaScriptState="json"},
    badType = {Name="Custom_Token"}
}
JSON = {decode = function(text)
    if fixtures[text] then return fixtures[text] end
    error("not JSON")
end}

dofile("src/global/sections/39_security-guard.lua")
local function valid(s, expected)
    local ok = BL_securityValidateCardJSON(s)
    assert(ok == expected, "unexpected validation: " .. s:sub(1,30))
end
valid("clean",true)
valid("cleanDeck",true)
valid("scripted",false)
valid("stateScripted",false)
valid("nestedScripted",false)
valid("xml",false)
valid("state",false)
valid("badType",false)
valid("not-json",false)

local function fake(guid, script, contents, states)
    return {
        tag=contents and "Deck" or "Custom",
        type=contents and "Deck" or "Custom",
        getGUID=function() return guid end,
        getLuaScript=function() return script end,
        getObjects=function() return contents end,
        getStateId=function() return states and 1 or -1 end,
        getStates=function() return states end,
        getData=function()
            dataCalls = dataCalls + 1
            return {ContainedObjects={{GUID="dee123",
                LuaScript="function onLoad() getObjectFromGUID('1').setLuaScript('bad') end"}}}
        end,
    }
end

local benign = fake("abc001", "function onLoad() self.setName('Safe') end")
local worm = fake("abc002", "function onLoad() target.setLuaScript('bad') end")
local trusted = fake("02e062", "function onLoad() target.setLuaScript('updater') end")
local states = fake("abc003", "", nil, {{
    guid="abc301", lua_script="function onLoad() o.script_code = 'bad' end"
}})
local deck = fake("abc004", "", {{
    guid="abc401", lua_script="function onLoad() obj.setLuaScript('worm') end"
}})
onObjectSpawn(benign)
onObjectSpawn(trusted)
assert(#public == 0, "Known or innocuous scripts should not alert")
onObjectSpawn(worm)
assert(#public == 1, "A worm-capable script should alert")
onObjectSpawn(worm)
assert(#public == 1, "Repeated scans should deduplicate alerts")
onObjectSpawn(states)
onObjectSpawn(deck)
assert(dataCalls == 0, "Fast path MUST NOT call getData")
onObjectStateChange(benign, "old")
assert(dataCalls == 0, "State change path MUST NOT call getData")

getAllObjects = function() return {benign, worm, trusted, states, deck} end
BL_securityScanAll("Blue")
assert(#private == 1 and private[1][2] == "Blue", "Manual summary must be private")
assert(private[1][1]:find("Scan: 5 objects",1,true))
assert(dataCalls == 0, "Normal scan MUST NOT call getData")

-- Deep mode deliberately performs serialization and detects nested payloads.
BL_securityScanAll(nil, true)
assert(dataCalls > 0, "Deep scan should inspect nested saved data")
print("Security guard tests passed")
