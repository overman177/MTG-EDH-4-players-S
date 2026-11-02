-- Lua 5.2: the Lotus General -> Configure key callback opens Game Keys
-- for the player who actually clicked it, including non-host seats.
local shown, fallback = {}, {}
Settings = {
    menuOwner = "White",
    playerColor = function(player)
        if type(player) == "string" then return player end
        return player and player.color or nil
    end,
    validColor = function(color)
        return color == "White" or color == "Blue"
            or color == "Red" or color == "Yellow"
    end
}
function showHotkeyConfig(color)
    assert(type(color) == "string", "TTS dialog must receive player color")
    shown[#shown + 1] = color
end
function printToColor(msg, color)
    fallback[#fallback + 1] = {message = msg, color = color}
end
dofile("src/lotus/sections/07_shared-event-dispatcher.lua")

-- Clicking Global UI delivers a Player object, not a color string.
settingsCombatKeyConfig({color = "White"}, "", "lotus_combat_bind")
assert(#shown == 1 and shown[1] == "White",
       "White player must receive their own keybind window")
settingsCombatKeyConfig({color = "Blue"}, "", "lotus_combat_bind")
assert(#shown == 1, "another player cannot invoke the open menu's callback")
Settings.menuOwner = "Blue"
settingsCombatKeyConfig({color = "Blue"}, "", "lotus_combat_bind")
assert(#shown == 2 and shown[2] == "Blue",
       "remote Blue player must receive their own window")
Settings.menuOwner = "Red"
settingsCombatKeyConfig("Red", "", "lotus_combat_bind")
assert(#shown == 3 and shown[3] == "Red",
       "string player color also supported")
Settings.menuOwner = nil
settingsCombatKeyConfig(nil, "", "lotus_combat_bind")
settingsCombatKeyConfig({color = "Grey"}, "", "lotus_combat_bind")
assert(#shown == 3, "invalid or absent owner cannot open the window")

-- If TTS declines the dialog call, explain the native manual route instead.
Settings.menuOwner = "Yellow"
showHotkeyConfig = function()
    error("simulated missing TTS dialog API")
end
settingsCombatKeyConfig({color = "Yellow"}, "", "lotus_combat_bind")
assert(#fallback == 1 and fallback[1].color == "Yellow",
       "fallback guidance must reach the clicking player")
assert(fallback[1].message:find("Game Keys", 1, true),
       "fallback tells player where to bind the key")
print("Lotus keybinding menu player routing tests passed.")
