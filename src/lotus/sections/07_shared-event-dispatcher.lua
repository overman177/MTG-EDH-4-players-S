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

-- Optional host-side tracing (TTS console):
-- getObjectFromGUID("185063").call("previewDebug", {enabled=true})
function previewDebug(params)
    Preview.DEBUG = type(params) == "table" and params.enabled == true
    print("MTG Preview diagnostics " .. (Preview.DEBUG and "enabled" or "disabled"))
    return Preview.DEBUG
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

-- TTS shows the local Game Keys dialog with no arguments.
function settingsCombatKeyConfig(player, value, id)
    local color = Settings.playerColor(player)
    if not Settings.validColor(color) or color ~= Settings.menuOwner then return end
    local ok = pcall(function() showHotkeyConfig() end)
    if not ok then
        printToColor("Open Options > Game Keys and bind MTG: Declare and Undo Combat Target.",
            color, {0.90, 0.75, 0.45})
    end
end

-- Per-seat slider callback for the Undo long-press threshold.
function settingsCombatHoldChanged(player, value, id)
    Settings.changeUndoHold(player, value, id)
end

-- Global XML: navigate read-only patch notes release pages.
function settingsNotesNavigate(player, value, id)
    Settings.navigateNotes(player, value, id)
end
