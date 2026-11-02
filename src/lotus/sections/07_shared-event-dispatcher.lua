-- =============================================================
-- SHARED EVENT DISPATCHER (6 MODULES)
-- =============================================================

function onLoad(savedData)
    Playmats.load(savedData)
    Settings.load(savedData)
    Preview.load(savedData)
    DrawRandom.load()
    Equipment.load()
    RevealTop.load(savedData)
    Combat.load()
    -- Deferred until Global and the other script objects have loaded.
    Wait.frames(Settings.ready, 20)
    print("MTG Portable Helper: Playmat module ready.")
end

function onSave()
    return Playmats.save()
end

function onChat(message, player)
    local rtResult = RevealTop.onChat(message, player)
    if rtResult ~= nil then return rtResult end
    return Playmats.onChat(message, player)
end

function onObjectEnterZone(zone, obj)
    Preview.onEnterZone(zone, obj)
    DrawRandom.onEnterZone(zone, obj)
    Equipment.onEnterZone(zone, obj)
end

function onObjectPickUp(playerColor, obj)
    Preview.onPickUp(playerColor, obj)
end

function onObjectDrop(playerColor, obj)
    Preview.onDrop(playerColor, obj)
    Equipment.onDrop(playerColor, obj)
end

function onObjectDestroy(obj)
    DrawRandom.onDestroy(obj)
    RevealTop.onDestroy(obj)
    Combat.onDestroy(obj)
end

function onObjectHover(playerColor, obj)
    Equipment.onHover(playerColor, obj)
end

function onObjectLeaveZone(zone, obj)
    Preview.onLeaveZone(zone, obj)
    Equipment.onLeaveZone(zone, obj)
end

function onObjectSpawn(obj)
    Equipment.onSpawn(obj)
    RevealTop.onSpawn(obj)
end

-- Public methods retained for compatibility with other table scripts.
function setPreviewPreferences(params)
    Preview.setPreferences(params)
end

function getPreviewPreferences()
    return Settings.getPreviewPreferences()
end

function applyPreviewSettings()
    Settings.applyPreview()
end

function applyAll()
    Settings.applyAll(true)
end

-- Object button callback (playerColor is a string)
function settingsButtonClick(obj, playerColor, alt)
    Settings.open(obj, playerColor)
end

-- Global XML UI callbacks (player may be a Player object)
function closeCounterSettings(player, value, id)
    Settings.close(player)
end

function counterToggle(player, value, id)
    Settings.toggle(player, value, id)
end

function allMeToggle(player, value, id)
    Settings.toggleAllMe(player, value)
end

function allEveryoneToggle(player, value, id)
    Settings.toggleAllEveryone(player, value)
end

function previewToggle(player, value, id)
    Settings.togglePreview(player, value, id)
end

-- Global XML: tab navigation. Notebook patch notes are read-only.
function settingsSelectTab(player, value, id)
    Settings.selectTab(player, value, id)
end

-- Personal on-screen shortcut overlay switch in General Settings.
function settingsGeneralToggle(player, value, id)
    Settings.toggleGeneral(player, value, id)
end

-- Binding must be selected by the player in TTS; Lua cannot write the key.
function settingsCombatKeyConfig(player, value, id)
    local color = Settings.playerColor(player)
    if not Settings.validColor(color) or color ~= Settings.menuOwner then return end
    -- TTS's networked hotkey dialog requires the requesting player's color.
    -- Without this argument it may open only for the host (or not at all).
    local ok = pcall(showHotkeyConfig, color)
    if not ok then
        printToColor("Open Options > Game Keys and bind 'MTG: Declare Combat Target' to C (or your preferred key).",
            color, {0.90, 0.75, 0.45})
    end
end

function settingsCombatClear(player, value, id)
    local color = Settings.playerColor(player)
    if color == nil or color ~= Settings.menuOwner then return end
    Combat.clear(color)
end

-- Global XML: navigate read-only patch notes release pages.
function settingsNotesNavigate(player, value, id)
    Settings.navigateNotes(player, value, id)
end
