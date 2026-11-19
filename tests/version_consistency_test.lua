-- Release metadata must not diverge between Global, Lotus and compiled GUID files.
local function read(path)
    local f=assert(io.open(path,"rb"))
    local text=f:read("*a")
    f:close()
    return text
end

local version="1.9.5"
local lotus=read("src/lotus/sections/00_card-preview.lua")
local settings=read("src/lotus/sections/03_edh-settings.lua")
local global=read("src/global/sections/32_patch-notes.lua")
local manifest=read("src/manifest.json")

assert(lotus:find('local HELPER_VERSION = "' .. version .. '"', 1, true),
    "Lotus self-name version does not match the release")
assert(lotus:find('MTG LOTUS HELPER  |  v' .. version, 1, true),
    "Lotus module header is stale")
assert(global:find('VERSION = "v' .. version .. '"',1,true),
    "Global banner version does not match Lotus")
assert(settings:find('Settings.LOCAL_MAINTENANCE_NOTES',1,true)
    and settings:find('Version ' .. version,1,true),
    "Lotus Settings does not provide current patch notes")
assert(settings:find('notes = Settings.LOCAL_MAINTENANCE_NOTES',1,true),
    "Current notes are not displayed in the Lotus Settings reader")
assert(not lotus:find('local HELPER_VERSION = "1.9.0"',1,true),
    "Stale Lotus 1.9.0 version detected")
-- This deliberately checks the actual GUID target, not only source files.
local compiledLotus=read("live/objects/lotus-helper/[FF595E]M[FF924C]T[FFCA3A]G [C5E55E]L[66D17A]o[35C9AF]t[3EBBDF]u[5B9BFF]s [8578EA]H[B879E4]e[DB75C7]l[EE80A4]p[FF595E]e[FF924C]r [C5CDD9]v1.8.0[-].185063.lua")
assert(compiledLotus:find('local HELPER_VERSION = "'..version..'"',1,true))
assert(compiledLotus:find('Settings.LOCAL_MAINTENANCE_NOTES',1,true))
local compiledGlobal=read("live/global/Global.-1.lua")
assert(compiledGlobal:find('VERSION = "v'..version..'"',1,true))
print("4P Global/Lotus version and patch notes consistency: OK")
