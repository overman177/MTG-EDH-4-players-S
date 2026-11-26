-- Global XML callbacks and TTS events enter here, then get forwarded to the appropriate Lotus module.

-- =============================================================
-- Shared event dispatcher
-- =============================================================

-- A deck merge can invalidate a TTS reference. Catch callback errors separately so the other modules can still run.
local lotusCallbackErrors = {}
local function lotusSafeCall(label, callback, ...)
    if type(callback) ~= "function" then return end
    local ok, err = pcall(callback, ...)
    if not ok then
        local key = label .. ":" .. tostring(err)
        if not lotusCallbackErrors[key] then
            lotusCallbackErrors[key] = true
            print("[MTG Lotus callback] " .. key)
        end
    end
end

-- Initialize all Lotus modules, then finish UI setup after Global loads.
function onLoad(savedData)
    Playmats.load(savedData)
    Wait.frames(Playmats.alignExisting, 30)
    Settings.load(savedData)
    Preview.load(savedData)
    DrawRandom.load()
    Equipment.load()
    RevealTop.load(savedData)
    Combat.load()
    -- Deferred until Global and the other script objects have loaded.
    Wait.frames(Settings.ready, 20)
    log("MTG Portable Helper: Playmat module ready.")
end

-- Return the combined Lotus state for TTS persistence.
function onSave()
    return Playmats.save()
end

-- Let Reveal Top handle its commands first, then pass the rest to Playmats.
function onChat(message, player)
    local rtResult = RevealTop.onChat(message, player)
    if rtResult ~= nil then return rtResult end
    return Playmats.onChat(message, player)
end

-- Forward the entry event to Preview, Draw Random and Equipment.
function onObjectEnterZone(zone, obj)
    lotusSafeCall("Preview.onEnterZone", Preview.onEnterZone, zone, obj)
    lotusSafeCall("DrawRandom.onEnterZone", DrawRandom.onEnterZone, zone, obj)
    lotusSafeCall("Equipment.onEnterZone", Equipment.onEnterZone, zone, obj)
end

-- Let Preview remember a card's origin before it is moved.
function onObjectPickUp(playerColor, obj)
    lotusSafeCall("Preview.onPickUp", Preview.onPickUp, playerColor, obj)
end

-- Forward drop events to Preview and Equipment.
function onObjectDrop(playerColor, obj)
    lotusSafeCall("Preview.onDrop", Preview.onDrop, playerColor, obj)
    lotusSafeCall("Equipment.onDrop", Equipment.onDrop, playerColor, obj)
end

-- Let the modules forget destroyed decks, visuals and arrow endpoints.
function onObjectDestroy(obj)
    lotusSafeCall("DrawRandom.onDestroy", DrawRandom.onDestroy, obj)
    lotusSafeCall("RevealTop.onDestroy", RevealTop.onDestroy, obj)
    lotusSafeCall("Combat.onDestroy", Combat.onDestroy, obj)
end

-- Forward pointer changes to Equipment.
function onObjectHover(playerColor, obj)
    lotusSafeCall("Equipment.onHover", Equipment.onHover, playerColor, obj)
end

-- Notify the relevant modules that the object left a zone.
function onObjectLeaveZone(zone, obj)
    lotusSafeCall("Preview.onLeaveZone", Preview.onLeaveZone, zone, obj)
    lotusSafeCall("Equipment.onLeaveZone", Equipment.onLeaveZone, zone, obj)
end

-- Forward spawn events to Equipment and Reveal Top.
function onObjectSpawn(obj)
    lotusSafeCall("Equipment.onSpawn", Equipment.onSpawn, obj)
    lotusSafeCall("RevealTop.onSpawn", RevealTop.onSpawn, obj)
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

-- Forward the XML counter toggle to Settings.
function counterToggle(player, value, id)
    Settings.toggle(player, value, id)
end

-- Forward the current-player counter toggle to Settings.
function allMeToggle(player, value, id)
    Settings.toggleAllMe(player, value)
end

-- Forward the all-player counter toggle to Settings.
function allEveryoneToggle(player, value, id)
    Settings.toggleAllEveryone(player, value)
end

-- Forward the viewer's preview toggle to Settings.
function previewToggle(player, value, id)
    Settings.togglePreview(player, value, id)
end

function settingsPreviewSizeChanged(player, value, id)
    Settings.changePreviewSize(player, value, id)
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
