-- Run with lua5.2 tests/counter_visibility_test.lua
-- Regression: toggling EVERYONE off must disable all owners, and toggling
-- one ME back on must not reveal any other player's counters.
local f = assert(io.open("src/lotus/sections/03_edh-settings.lua", "rb"))
local source = f:read("*a")
f:close()
assert(load(source, "@counter-settings", "t", _ENV))()

local attrs, objects, persisted = {}, {}, 0
UI = {setAttribute=function(id, key, value) attrs[id .. "." .. key] = value end}
Playmats = {persist=function() persisted = persisted + 1 end}
for _, kind in ipairs(Settings.TYPES) do
    objects[kind] = {}
    for _, owner in ipairs(Settings.OWNERS) do
        local obj = {owner=owner, guid=kind .. "_" .. owner, invisible=nil}
        function obj.hasTag(tag) return tag == owner or tag == Settings.TAGS[kind] end
        function obj.getGUID() return obj.guid end
        function obj.setInvisibleTo(colors) obj.invisible = colors end
        objects[kind][owner] = obj
    end
end
getObjectsWithTag = function(tag)
    for kind, name in pairs(Settings.TAGS) do
        if name == tag then
            local result = {}
            for _, owner in ipairs(Settings.OWNERS) do
                result[#result + 1] = objects[kind][owner]
            end
            return result
        end
    end
    return {}
end
local function visible(kind, owner)
    local obj = objects[kind][owner]
    return obj.invisible and #obj.invisible == 0
end
local function expectAll(yes)
    for _, kind in ipairs(Settings.TYPES) do
        for _, owner in ipairs(Settings.OWNERS) do
            assert(visible(kind, owner) == yes, kind .. "/" .. owner)
        end
    end
end

Settings.state = {}
Settings.normalize()
Settings.menuOwner = "White"
Settings.applyAll(true)
expectAll(true)
Settings.toggleAllEveryone("White", false)
expectAll(false)
assert(attrs["counter_all_me.isOn"] == "false")
assert(attrs["counter_all_everyone.isOn"] == "false")

Settings.toggle("White", true, "counter_energy_me")
assert(visible("energy", "White"))
assert(not visible("energy", "Blue"))
assert(not visible("poison", "White"))
assert(attrs["counter_energy_me.isOn"] == "true")
assert(attrs["counter_energy_everyone.isOn"] == "false")

Settings.menuOwner = "Red"
Settings.syncUI()
assert(attrs["counter_energy_me.isOn"] == "false")
Settings.toggle("Red", true, "counter_poison_me")
assert(visible("poison", "Red"))
assert(not visible("poison", "White"))
assert(visible("energy", "White"))
assert(attrs["counter_poison_everyone.isOn"] == "false")

Settings.toggle("Red", true, "counter_poison_everyone")
for _, owner in ipairs(Settings.OWNERS) do assert(visible("poison", owner)) end
assert(attrs["counter_poison_everyone.isOn"] == "true")
Settings.toggle("Red", false, "counter_poison_me")
assert(not visible("poison", "Red"))
assert(visible("poison", "White"))
assert(attrs["counter_poison_everyone.isOn"] == "false")

Settings.toggleAllMe("Red", true)
for _, kind in ipairs(Settings.TYPES) do
    assert(visible(kind, "Red"))
end
assert(not visible("energy", "Blue"))
assert(attrs["counter_all_me.isOn"] == "true")
assert(attrs["counter_all_everyone.isOn"] == "false")

-- A legacy EVERYONE=false save represented all hidden, even when ME=true.
Settings.state = {energy={everyone=false, owners={White=true,Blue=true}}}
Settings.normalize()
assert(Settings.state.energy.everyone == nil)
for _, owner in ipairs(Settings.OWNERS) do
    assert(Settings.state.energy.owners[owner] == false)
end
Settings.state.energy.owners.White = true
Settings.normalize() -- save/load normalization must NOT erase new exceptions
assert(Settings.state.energy.owners.White == true)
assert(Settings.state.energy.owners.Blue == false)
assert(persisted >= 4)
print("Counter visibility independent-owner regression test passed")
