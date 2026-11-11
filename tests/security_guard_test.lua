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
        getQuantity=function() return contents and #contents or -1 end,
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
-- Regression: keyword tokens / custom counters can be tagged as Bag/Container,
-- but do NOT implement getObjects(). Never invoke it on these objects.
local invalidContainerCalls = 0
local keywordToken = fake("bacdad", "function onLoad() end")
keywordToken.tag = "Bag"
keywordToken.type = "Custom_Token"
keywordToken.getQuantity = function() return 5 end
keywordToken.getObjects = function()
    invalidContainerCalls = invalidContainerCalls + 1
    error("getObjects unsupported on keyword token")
end
local customCounter = fake("c0c0c0", "function onLoad() end")
customCounter.tag = "Container"
customCounter.type = "Custom_Model"
customCounter.getObjects = keywordToken.getObjects
onObjectSpawn(keywordToken)
onObjectSpawn(customCounter)
assert(invalidContainerCalls == 0, "Must never call getObjects on keyword tokens/counters")
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

getAllObjects = function() return {benign, worm, trusted, states, deck, keywordToken, customCounter} end
BL_securityScanAll("Blue")
assert(#private == 1 and private[1][2] == "Blue", "Manual summary must be private")
assert(private[1][1]:find("Scan: 7 objects",1,true))
assert(dataCalls == 0, "Normal scan MUST NOT call getData")
assert(invalidContainerCalls == 0, "Manual scan must skip noncontainer getObjects")

-- Deep mode deliberately performs serialization and detects nested payloads.
BL_securityScanAll(nil, true)
assert(dataCalls > 0, "Deep scan should inspect nested saved data")
-- Exceptions for bundled keyword dispensers and utility pieces.
-- They MUST remain script-inspected, but must never receive getObjects().
local exceptions = {
    {guid = "b653d2", name = "Turn Skipper Puck"},
    {guid = "feadfa", name = "Haste"},
    {guid = "de6012", name = "Renowned"},
    {guid = "b9f545", name = "Menace"},
    {guid = "c1840d", name = "Vigilance"},
    {guid = "c3ca32", name = "Double Strike"},
    {guid = "c36338", name = "First Strike"},
    {guid = "bc8aef", name = "Rhystic Block Bag"},
    {guid = "beb998", name = "+X/+Y Counter"},
    {guid = "60df73", name = "d6"},
    {guid = "cbcea4", name = "d4"},
}
for _, pair in ipairs(exceptions) do
    local obj = fake(pair.guid, "", {{guid = "child"}})
    obj.tag = "Bag"
    obj.type = "Infinite"
    obj.getName = function() return pair.name end
    obj.getObjects = keywordToken.getObjects
    onObjectSpawn(obj)
end
-- Name-based exception survives reimported infinite-bag GUID changes.
local renamed = fake("abcdef", "", {{guid = "child"}})
renamed.type = "Infinite"
renamed.getName = function() return "Haste" end
renamed.getObjects = keywordToken.getObjects
onObjectSpawn(renamed)
assert(invalidContainerCalls == 0,
    "Known uninspectable props must never be passed to getObjects")

-- Valid imported decks and ordinary bags MUST still be scanned.
local actualDeckScan, actualBagScan = 0, 0
local deckWithThreat = fake("bac001", "", {{
    guid="bac002", lua_script="function onLoad() obj.setLuaScript('bad') end"
}})
deckWithThreat.type = "Deck"
deckWithThreat.getName = function() return "Haste" end
deckWithThreat.getObjects = function()
    actualDeckScan = actualDeckScan + 1
    return {{guid="bac002",lua_script="function onLoad() obj.setLuaScript('bad') end"}}
end
local ordinaryBag = fake("bac003", "", {{
    guid="bac004", lua_script="function onLoad() x.setLuaScript('worm') end"
}})
ordinaryBag.type = "Bag"
ordinaryBag.getName = function() return "Imported Bag" end
ordinaryBag.getObjects = function()
    actualBagScan = actualBagScan + 1
    return {{guid="bac004",lua_script="function onLoad() x.setLuaScript('worm') end"}}
end
onObjectSpawn(deckWithThreat)
onObjectSpawn(ordinaryBag)
local savedBefore = dataCalls
getAllObjects = function() return {renamed, deckWithThreat, ordinaryBag} end
BL_securityScanAll(nil, true)
assert(dataCalls > savedBefore,
    "Deep scan must still serialize exempt keyword dispensers")
assert(invalidContainerCalls == 0,
    "Deep scan must not call getObjects on exempt objects")
assert(actualDeckScan > 1 and actualBagScan > 1,
    "Real container inspection must remain enabled during deep scan")
assert(actualDeckScan == 2 and actualBagScan == 2,
    "Real decks and bags must still receive getObjects() checks")
assert(invalidContainerCalls == 0,
    "Exempt props must not trigger any unsupported getObjects() calls")

print("Security guard tests passed")
