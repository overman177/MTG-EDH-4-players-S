-- =============================================================
-- MODULE 4/4: EDH SETTINGS
-- =============================================================

Settings = {
    TAG = "MTG_EDH_Settings_Controller",
    OLD_CONTROLLER_GUID = "777766",  -- migration only (can be removed later)
    OWNERS = {"Red", "Blue", "White", "Yellow"},
    TYPES = {"energy", "poison", "experience", "rad"},
    TAGS = {
        energy = "Counter_Energy",
        poison = "Counter_Poison",
        experience = "Counter_Experience",
        rad = "Counter_Rad"
    },
    state = {},
    previewOwnEnabled = {},
    previewOpponentsEnabled = {},
    previewHideOwnLands = {},
    previewHideOpponentsLands = {},
    previewFirstCommanderOwn = {},
    previewFirstCommanderOpponents = {},
    previewSizeByColor = {}, -- per-seat scale percentage
    showShortcutsByColor = {}, -- personal HUD visibility, keyed by TTS seat color
    combatEnabledByColor = {}, -- per-seat combat targeting preference
    combatUndoHoldSecondsByColor = {}, -- per-seat long-press threshold, 1-10 seconds
    menuOpen = false,
    menuOwner = nil,
    uiSyncing = false,
    hasSavedState = false,
    lastApplied = {},
    activeTab = "notes",
    notesPages = {},
    notesIndex = 1,
    notesRaw = nil
}

-- Clamp saved/client values to whole seconds. Invalid/old saves default to 5.
function Settings.normalizeUndoHold(value)
    local n = tonumber(value)
    if not n or n ~= n then return 5 end
    return math.max(1, math.min(10, math.floor(n + 0.5)))
end

function Settings.getUndoHold(color)
    if type(Settings.combatUndoHoldSecondsByColor) ~= "table" then return 5 end
    return Settings.normalizeUndoHold(Settings.combatUndoHoldSecondsByColor[color])
end

function Settings.normalizePreviewSize(value)
    local n = tonumber(value)
    if not n or n ~= n then return 100 end
    return math.max(50, math.min(150, math.floor(n / 5 + 0.5) * 5))
end

function Settings.getPreviewSize(color)
    return Settings.normalizePreviewSize(Settings.previewSizeByColor[color])
end

function Settings.normalize()
    for _, kind in ipairs(Settings.TYPES) do
        if type(Settings.state[kind]) ~= "table" then
            Settings.state[kind] = {}
        end
        local state = Settings.state[kind]
        if type(state.owners) ~= "table" then
            state.owners = type(state.ownerVisible) == "table" and state.ownerVisible or {}
        end
        -- Legacy saves used "everyone" as a hard global gate. If that gate
        -- was off, every counter of this type was effectively invisible,
        -- even if all of the individual owner flags were still checked.
        -- Migrate that state once, then store only per-owner visibility.
        if state.everyone == false then
            for _, color in ipairs(Settings.OWNERS) do
                state.owners[color] = false
            end
        end
        state.everyone = nil
        for _, color in ipairs(Settings.OWNERS) do
            if state.owners[color] == nil then state.owners[color] = true end
        end
    end
    for _, color in ipairs(Settings.OWNERS) do
        if Settings.previewOwnEnabled[color] == nil then
            Settings.previewOwnEnabled[color] = true
        end
        if Settings.previewOpponentsEnabled[color] == nil then
            Settings.previewOpponentsEnabled[color] = true
        end
        if Settings.previewHideOwnLands[color] == nil then
            Settings.previewHideOwnLands[color] = false
        end
        if Settings.previewHideOpponentsLands[color] == nil then
            Settings.previewHideOpponentsLands[color] = false
        end
        if Settings.previewFirstCommanderOwn[color] == nil then
            Settings.previewFirstCommanderOwn[color] = true
        end
        if Settings.previewFirstCommanderOpponents[color] == nil then
            Settings.previewFirstCommanderOpponents[color] = true
        end
        Settings.previewSizeByColor[color] =
            Settings.normalizePreviewSize(Settings.previewSizeByColor[color])
        if Settings.showShortcutsByColor[color] == nil then
            Settings.showShortcutsByColor[color] = true
        end
        if Settings.combatEnabledByColor[color] == nil then
            Settings.combatEnabledByColor[color] = true
        end
        Settings.combatUndoHoldSecondsByColor[color] =
            Settings.normalizeUndoHold(Settings.combatUndoHoldSecondsByColor[color])
    end
end

-- Older saves used "MY VIEW / MY CARDS". Only the MY VIEW flags have a
-- meaningful replacement: they apply equally to both new viewer categories.
-- The old MY CARDS publishing restriction is intentionally not migrated,
-- because the new settings cannot control other players' screens.
local function copyPreviewColors(saved)
    local result = {}
    for _, color in ipairs(Settings.OWNERS) do result[color] = saved[color] end
    return result
end

function Settings.import(data)
    if type(data) ~= "table" then return false end
    if type(data.state) ~= "table"
        and type(data.previewOwnEnabled) ~= "table"
        and type(data.previewOpponentsEnabled) ~= "table"
        and type(data.previewHideOwnLands) ~= "table"
        and type(data.previewHideOpponentsLands) ~= "table"
        and type(data.previewFirstCommanderOwn) ~= "table"
        and type(data.previewFirstCommanderOpponents) ~= "table"
        and type(data.previewSizeByColor) ~= "table"
        and type(data.previewEnabled) ~= "table"
        and type(data.previewHideLands) ~= "table"
        and type(data.previewShareEnabled) ~= "table"
        and type(data.previewHideOwnLandsForOthers) ~= "table"
        and type(data.showShortcutsByColor) ~= "table"
        and type(data.combatEnabledByColor) ~= "table"
        and type(data.combatUndoHoldSecondsByColor) ~= "table" then
        return false
    end
    if type(data.state) == "table" then Settings.state = data.state end
    if type(data.previewOwnEnabled) == "table" then
        Settings.previewOwnEnabled = data.previewOwnEnabled
    elseif type(data.previewEnabled) == "table" then
        Settings.previewOwnEnabled = copyPreviewColors(data.previewEnabled)
    end
    if type(data.previewOpponentsEnabled) == "table" then
        Settings.previewOpponentsEnabled = data.previewOpponentsEnabled
    elseif type(data.previewEnabled) == "table" then
        Settings.previewOpponentsEnabled = copyPreviewColors(data.previewEnabled)
    end
    if type(data.previewHideOwnLands) == "table" then
        Settings.previewHideOwnLands = data.previewHideOwnLands
    elseif type(data.previewHideLands) == "table" then
        Settings.previewHideOwnLands = copyPreviewColors(data.previewHideLands)
    end
    if type(data.previewHideOpponentsLands) == "table" then
        Settings.previewHideOpponentsLands = data.previewHideOpponentsLands
    elseif type(data.previewHideLands) == "table" then
        Settings.previewHideOpponentsLands = copyPreviewColors(data.previewHideLands)
    end
    if type(data.previewFirstCommanderOwn) == "table" then
        Settings.previewFirstCommanderOwn = data.previewFirstCommanderOwn
    end
    if type(data.previewFirstCommanderOpponents) == "table" then
        Settings.previewFirstCommanderOpponents = data.previewFirstCommanderOpponents
    end
    if type(data.previewSizeByColor) == "table" then
        Settings.previewSizeByColor = data.previewSizeByColor
    end
    if type(data.showShortcutsByColor) == "table" then
        Settings.showShortcutsByColor = data.showShortcutsByColor
    end
    if type(data.combatEnabledByColor) == "table" then
        Settings.combatEnabledByColor = data.combatEnabledByColor
    end
    if type(data.combatUndoHoldSecondsByColor) == "table" then
        Settings.combatUndoHoldSecondsByColor = data.combatUndoHoldSecondsByColor
    end
    Settings.hasSavedState = true
    Settings.normalize()
    return true
end

function Settings.load(savedData)
    Settings.state = {}
    Settings.previewOwnEnabled = {}
    Settings.previewOpponentsEnabled = {}
    Settings.previewHideOwnLands = {}
    Settings.previewHideOpponentsLands = {}
    Settings.previewFirstCommanderOwn = {}
    Settings.previewFirstCommanderOpponents = {}
    Settings.previewSizeByColor = {}
    Settings.showShortcutsByColor = {}
    Settings.combatEnabledByColor = {}
    Settings.combatUndoHoldSecondsByColor = {}
    Settings.menuOpen = false
    Settings.menuOwner = nil
    Settings.uiSyncing = false
    Settings.lastApplied = {}
    Settings.activeTab = "general"
    Settings.notesPages = {}
    Settings.notesIndex = 1
    Settings.notesRaw = nil
    Settings.hasSavedState = false

    if type(savedData) == "string" and savedData ~= "" then
        local ok, data = pcall(JSON.decode, savedData)
        if ok and type(data) == "table" then
            -- Integrated v0.4 save; also allow direct old controller JSON.
            Settings.import(data.settings or data)
        end
    end

    -- One-time copy from the old Settings Controller, if still on the table.
    -- After successful migration remove its script/object to avoid duplicate menus.
    if not Settings.hasSavedState then
        local old = getObjectFromGUID(Settings.OLD_CONTROLLER_GUID)
        if old ~= nil and old ~= self then
            local ok, stored = pcall(function() return old.script_state end)
            if ok and type(stored) == "string" and stored ~= "" then
                local decodedOK, decoded = pcall(JSON.decode, stored)
                if decodedOK and Settings.import(decoded) then
                    print("MTG Helper: previous EDH settings imported from old controller.")
                end
            end
        end
    end
    Settings.normalize()
    self.addTag(Settings.TAG)
    if Settings.hasSavedState then Playmats.persist() end
end

function Settings.export()
    return {
        state = Settings.state,
        previewOwnEnabled = Settings.previewOwnEnabled,
        previewOpponentsEnabled = Settings.previewOpponentsEnabled,
        previewHideOwnLands = Settings.previewHideOwnLands,
        previewHideOpponentsLands = Settings.previewHideOpponentsLands,
        previewFirstCommanderOwn = Settings.previewFirstCommanderOwn,
        previewFirstCommanderOpponents = Settings.previewFirstCommanderOpponents,
        previewSizeByColor = Settings.previewSizeByColor,
        showShortcutsByColor = Settings.showShortcutsByColor,
        combatEnabledByColor = Settings.combatEnabledByColor,
        combatUndoHoldSecondsByColor = Settings.combatUndoHoldSecondsByColor
    }
end

function Settings.persist()
    Playmats.persist()  -- saves playmats AND settings together
end

function Settings.getPreviewPreferences()
    local own, opponents, hideOwn, hideOpponents = {}, {}, {}, {}
    local commanderOwn, commanderOpponents = {}, {}
    local sizeByColor = {}
    for _, color in ipairs(Settings.OWNERS) do
        own[color] = Settings.previewOwnEnabled[color] ~= false
        opponents[color] = Settings.previewOpponentsEnabled[color] ~= false
        hideOwn[color] = Settings.previewHideOwnLands[color] == true
        hideOpponents[color] = Settings.previewHideOpponentsLands[color] == true
        commanderOwn[color] = Settings.previewFirstCommanderOwn[color] ~= false
        commanderOpponents[color] =
            Settings.previewFirstCommanderOpponents[color] ~= false
        sizeByColor[color] = Settings.getPreviewSize(color)
    end
    return {
        ownEnabledByColor = own,
        opponentsEnabledByColor = opponents,
        hideOwnLandsByColor = hideOwn,
        hideOpponentsLandsByColor = hideOpponents,
        firstCommanderOwnByColor = commanderOwn,
        firstCommanderOpponentsByColor = commanderOpponents,
        sizeByColor = sizeByColor
    }
end

function Settings.applyPreview()
    -- Both modules live in the same object: no cross-object call required.
    Preview.setPreferences(Settings.getPreviewPreferences())
end

function Settings.getOwner(obj)
    for _, color in ipairs(Settings.OWNERS) do
        if obj.hasTag(color) then return color end
    end
    return nil
end

-- EVERYONE is a bulk action and an aggregate indicator, not a master gate.
-- When the last player's ME flag is enabled, EVERYONE automatically checks.
function Settings.allOwnersVisible(kind)
    local state = Settings.state[kind]
    if not state or type(state.owners) ~= "table" then return false end
    for _, color in ipairs(Settings.OWNERS) do
        if state.owners[color] == false then return false end
    end
    return true
end

function Settings.visibility(kind, obj)
    local state = Settings.state[kind]
    if not state then return true end
    local owner = Settings.getOwner(obj)
    -- Unknown-owner counters cannot be selectively assigned to one seat.
    -- Keep them hidden unless all seats have this counter type enabled.
    if owner == nil then return Settings.allOwnersVisible(kind) end
    return state.owners[owner] ~= false
end

function Settings.applyType(kind, force)
    local tag = Settings.TAGS[kind]
    if tag == nil then return end
    for _, obj in ipairs(getObjectsWithTag(tag) or {}) do
        local guid = obj.getGUID()
        local visible = Settings.visibility(kind, obj)
        local key = kind .. ":" .. tostring(visible)
        if force or guid == nil or Settings.lastApplied[guid] ~= key then
            -- Identical semantics to original EDH Settings Controller:
            -- invisible to the four EDH seats when disabled.
            obj.setInvisibleTo(visible and {} or Settings.OWNERS)
            if guid ~= nil then Settings.lastApplied[guid] = key end
        end
    end
end

function Settings.applyAll(force)
    for _, kind in ipairs(Settings.TYPES) do
        Settings.applyType(kind, force)
    end
end

function Settings.playerColor(player)
    if type(player) == "string" then return player end
    return player and player.color or nil
end

function Settings.validColor(color)
    for _, c in ipairs(Settings.OWNERS) do
        if c == color then return true end
    end
    return false
end

function Settings.toBool(value)
    if type(value) == "boolean" then return value end
    return tostring(value):lower() == "true"
end

function Settings.setToggle(id, value)
    UI.setAttribute(id, "isOn", value and "true" or "false")
end

function Settings.syncUI()
    if not Settings.menuOwner then return end
    Settings.uiSyncing = true
    local color = Settings.menuOwner
    local allMe = true
    local allEveryone = true

    for _, kind in ipairs(Settings.TYPES) do
        local mine = Settings.state[kind].owners[color] ~= false
        local everyone = Settings.allOwnersVisible(kind)
        Settings.setToggle("counter_" .. kind .. "_me", mine)
        Settings.setToggle("counter_" .. kind .. "_everyone", everyone)
        if not mine then allMe = false end
        if not everyone then allEveryone = false end
    end

    Settings.setToggle("counter_all_me", allMe)
    Settings.setToggle("counter_all_everyone", allEveryone)
    Settings.setToggle("preview_cards_mine", Settings.previewOwnEnabled[color] ~= false)
    Settings.setToggle("preview_cards_opponents", Settings.previewOpponentsEnabled[color] ~= false)
    Settings.setToggle("preview_hide_lands_mine", Settings.previewHideOwnLands[color] == true)
    Settings.setToggle("preview_hide_lands_opponents",
        Settings.previewHideOpponentsLands[color] == true)
    Settings.setToggle("preview_first_commander_mine",
        Settings.previewFirstCommanderOwn[color] ~= false)
    Settings.setToggle("preview_first_commander_opponents",
        Settings.previewFirstCommanderOpponents[color] ~= false)
    local scale = Settings.getPreviewSize(color)
    UI.setAttribute("lotus_preview_size_slider", "value", tostring(scale))
    UI.setAttribute("lotus_preview_size_value", "text", tostring(scale) .. "%")
    Settings.setToggle("lotus_show_shortcuts",
        Settings.showShortcutsByColor[color] ~= false)
    Settings.setToggle("lotus_enable_combat",
        Settings.combatEnabledByColor[color] ~= false)
    local hold = Settings.getUndoHold(color)
    UI.setAttribute("lotus_combat_hold_slider", "value", tostring(hold))
    UI.setAttribute("lotus_combat_hold_value", "text", tostring(hold) .. " s")
    Settings.uiSyncing = false
end

-- The settings window is visible only to its current menu owner.
-- Tab selection therefore remains local to whoever opened this menu.
Settings.TAB_IDS = {
    general = { panel = "MTG_Settings_Tab_General", button = "MTG_Settings_Button_General" },
    notes = { panel = "MTG_Settings_Tab_Notes", button = "MTG_Settings_Button_Notes" },
    counters = { panel = "MTG_Settings_Tab_Counters", button = "MTG_Settings_Button_Counters" },
    preview = { panel = "MTG_Settings_Tab_Preview", button = "MTG_Settings_Button_Preview" }
}

function Settings.applyTab()
    local height = "465"
    if Settings.activeTab == "notes" then height = "605"
    elseif Settings.activeTab == "general" then height = "465"
    elseif Settings.activeTab == "preview" then height = "465"
    end
    UI.setAttribute("CounterVisibilityPanel", "height", height)
    for tab, ids in pairs(Settings.TAB_IDS) do
        local selected = Settings.activeTab == tab
        UI.setAttribute(ids.panel, "active", selected and "true" or "false")
        UI.setAttribute(ids.button, "colors", selected
            and "#315A87|#4274AC|#234363|#234363"
            or "#29292E|#3D3D45|#222229|#222229")
        UI.setAttribute(ids.button, "textColor", selected and "#FFFFFF" or "#C9D1DF")
    end
end

function Settings.selectTab(player, value, id)
    if Settings.playerColor(player) ~= Settings.menuOwner then return end
    local tab = ({
        MTG_Settings_Button_General = "general",
        MTG_Settings_Button_Notes = "notes",
        MTG_Settings_Button_Counters = "counters",
        MTG_Settings_Button_Preview = "preview"
    })[id]
    if tab == nil then return end
    Settings.activeTab = tab
    Settings.applyTab()
    if tab == "notes" then Settings.syncPatchNotes() end
end

-- NOTEBOOK STORAGE -------------------------------------------------------
-- Private Black notebook page = editable source for the table creator.
-- Lotus reads it when Patch Notes opens; the settings text is never editable.
Settings.NOTEBOOK_TITLE = "LOTUS_PATCH_NOTES"
Settings.NOTEBOOK_COLOR = "Black"

function Settings.getNotebookTab()
    -- Returns (matching tab or nil, notebook API available).
    -- Compare title and color so a public page with the same name cannot
    -- silently replace the private source. Tab indices may change; use name.
    local ok, tabs = pcall(function() return Notes.getNotebookTabs() end)
    if not ok or type(tabs) ~= "table" then
        return nil, false
    end
    for _, tab in ipairs(tabs) do
        if tab.title == Settings.NOTEBOOK_TITLE
            and tab.color == Settings.NOTEBOOK_COLOR then
            return tab, true
        end
    end
    return nil, true
end

function Settings.ensureNotebookTab()
    local tab, available = Settings.getNotebookTab()
    if not available then
        print("MTG Helper: could not access the TTS Notebook API.")
        return
    end
    if tab ~= nil then return end  -- never replace the creator's notes

    -- Create the private page only once, when it doesn't already exist.
    -- Blank by design: the creator provides the release notes in Notebook.
    local ok, index = pcall(function()
        return Notes.addNotebookTab({
            title = Settings.NOTEBOOK_TITLE,
            body = "",
            color = Settings.NOTEBOOK_COLOR
        })
    end)
    if not ok or index == -1 then
        print("MTG Helper: failed to create LOTUS_PATCH_NOTES Notebook page.")
    else
        print("MTG Helper: created private Black Notebook page LOTUS_PATCH_NOTES.")
    end
end

-- Read release headings from the creator's private Notebook, keeping the
-- Notebook text as the single source of truth. One release at a time avoids
-- TTS scroll view clipping and inconsistent mouse-wheel handling.
local function notesTrim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- One release is one page. Do not wrap at character counts or split at
-- arbitrary line counts: Unity Text performs natural wrapping based on the
-- actual panel width, and the larger panel can shrink the font as needed.
function Settings.parsePatchNotes(raw)
    raw = tostring(raw or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local sections, current = {}, nil
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        local cleaned = notesTrim(line)
        if cleaned:match("^[Vv]ersion%s+[%d%.]+") then
            if current ~= nil then table.insert(sections, current) end
            current = { title = cleaned, lines = {} }
        elseif cleaned ~= "" then
            -- Blank Notebook spacer lines are visual separators only; they
            -- must not create empty rows inside the compact release reader.
            -- Preserve the full original words and let TTS wrap at the edge.
            if current == nil then
                current = { title = "Patch Notes", lines = {} }
            end
            table.insert(current.lines, cleaned)
        end
    end
    if current ~= nil then table.insert(sections, current) end
    if #sections == 0 then
        sections = {{ title = "Patch Notes", lines = {"No patch notes published yet."} }}
    end
    -- Avoid a useless empty intro when the Notebook starts with a heading.
    if #sections > 1 and sections[1].title == "Patch Notes"
        and #sections[1].lines == 0 then
        table.remove(sections, 1)
    end

    local pages = {}
    for _, section in ipairs(sections) do
        if #section.lines == 0 then section.lines = {"No changes listed."} end
        table.insert(pages, {
            title = section.title,
            body = table.concat(section.lines, "\n")
        })
    end
    return pages
end

function Settings.displayPatchNotes()
    local pages = Settings.notesPages
    if #pages == 0 then
        pages = {{ title = "Patch Notes", body = "No patch notes published yet." }}
    end
    Settings.notesIndex = math.max(1, math.min(Settings.notesIndex, #pages))
    local page = pages[Settings.notesIndex]
    UI.setAttribute("MTG_Settings_PatchNotesVersion", "text", page.title)
    UI.setAttribute("MTG_Settings_PatchNotesText", "text", page.body)
    UI.setAttribute("MTG_Settings_PatchNotesPosition", "text",
        tostring(Settings.notesIndex) .. " / " .. tostring(#pages))
    UI.setAttribute("MTG_Settings_PatchNotesNewer", "interactable",
        Settings.notesIndex > 1 and "true" or "false")
    UI.setAttribute("MTG_Settings_PatchNotesOlder", "interactable",
        Settings.notesIndex < #pages and "true" or "false")
    UI.setAttribute("MTG_Settings_PatchNotesHint", "text", Settings.PATCH_NOTES_HINT)
end

function Settings.syncPatchNotes(resetToLatest)
    -- Re-read the Notebook whenever the menu or tab opens. Do not mutate it.
    local tab, available = Settings.getNotebookTab()
    local notes
    if not available then
        notes = "Patch notes are unavailable: TTS Notebook could not be read."
    elseif tab == nil or type(tab.body) ~= "string" or notesTrim(tab.body) == "" then
        notes = "No patch notes published yet."
    else
        notes = tab.body
    end
    if Settings.notesRaw ~= notes then
        Settings.notesRaw = notes
        Settings.notesPages = Settings.parsePatchNotes(notes)
        Settings.notesIndex = 1
    elseif resetToLatest then
        Settings.notesIndex = 1
    end
    Settings.displayPatchNotes()
end

function Settings.navigateNotes(player, value, id)
    if Settings.playerColor(player) ~= Settings.menuOwner
        or Settings.activeTab ~= "notes" then return end
    if id == "MTG_Settings_PatchNotesNewer" then
        Settings.notesIndex = Settings.notesIndex - 1
    elseif id == "MTG_Settings_PatchNotesOlder" then
        Settings.notesIndex = Settings.notesIndex + 1
    else
        return
    end
    Settings.displayPatchNotes()
end

-- UI callbacks are global functions below, forwarded to these methods.
function Settings.open(obj, color)
    if Settings.menuOpen or not Settings.validColor(color) then return end
    Settings.menuOpen = true
    Settings.menuOwner = color
    UI.setAttribute("CounterVisibilityPanel", "visibility", color)
    UI.setAttribute("CounterVisibilityPanel", "active", "true")
    Settings.syncUI()
    Settings.activeTab = "general"
    Settings.applyTab()
    Settings.syncPatchNotes(true)
end

function Settings.close(player)
    local color = Settings.playerColor(player)
    if color ~= Settings.menuOwner then return end
    UI.setAttribute("CounterVisibilityPanel", "active", "false")
    Settings.menuOpen = false
    Settings.menuOwner = nil
end

function Settings.toggle(player, value, id)
    if Settings.uiSyncing then return end
    local color = Settings.playerColor(player)
    if color == nil or color ~= Settings.menuOwner or type(id) ~= "string" then return end
    local kind, column = id:match("^counter_(%w+)_(%w+)$")
    if not kind or not Settings.state[kind] then return end
    local checked = Settings.toBool(value)
    if column == "me" then
        Settings.state[kind].owners[color] = checked
    elseif column == "everyone" then
        for _, owner in ipairs(Settings.OWNERS) do
            Settings.state[kind].owners[owner] = checked
        end
    else
        return
    end
    Settings.applyType(kind, true)
    Settings.persist()
    Settings.syncUI()
end

function Settings.toggleAllMe(player, value)
    if Settings.uiSyncing then return end
    local color = Settings.playerColor(player)
    if color == nil or color ~= Settings.menuOwner then return end
    local checked = Settings.toBool(value)
    for _, kind in ipairs(Settings.TYPES) do
        Settings.state[kind].owners[color] = checked
        Settings.applyType(kind, true)
    end
    Settings.persist()
    Settings.syncUI()
end

function Settings.toggleAllEveryone(player, value)
    if Settings.uiSyncing then return end
    if Settings.playerColor(player) ~= Settings.menuOwner then return end
    local checked = Settings.toBool(value)
    for _, kind in ipairs(Settings.TYPES) do
        for _, owner in ipairs(Settings.OWNERS) do
            Settings.state[kind].owners[owner] = checked
        end
        Settings.applyType(kind, true)
    end
    Settings.persist()
    Settings.syncUI()
end

function Settings.togglePreview(player, value, id)
    if Settings.uiSyncing then return end
    local color = Settings.playerColor(player)
    if color == nil or color ~= Settings.menuOwner then return end
    local checked = Settings.toBool(value)
    if id == "preview_cards_mine" then
        Settings.previewOwnEnabled[color] = checked
    elseif id == "preview_cards_opponents" then
        Settings.previewOpponentsEnabled[color] = checked
    elseif id == "preview_hide_lands_mine" then
        Settings.previewHideOwnLands[color] = checked
    elseif id == "preview_hide_lands_opponents" then
        Settings.previewHideOpponentsLands[color] = checked
    elseif id == "preview_first_commander_mine" then
        Settings.previewFirstCommanderOwn[color] = checked
    elseif id == "preview_first_commander_opponents" then
        Settings.previewFirstCommanderOpponents[color] = checked
    else
        return
    end
    Settings.applyPreview()
    Settings.persist()
    Settings.syncUI()
end

-- Scale is a viewer preference, not a publisher preference. The callback
-- validates the current menu owner before touching any seat-specific panel.
function Settings.changePreviewSize(player, value, id)
    if Settings.uiSyncing or id ~= "lotus_preview_size_slider" then return end
    local color = Settings.playerColor(player)
    if not Settings.validColor(color) or color ~= Settings.menuOwner then return end
    local scale = Settings.normalizePreviewSize(value)
    UI.setAttribute("lotus_preview_size_value", "text", tostring(scale) .. "%")
    if Settings.getPreviewSize(color) == scale then return end
    Settings.previewSizeByColor[color] = scale
    Preview.setSize(color, scale)
    Settings.persist()
end

-- HUD visibility is a VIEWER preference. One player's switch never changes
-- any other player's overlay; global keyboard bindings remain in Global.lua.
Settings.HUD_VIEWERS = {
    "White", "Brown", "Red", "Orange", "Yellow", "Green",
    "Teal", "Blue", "Purple", "Pink", "Grey", "Black"
}

function Settings.applyShortcutsVisibility()
    local viewers = {}
    for _, color in ipairs(Settings.HUD_VIEWERS) do
        if Settings.showShortcutsByColor[color] ~= false then
            table.insert(viewers, color)
        end
    end
    -- Empty visibility means EVERYONE in TTS, so never use an empty string
    -- as the hidden value. The overlay is still a single shared Global UI node.
    UI.setAttribute("MTG_ShortcutsOverlay", "visibility",
        #viewers > 0 and table.concat(viewers, "|") or "Black")
    UI.setAttribute("MTG_ShortcutsOverlay", "active",
        #viewers > 0 and "true" or "false")
end

function Settings.toggleGeneral(player, value, id)
    if Settings.uiSyncing then return end
    local color = Settings.playerColor(player)
    if color == nil or color ~= Settings.menuOwner or not Settings.validColor(color) then
        return
    end
    if id == "lotus_show_shortcuts" then
        Settings.showShortcutsByColor[color] = Settings.toBool(value)
        Settings.applyShortcutsVisibility()
    elseif id == "lotus_enable_combat" then
        Settings.combatEnabledByColor[color] = Settings.toBool(value)
        if not Settings.combatEnabledByColor[color] then
            Combat.pending[color] = nil
            Combat.clear(color)
        end
    else
        return
    end
    Settings.persist()
end

-- A per-player value selected in the General tab. The menu is owner-only;
-- another player's slider callback must never change this owner's setting.
function Settings.changeUndoHold(player, value, id)
    if Settings.uiSyncing or id ~= "lotus_combat_hold_slider" then return end
    local color = Settings.playerColor(player)
    if not Settings.validColor(color) or color ~= Settings.menuOwner then return end
    local seconds = Settings.normalizeUndoHold(value)
    UI.setAttribute("lotus_combat_hold_value", "text", tostring(seconds) .. " s")
    if Settings.getUndoHold(color) == seconds then return end
    Settings.combatUndoHoldSecondsByColor[color] = seconds
    Settings.persist()
end

-- Keep every unrelated button attached to the Lotus intact.
function Settings.createButton()
    for _, button in ipairs(self.getButtons() or {}) do
        if button.click_function == "settingsButtonClick" then return end
    end
    self.createButton({
        click_function = "settingsButtonClick",
        function_owner = self,
        label = "Settings",
        position = {0, 0.6, 0},
        rotation = {0, 180, 0},
        scale = {1, 1, 1},
        width = 900,
        height = 150,
        font_size = 220,
        color = {0.15, 0.15, 0.15, 0.9},
        font_color = {1, 1, 1, 1}
    })
end

-- Single-release reader: natural word wrapping, no split pages, no
-- blank-line gaps, and a much larger text field. Best-fit prevents ordinary
-- release notes from being clipped without relying on mouse-wheel scrolling.
function Settings.patchNotesReader()
    return {
        tag = "Panel",
        attributes = {
            id = "MTG_Settings_PatchNotesBox",
            rectAlignment = "UpperCenter", offsetXY = "0 -36",
            width = "500", height = "394", color = "#28272B"
        },
        children = {
            { tag = "Text", attributes = {
                id = "MTG_Settings_PatchNotesVersion",
                rectAlignment = "UpperLeft", offsetXY = "13 -8",
                width = "474", height = "32", fontSize = "21",
                fontStyle = "Bold", color = "#FFFFFF",
                alignment = "MiddleLeft", text = "Patch Notes"
            }},
            { tag = "Panel", attributes = {
                id = "MTG_Settings_PatchNotesReader_v120",
                rectAlignment = "UpperCenter", offsetXY = "0 -44",
                width = "472", height = "2", color = "#4B5D71"
            }},
            { tag = "Text", attributes = {
                id = "MTG_Settings_PatchNotesText",
                rectAlignment = "UpperLeft", offsetXY = "13 -54",
                width = "474", height = "284", fontSize = "17",
                resizeTextForBestFit = "true",
                resizeTextMinSize = "12",
                resizeTextMaxSize = "17",
                color = "#EDEEF2", alignment = "UpperLeft",
                horizontalOverflow = "Wrap", verticalOverflow = "Truncate",
                raycastTarget = "false", text = "No patch notes published yet."
            }},
            { tag = "HorizontalLayout", attributes = {
                rectAlignment = "LowerCenter", offsetXY = "0 9",
                width = "474", height = "34", spacing = "10",
                childAlignment = "MiddleCenter",
                childForceExpandWidth = "false", childForceExpandHeight = "false"
            }, children = {
                {tag = "Button", attributes = {
                    id = "MTG_Settings_PatchNotesNewer",
                    preferredWidth = "135", preferredHeight = "34",
                    fontSize = "15", fontStyle = "Bold",
                    textColor = "#FFFFFF",
                    colors = "#315A87|#4274AC|#234363|#234363",
                    onClick = "777766/settingsNotesNavigate", text = "< NEWER"
                }},
                {tag = "Text", attributes = {
                    id = "MTG_Settings_PatchNotesPosition",
                    preferredWidth = "164", preferredHeight = "34",
                    fontSize = "14", color = "#AEBAC8",
                    alignment = "MiddleCenter", text = "1 / 1"
                }},
                {tag = "Button", attributes = {
                    id = "MTG_Settings_PatchNotesOlder",
                    preferredWidth = "135", preferredHeight = "34",
                    fontSize = "15", fontStyle = "Bold",
                    textColor = "#FFFFFF",
                    colors = "#315A87|#4274AC|#234363|#234363",
                    onClick = "777766/settingsNotesNavigate", text = "OLDER >"
                }}
            }}
        }
    }
end

Settings.PATCH_NOTES_HINT = "Read-only | Creator edits LOTUS_PATCH_NOTES in the Black Notebook"

-- The preview tab is regenerated as a unit to avoid mismatched columns
-- when upgrading older Global XML; counter/notes tabs remain untouched.
function Settings.previewTab()
    local function label(text, width, color, size, bold)
        local attr = {
            preferredWidth = tostring(width), minWidth = tostring(width),
            fontSize = tostring(size or 17), color = color or "rgb(0.9,0.9,0.9)",
            alignment = "MiddleLeft", text = text
        }
        if bold then attr.fontStyle = "Bold" end
        return {tag = "Text", attributes = attr}
    end
    local function toggle(id, enabled, width)
        return {tag = "Toggle", attributes = {
            id = id, isOn = enabled and "True" or "False",
            onValueChanged = "777766/previewToggle",
            preferredWidth = tostring(width), minWidth = tostring(width)
        }}
    end
    local function row(y, title, myID, myDefault, opponentsID, opponentsDefault, titleSize)
        return {tag = "HorizontalLayout", attributes = {
            rectAlignment = "UpperCenter", offsetXY = "0 " .. tostring(y),
            width = "500", height = "44", spacing = "8",
            childForceExpandWidth = "false", childForceExpandHeight = "false"
        }, children = {
            label(title, 220, nil, titleSize or 17),
            toggle(myID, myDefault, 105),
            toggle(opponentsID, opponentsDefault, 155)
        }}
    end
    return {tag = "Panel", attributes = {
        id = "MTG_Settings_Tab_Preview",
        rectAlignment = "UpperCenter", offsetXY = "0 -124",
        width = "516", height = "320", color = "clear", active = "false"
    }, children = {
        {tag = "HorizontalLayout", attributes = {
            id = "MTG_Settings_PreviewGrid_v120_compact",
            rectAlignment = "UpperCenter", offsetXY = "0 -8",
            width = "500", height = "28", spacing = "8",
            childForceExpandWidth = "false", childForceExpandHeight = "false"
        }, children = {
            label("PREVIEW OPTION", 220, "#6fa0d8", 14, true),
            label("MY CARDS", 105, "#6fa0d8", 13, true),
            label("OPPONENTS' CARDS", 155, "#6fa0d8", 12, true)
        }},
        row(-50, "Played Card Preview", "preview_cards_mine", true,
            "preview_cards_opponents", true),
        row(-102, "Hide Land Previews", "preview_hide_lands_mine", false,
            "preview_hide_lands_opponents", false),
        row(-154, "First Commander Entry Preview",
            "preview_first_commander_mine", true,
            "preview_first_commander_opponents", true, 14),
        {tag = "Text", attributes = {
            rectAlignment = "UpperLeft", offsetXY = "8 -211",
            width = "480", height = "21", fontSize = "14",
            fontStyle = "Bold", color = "#6fa0d8",
            text = "PREVIEW SIZE (MY SCREEN ONLY)"
        }},
        {tag = "HorizontalLayout", attributes = {
            rectAlignment = "UpperCenter", offsetXY = "0 -240",
            width = "500", height = "35", spacing = "8",
            childForceExpandWidth = "false", childForceExpandHeight = "false"
        }, children = {
            label("Card preview scale", 176, nil, 16),
            {tag = "Slider", attributes = {
                id = "lotus_preview_size_slider",
                onValueChanged = self.getGUID() .. "/settingsPreviewSizeChanged",
                preferredWidth = "237", minWidth = "237",
                preferredHeight = "30", minHeight = "30",
                minValue = "50", maxValue = "150", value = "100",
                wholeNumbers = "true",
                backgroundColor = "#393A42", fillColor = "#4274AC",
                handleColor = "#E5EBF4"
            }},
            {tag = "Text", attributes = {
                id = "lotus_preview_size_value",
                preferredWidth = "65", minWidth = "65",
                fontSize = "17", fontStyle = "Bold",
                color = "#87B9EF", alignment = "MiddleRight", text = "100%"
            }}
        }},
        {tag = "Text", attributes = {
            rectAlignment = "UpperLeft", offsetXY = "8 -288",
            width = "490", height = "20", fontSize = "13",
            color = "#9BA4B0",
            text = "Affects my and opponents' card previews on my screen only."
        }}
    }}
end

-- Read-only shortcut list mirrors Global.onScriptingButtonDown.
-- Numpad 0 corresponds to scripting index 10; 1-9 correspond to indices 1-9.
-- This overlay NEVER registers scripting events of its own.
Settings.SHORTCUTS = {
    { key = "Num 0", action = "Enable / End turn" },
    { key = "Num 1", action = "Untap" },
    { key = "Num 2", action = "Draw" },
    { key = "Num 3", action = "Scry" },
    { key = "Num 4", action = "Mill" },
    { key = "Num 5", action = "Reveal (fan)" },
    { key = "Num 6", action = "Reveal (stack)" },
    { key = "Num 7", action = "To graveyard *" },
    { key = "Num 8", action = "To exile *" },
    { key = "Num 9", action = "Library bottom *" }
}

-- Persistent screen-edge overlay, shown from every seat (not world-space text).
-- No raycast targets: it doesn't block tabletop interactions underneath.
function Settings.shortcutsOverlay()
    local rows = {}
    for _, item in ipairs(Settings.SHORTCUTS) do
        table.insert(rows, {tag = "HorizontalLayout", attributes = {
            preferredHeight = "24", minHeight = "24", spacing = "6",
            childForceExpandHeight = "false", childForceExpandWidth = "false",
            raycastTarget = "false"
        }, children = {
            {tag = "Text", attributes = {
                preferredWidth = "54", minWidth = "54", fontSize = "14",
                fontStyle = "Bold", color = "#87B9EF",
                alignment = "MiddleLeft", raycastTarget = "false",
                text = item.key
            }},
            {tag = "Text", attributes = {
                preferredWidth = "166", minWidth = "166", fontSize = "14",
                color = "#F0F1F4", alignment = "MiddleLeft",
                raycastTarget = "false", text = item.action
            }}
        }})
    end
    return {tag = "Panel", attributes = {
        id = "MTG_ShortcutsOverlay", rectAlignment = "MiddleLeft",
        offsetXY = "7 -165", width = "252", height = "325",
        color = "clear",
        raycastTarget = "false", active = "true"
    }, children = {
        {tag = "Text", attributes = {
            rectAlignment = "UpperLeft", offsetXY = "11 -9",
            width = "230", height = "22", fontSize = "17",
            fontStyle = "Bold", color = "#F0F1F4",
            raycastTarget = "false", text = "Shortcuts"
        }},
        {tag = "VerticalLayout", attributes = {
            rectAlignment = "UpperCenter", offsetXY = "0 -34",
            width = "228", height = "251", spacing = "1",
            childForceExpandHeight = "false", childForceExpandWidth = "false",
            raycastTarget = "false"
        }, children = rows},
        {tag = "Text", attributes = {
            rectAlignment = "LowerLeft", offsetXY = "11 8",
            width = "230", height = "15", fontSize = "11",
            color = "#ACB7C5", raycastTarget = "false",
            text = "* Selected cards or hovered card"
        }}
    }}
end

function Settings.generalTab()
    local cb = self.getGUID() .. "/"
    return {tag = "Panel", attributes = {
        id = "MTG_Settings_Tab_General", rectAlignment = "UpperCenter",
        offsetXY = "0 -124", width = "516", height = "280",
        color = "clear", active = "false"
    }, children = {
        {tag = "Text", attributes = {
            rectAlignment = "UpperLeft", offsetXY = "11 -3", width = "470",
            height = "24", fontSize = "14", fontStyle = "Bold",
            alignment = "MiddleLeft", color = "#6fa0d8", text = "GENERAL"
        }},
        {tag = "Panel", attributes = {
            id = "MTG_Settings_GeneralContent_v155",
            rectAlignment = "UpperCenter", offsetXY = "0 -36",
            width = "500", height = "240", color = "#28272B"
        }, children = {
            {tag = "Toggle", attributes = {
                id = "lotus_show_shortcuts", isOn = "True",
                onValueChanged = cb .. "settingsGeneralToggle",
                rectAlignment = "UpperLeft", offsetXY = "16 -12",
                width = "465", height = "31", fontSize = "17",
                textColor = "#EDEEF2"
            }, value = "Show numpad shortcuts on my screen"},
            {tag = "Text", attributes = {
                rectAlignment = "UpperLeft", offsetXY = "16 -46",
                width = "465", height = "20", fontSize = "13",
                color = "#9BA4B0", alignment = "MiddleLeft",
                text = "Numpad keys: TTS Configuration > Controls."
            }},
            {tag = "Toggle", attributes = {
                id = "lotus_enable_combat", isOn = "True",
                onValueChanged = cb .. "settingsGeneralToggle",
                rectAlignment = "UpperLeft", offsetXY = "16 -79",
                width = "465", height = "33", fontSize = "17",
                textColor = "#EDEEF2"
            }, value = "Enable combat targeting for me"},
            {tag = "Button", attributes = {
                id = "lotus_combat_bind",
                onClick = cb .. "settingsCombatKeyConfig",
                rectAlignment = "UpperLeft", offsetXY = "16 -127",
                width = "468", height = "35", fontSize = "15",
                textColor = "#FFFFFF", colors = "#315A87|#4274AC|#234363|#234363",
                text = "Open Game Keys"
            }},
            {tag = "Text", attributes = {
                rectAlignment = "UpperLeft", offsetXY = "16 -177",
                width = "365", height = "24", fontSize = "15",
                fontStyle = "Bold", color = "#EDEEF2",
                alignment = "MiddleLeft",
                text = "Hold UNDO to clear all your arrows"
            }},
            {tag = "Text", attributes = {
                id = "lotus_combat_hold_value",
                rectAlignment = "UpperRight", offsetXY = "-16 -177",
                width = "88", height = "24", fontSize = "17",
                fontStyle = "Bold", color = "#87B9EF",
                alignment = "MiddleRight", text = "5 s"
            }},
            {tag = "Slider", attributes = {
                id = "lotus_combat_hold_slider",
                onValueChanged = cb .. "settingsCombatHoldChanged",
                rectAlignment = "UpperLeft", offsetXY = "16 -209",
                width = "468", height = "27",
                minValue = "1", maxValue = "10", value = "5",
                wholeNumbers = "true",
                backgroundColor = "#393A42", fillColor = "#4274AC",
                handleColor = "#E5EBF4"
            }},
        }}
    }}
end

-- Upgrades both the older three-tab panel and the v1.4.1 Shortcuts tab.
-- Rebuilds only Lotus's own tab buttons; leaves all other Global UI intact.
function Settings.ensureGeneralTab(panel)
    if type(panel) ~= "table" or type(panel.children) ~= "table" then return false end
    local tabbar
    for _, child in ipairs(panel.children) do
        if child.attributes and child.attributes.id == "MTG_Settings_TabBar" then
            tabbar = child
            break
        end
    end
    if tabbar == nil or type(tabbar.children) ~= "table" then return false end
    local changed = false
    local hasGeneral = false
    -- Use an existing General button if present. Migrate the Shortcuts button
    -- in place when possible, instead of leaving two buttons behind.
    for _, btn in ipairs(tabbar.children) do
        if btn.attributes and btn.attributes.id == "MTG_Settings_Button_General" then
            hasGeneral = true
        end
    end
    for i = #tabbar.children, 1, -1 do
        local btn = tabbar.children[i]
        local attr = btn.attributes or {}
        if attr.id == "MTG_Settings_Button_Shortcuts" then
            if hasGeneral then
                table.remove(tabbar.children, i)
            else
                attr.id = "MTG_Settings_Button_General"
                attr.text = "General"
                attr.onClick = self.getGUID() .. "/settingsSelectTab"
                hasGeneral = true
            end
            changed = true
        end
    end
    if not hasGeneral then
        table.insert(tabbar.children, 1, {tag = "Button", attributes = {
            id = "MTG_Settings_Button_General", text = "General",
            preferredWidth = "124", minWidth = "124",
            preferredHeight = "38", minHeight = "38",
            fontSize = "15", fontStyle = "Bold", textColor = "#FFFFFF",
            colors = "#315A87|#4274AC|#234363|#234363",
            onClick = self.getGUID() .. "/settingsSelectTab"
        }})
        changed = true
    end
    local preferredOrder = {
        "MTG_Settings_Button_General", "MTG_Settings_Button_Notes",
        "MTG_Settings_Button_Counters", "MTG_Settings_Button_Preview"
    }
    local byId = {}
    for _, btn in ipairs(tabbar.children) do
        if btn.attributes then byId[btn.attributes.id] = btn end
    end
    local ordered = {}
    for _, id in ipairs(preferredOrder) do
        if byId[id] then table.insert(ordered, byId[id]) end
    end
    -- Unknown tab buttons should not be deleted.
    for _, btn in ipairs(tabbar.children) do
        local id = btn.attributes and btn.attributes.id
        if not byId[id] or not (
            id == preferredOrder[1] or id == preferredOrder[2] or
            id == preferredOrder[3] or id == preferredOrder[4]) then
            table.insert(ordered, btn)
        end
    end
    if #ordered == #tabbar.children then
        for i, btn in ipairs(ordered) do
            if tabbar.children[i] ~= btn then changed = true; break end
        end
        tabbar.children = ordered
    end
    for _, btn in ipairs(tabbar.children) do
        local attr = btn.attributes
        if attr and type(attr.id) == "string"
            and attr.id:match("^MTG_Settings_Button_") then
            for _, field in ipairs({"preferredWidth", "minWidth"}) do
                if attr[field] ~= "124" then attr[field] = "124"; changed = true end
            end
            if attr.fontSize ~= "15" then attr.fontSize = "15"; changed = true end
        end
    end

    local hasGeneralPanel = false
    for i = #panel.children, 1, -1 do
        local child = panel.children[i]
        local id = child.attributes and child.attributes.id
        if id == "MTG_Settings_Tab_General" then
            hasGeneralPanel = true
            -- Replace only Lotus' own obsolete General tab. Never touch other UI.
            local current = false
            for _, node in ipairs(child.children or {}) do
                if node.attributes
                    and node.attributes.id == "MTG_Settings_GeneralContent_v155" then
                    current = true
                    break
                end
            end
            if not current then
                panel.children[i] = Settings.generalTab()
                changed = true
            end
        elseif id == "MTG_Settings_Tab_Shortcuts" then
            table.remove(panel.children, i)
            changed = true
        end
    end
    if not hasGeneralPanel then
        table.insert(panel.children, 1, Settings.generalTab())
        changed = true
    end
    return changed
end

-- Tabbed panel is also generated as a fallback when no Global XML panel exists.
-- The installer automatically upgrades the legacy panel on first load.
function Settings.tabbedPanel()
    local panel = {
        tag = "Panel",
        attributes = {
            id = "CounterVisibilityPanel",
            width = "560",
            height = "465",
            rectAlignment = "MiddleCenter",
            showAnimation = "FadeIn",
            hideAnimation = "FadeOut",
            returnToOriginalPositionWhenReleased = "false",
            allowDragging = "true",
            color = "rgba(0.1,0.1,0.1,0.97)",
            outline = "#635351",
            outlineSize = "2 -2",
            visibility = "",
            active = "false",
        },
        children = {
            {
            tag = "Text",
            attributes = {
                rectAlignment = "UpperCenter",
                offsetXY = "0 -18",
                width = "410",
                height = "34",
                fontSize = "26",
                fontStyle = "Bold",
                color = "rgb(1,1,1)",
                alignment = "MiddleCenter",
                text = "Table Settings",
            },
        }, 
            {
            tag = "Button",
            attributes = {
                id = "CounterVisibilityClose",
                rectAlignment = "UpperRight",
                offsetXY = "-8 -8",
                width = "30",
                height = "30",
                color = "#990000",
                textColor = "#FFFFFF",
                text = "X",
                fontSize = "18",
                onClick = "777766/closeCounterSettings",
            },
        }, 
            {
            tag = "HorizontalLayout",
            attributes = {
                id = "MTG_Settings_TabBar",
                rectAlignment = "UpperCenter",
                offsetXY = "0 -70",
                width = "516",
                height = "40",
                spacing = "6",
                childForceExpandWidth = "false",
                childForceExpandHeight = "false",
            },
            children = {
                {
                tag = "Button",
                attributes = {
                    id = "MTG_Settings_Button_Notes",
                    preferredWidth = "168",
                    minWidth = "168",
                    preferredHeight = "38",
                    minHeight = "38",
                    fontSize = "16",
                    fontStyle = "Bold",
                    textColor = "#FFFFFF",
                    colors = "#315A87|#4274AC|#234363|#234363",
                    onClick = "777766/settingsSelectTab",
                    text = "Patch Notes",
                },
            }, 
                {
                tag = "Button",
                attributes = {
                    id = "MTG_Settings_Button_Counters",
                    preferredWidth = "168",
                    minWidth = "168",
                    preferredHeight = "38",
                    minHeight = "38",
                    fontSize = "16",
                    fontStyle = "Bold",
                    textColor = "#C9D1DF",
                    colors = "#29292E|#3D3D45|#222229|#222229",
                    onClick = "777766/settingsSelectTab",
                    text = "Counters",
                },
            }, 
                {
                tag = "Button",
                attributes = {
                    id = "MTG_Settings_Button_Preview",
                    preferredWidth = "168",
                    minWidth = "168",
                    preferredHeight = "38",
                    minHeight = "38",
                    fontSize = "16",
                    fontStyle = "Bold",
                    textColor = "#C9D1DF",
                    colors = "#29292E|#3D3D45|#222229|#222229",
                    onClick = "777766/settingsSelectTab",
                    text = "Card Preview",
                },
            }, 
            },
        }, 
            {
            tag = "Panel",
            attributes = {
                id = "MTG_Settings_Tab_Notes",
                rectAlignment = "UpperCenter",
                offsetXY = "0 -124",
                width = "516",
                height = "460",
                color = "clear",
                active = "true",
            },
            children = {
                {
                tag = "Text",
                attributes = {
                    rectAlignment = "UpperLeft",
                    offsetXY = "11 -3",
                    width = "400",
                    height = "25",
                    fontSize = "14",
                    fontStyle = "Bold",
                    alignment = "MiddleLeft",
                    color = "#6fa0d8",
                    text = "PATCH NOTES",
                },
            }, 
                Settings.patchNotesReader(),
                {
                tag = "Text",
                attributes = {
                    id = "MTG_Settings_PatchNotesHint",
                    rectAlignment = "LowerCenter",
                    offsetXY = "0 5",
                    width = "495",
                    height = "22",
                    fontSize = "12",
                    alignment = "MiddleLeft",
                    color = "#9BA4B0",
                    text = Settings.PATCH_NOTES_HINT,
                },
            }, 
            },
        }, 
            {
            tag = "Panel",
            attributes = {
                id = "MTG_Settings_Tab_Counters",
                rectAlignment = "UpperCenter",
                offsetXY = "0 -124",
                width = "516",
                height = "325",
                color = "clear",
                active = "false",
            },
            children = {
                {
                tag = "VerticalLayout",
                attributes = {
                    rectAlignment = "UpperCenter",
                    offsetXY = "0 -5",
                    width = "500",
                    height = "300",
                    spacing = "5",
                    childForceExpandHeight = "false",
                    childForceExpandWidth = "true",
                },
                children = {
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "28",
                        minHeight = "28",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "14",
                            fontStyle = "Bold",
                            color = "#6fa0d8",
                            alignment = "MiddleLeft",
                            text = "COUNTER TYPE",
                        },
                    }, 
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "80",
                            minWidth = "80",
                            fontSize = "14",
                            fontStyle = "Bold",
                            color = "#6fa0d8",
                            alignment = "MiddleCenter",
                            text = "ME",
                        },
                    }, 
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "100",
                            minWidth = "100",
                            fontSize = "14",
                            fontStyle = "Bold",
                            color = "#6fa0d8",
                            alignment = "MiddleCenter",
                            text = "EVERYONE",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "38",
                        minHeight = "38",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            color = "rgb(0.9,0.9,0.9)",
                            alignment = "MiddleLeft",
                            text = "Energy Counters",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_energy_me",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_energy_everyone",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "38",
                        minHeight = "38",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            color = "rgb(0.9,0.9,0.9)",
                            alignment = "MiddleLeft",
                            text = "Poison Counters",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_poison_me",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_poison_everyone",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "38",
                        minHeight = "38",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            color = "rgb(0.9,0.9,0.9)",
                            alignment = "MiddleLeft",
                            text = "Experience Counters",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_experience_me",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_experience_everyone",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "38",
                        minHeight = "38",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            color = "rgb(0.9,0.9,0.9)",
                            alignment = "MiddleLeft",
                            text = "Rad Counters",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_rad_me",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_rad_everyone",
                            isOn = "True",
                            onValueChanged = "777766/counterToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                    {
                    tag = "HorizontalLayout",
                    attributes = {
                        preferredHeight = "42",
                        minHeight = "42",
                        spacing = "8",
                        childForceExpandWidth = "false",
                        childForceExpandHeight = "false",
                    },
                    children = {
                        {
                        tag = "Text",
                        attributes = {
                            preferredWidth = "260",
                            minWidth = "260",
                            fontSize = "17",
                            fontStyle = "Bold",
                            color = "rgb(1,1,1)",
                            alignment = "MiddleLeft",
                            text = "ALL COUNTERS",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_all_me",
                            isOn = "True",
                            onValueChanged = "777766/allMeToggle",
                            preferredWidth = "80",
                            minWidth = "80",
                        },
                    }, 
                        {
                        tag = "Toggle",
                        attributes = {
                            id = "counter_all_everyone",
                            isOn = "True",
                            onValueChanged = "777766/allEveryoneToggle",
                            preferredWidth = "100",
                            minWidth = "100",
                        },
                    }, 
                    },
                }, 
                },
            }, 
            },
        }, 
            Settings.previewTab(),
        },
    }
    Settings.ensureGeneralTab(panel)
    return panel
end

-- v1.2.0 marker upgrades earlier patch-note readers on Save & Play.
-- This is essential because the previous reader already had the same root ID.
function Settings.isCurrentPatchReader(node)
    local function hasMarker(n)
        if n.attributes and n.attributes.id ==
            "MTG_Settings_PatchNotesReader_v120" then
            return true
        end
        for _, child in ipairs(n.children or {}) do
            if hasMarker(child) then return true end
        end
        return false
    end
    return hasMarker(node)
end

function Settings.installUI()
    local xml = UI.getXmlTable() or {}
    local found, changed = false, false
    local guid = self.getGUID()
    local callbacks = {
        closeCounterSettings = true,
        counterToggle = true,
        allMeToggle = true,
        allEveryoneToggle = true,
        previewToggle = true,
        settingsSelectTab = true,
        settingsNotesNavigate = true,
        settingsGeneralToggle = true,
        settingsCombatKeyConfig = true,
        settingsCombatHoldChanged = true,
        settingsPreviewSizeChanged = true
    }

    local function hasTabs(node)
        if type(node) ~= "table" then return false end
        if node.attributes and node.attributes.id == "MTG_Settings_TabBar" then
            return true
        end
        for _, child in ipairs(node.children or {}) do
            if hasTabs(child) then return true end
        end
        return false
    end

    -- Walk every UI subtree, replacing only the legacy Settings panel.
    -- Preserve all unrelated Global XML, including preview/other mod UIs.
    local function walk(nodes)
        for index, node in ipairs(nodes) do
            if node.attributes and node.attributes.id == "CounterVisibilityPanel" then
                found = true
                if not hasTabs(node) then
                    nodes[index] = Settings.tabbedPanel()
                    node = nodes[index]
                    changed = true
                    print("MTG Helper: legacy settings panel upgraded to tabs.")
                end
                if Settings.ensureGeneralTab(node) then
                    changed = true
                    print("MTG Helper: installed General settings tab.")
                end
            end
            if type(node.attributes) == "table" then
                -- The previous tab panel is too short for a full release.
                if node.attributes.id == "MTG_Settings_Tab_Notes"
                    and node.attributes.height ~= "460" then
                    node.attributes.height = "460"
                    changed = true
                end
                -- Migrate legacy InputField, ScrollViews and older readers
                -- without touching any other settings or table UI.
                if node.attributes.id == "MTG_Settings_PatchNotesInput"
                    or (node.attributes.id == "MTG_Settings_PatchNotesBox"
                        and not Settings.isCurrentPatchReader(node)) then
                    nodes[index] = Settings.patchNotesReader()
                    node = nodes[index]
                    changed = true
                    print("MTG Helper: upgraded Patch Notes to the release reader.")
                end
                if node.attributes.id == "MTG_Settings_Tab_Preview" then
                    local upgraded = false
                    for _, child in ipairs(node.children or {}) do
                        if child.attributes and
                            child.attributes.id == "lotus_preview_size_slider" then
                            upgraded = true
                            break
                        end
                    end
                    if not upgraded then
                        nodes[index] = Settings.previewTab()
                        node = nodes[index]
                        changed = true
                        print("MTG Helper: updated compact Card Preview settings.")
                    end
                end
                if node.attributes.id == "MTG_Settings_PatchNotesHint" then
                    if node.attributes.text ~= Settings.PATCH_NOTES_HINT then
                        node.attributes.text = Settings.PATCH_NOTES_HINT
                        changed = true
                    end
                end
                for _, attr in ipairs({"onClick", "onValueChanged", "onEndEdit"}) do
                    local callback = node.attributes[attr]
                    if type(callback) == "string" then
                        local previous, fn = callback:match("^([%w]+)/([%w_]+)$")
                        if previous == Settings.OLD_CONTROLLER_GUID and callbacks[fn] then
                            node.attributes[attr] = guid .. "/" .. fn
                            changed = true
                        end
                    end
                end
            end
            if type(node.children) == "table" then walk(node.children) end
        end
    end
    walk(xml)

    -- Install the shortcuts overlay only if it is missing.
    -- Never replace an existing panel: its position, size, alignment, and
    -- appearance belong to the editable Global UI XML.
    local hasOverlay = false
    for _, node in ipairs(xml) do
        if node.attributes and node.attributes.id == "MTG_ShortcutsOverlay" then
            hasOverlay = true
            break
        end
    end
    if not hasOverlay then
        table.insert(xml, Settings.shortcutsOverlay())
        changed = true
    end

    if not found then
        table.insert(xml, Settings.tabbedPanel())
        changed = true
        print("MTG Helper: created tabbed EDH Settings UI.")
    end
    if changed then UI.setXmlTable(xml) end
    -- Runtime UI may be rebuilding after setXmlTable; defer panel reset.
    Wait.frames(function()
        UI.setAttribute("CounterVisibilityPanel", "active", "false")
        Settings.applyShortcutsVisibility()
    end, 4)
end

function Settings.ready()
    Settings.createButton()
    Settings.ensureNotebookTab()
    Settings.installUI()
    Settings.applyPreview()
    Settings.applyAll(true)
    Wait.time(function() Settings.applyAll(false) end, 3.0, -1)
    print("MTG Portable Helper: EDH Settings module ready.")
end

