-- =============================================================
-- MODULE 5/5: ORIGINAL MOON-MTG EQUIPMENT (ENCODER-BASED)
-- Source: moon-mtg-equip v1.0.4 from the supplied standalone script.
-- Original Encoder attachment/unequip mechanics preserved.
-- Both equipment controls are now visible only while hovered.
-- =============================================================

local Equipment = {}
local function equipmentAlive(obj)
    if obj == nil then return false end
    local ok, valid = pcall(function() return obj.isDestroyed() == false end)
    return ok and valid == true
end

--[[--
moon-mtg-equip (tag-aware, menu-safe, high-visibility hover button)
Original equipment logic: stella + Lilith / stella.lifeless.space

WHY THE CONTROL MOVED:
Tabletop Simulator cannot remove one specific object context-menu item.
Object.clearContextMenu() would also remove custom menu options installed
by other MTG scripts (Draw Random, Cascade, Reveal, etc.).

This version NEVER adds an 'equip all to top' context-menu entry.
Instead it shows a large, high-contrast 'EQUIP ALL' button on hover over
an eligible Deck; the button disappears on leaving the deck or on entering
an Exile/Library/Graveyard tagged area. Other scripts' menus are untouched.

Tags can be on the Deck, a Scripting Zone, or a snap point.
Tagged snap points are detected by proximity (configurable radius below).
Reload scripts with Save & Play to discard old context-menu entries.
--]]--

local prop_id = "moon-mtg-equip"
local equipment_version = "1.0.4"

local EXCLUDED_TAGS = { "Exile", "Library", "Graveyard" }
local EXCLUDED_LOOKUP = { exile = true, library = true, graveyard = true }
local BUTTON_MARKER = "moon-mtg-equip / equip all to top"
local PROTECTED_SNAP_RADIUS = 0.85 -- TTS world units; adjust if needed
local protectedSnapPositions = {}

-- High-visibility hover button appearance. Adjust these settings to taste.
-- The button only appears on eligible Decks while hovered.
local EQUIP_BUTTON_STYLE = {
    label = "EQUIP ALL",
    position = {0, 0.38, -0.8},
    scale = {0.63, 0.63, 0.63},
    width = 980,
    height = 300,
    font_size = 155,
    color = {1.0, 0.73, 0.12, 1.0},       -- bright amber/gold
    font_color = {0.08, 0.06, 0.02, 1.0}, -- dark text for contrast
    hover_color = {1.0, 0.88, 0.33, 1.0},
    press_color = {0.79, 0.48, 0.04, 1.0},
}

-- player color -> hovered Deck/Card GUID; only hovered objects get buttons
local hovered = {}

local function has_protected_tag(obj)
    if obj == nil then return false end
    local ok, tags = pcall(function() return obj.getTags() end)
    if not ok or type(tags) ~= "table" then return false end
    for _, tag in ipairs(tags) do
        if EXCLUDED_LOOKUP[string.lower(tostring(tag))] then
            return true
        end
    end
    return false
end

local function is_protected_tag_list(tags)
    for _, tag in ipairs(tags or {}) do
        if EXCLUDED_LOOKUP[string.lower(tostring(tag))] then return true end
    end
    return false
end

-- Snap points are separate from scripting zones. In particular, putting a
-- deck onto a tagged snap point does NOT apply that tag to the Deck.
-- Cache them once at load to avoid scanning every object on each hover.
local function collect_protected_snap_points()
    protectedSnapPositions = {}

    local function collect(owner)
        local ok, points = pcall(function() return owner.getSnapPoints() end)
        if not ok or type(points) ~= "table" then return end

        for _, point in ipairs(points) do
            if is_protected_tag_list(point.tags) then
                local pos = point.position
                if owner ~= Global then
                    pos = owner.positionToWorld(point.position)
                end
                table.insert(protectedSnapPositions, pos)
            end
        end
    end

    collect(Global)
    for _, obj in ipairs(getObjects()) do collect(obj) end
end

local function near_protected_snap_point(deck)
    local pos = deck.getPosition()
    local px, pz = pos.x or pos[1], pos.z or pos[3]
    local r2 = PROTECTED_SNAP_RADIUS * PROTECTED_SNAP_RADIUS
    for _, snap in ipairs(protectedSnapPositions) do
        local sx, sz = snap.x or snap[1], snap.z or snap[3]
        if sx and sz then
            local dx, dz = px - sx, pz - sz
            if dx*dx + dz*dz <= r2 then return true end
        end
    end
    return false
end

local function deck_is_excluded(deck)
    if deck == nil or deck.tag ~= "Deck" then return false end
    if has_protected_tag(deck) or near_protected_snap_point(deck) then return true end

    -- Scripting zones TTS reports for this object.
    for _, zone in ipairs(deck.getZones() or {}) do
        if has_protected_tag(zone) then return true end
    end

    -- getZones() is tag-filtered. Check tagged scripting zones with
    -- getObjects(true) so an untagged deck doesn't get missed.
    for _, candidate in ipairs(getObjectsWithAnyTags(EXCLUDED_TAGS)) do
        if candidate.tag == "Scripting" or candidate.type == "Scripting" then
            local ok, occupants = pcall(function()
                return candidate.getObjects(true)
            end)
            if ok and type(occupants) == "table" then
                for _, occupant in ipairs(occupants) do
                    if occupant == deck then return true end
                end
            end
        end
    end

    return false
end

-- Encoder API wrapper -----------------------------------------------------
local encoder
do
    local mt = {
        __index = function(self, index)
            return function(args)
                return rawget(self, "object").call("API" .. index, args)
            end
        end
    }

    encoder = function()
        local object = Global.getVar("Encoder")
        return object ~= nil and setmetatable({ object = object }, mt) or nil
    end
end

local function register_module()
    local enc = encoder()
    if enc == nil then return end

    local v = tostring(enc.object.getVar("version") or "")
    local major, minor = v:match("^(%d+)%.(%d+)")
    major, minor = tonumber(major), tonumber(minor)
    if not major or major < 4 or (major == 4 and minor < 4) then
        broadcastToAll("encoder version must be >=4.4", {1, 0, 0, 1})
        error("bad encoder version")
    end

    enc.registerProperty {
        propID = prop_id,
        name = "Manage Equipment",
        values = { "moon_mtg_equip" },
        tags = "basic,counter",
        visible = false,
        visible_in_hand = 0,
        funcOwner = self,
        activateFunc = "",
    }

    enc.registerValue {
        valueID = "moon_mtg_equip",
        validType = "nil",
        desc = "who up describing they values (when are these ever used)",
        default = {},
    }
end

local function init_card(card)
    if card == nil or card.tag ~= "Card" then return end
    if card.getVar("noencode") == true then return end

    local enc = encoder()
    if enc == nil then return end

    if not enc.objectExists { obj = card } then
        enc.encodeObject { obj = card }
    end
    if not enc.propertyExists { propID = prop_id } then return end

    if not enc.objIsPropEnabled { obj = card, propID = prop_id } then
        enc.objEnableProp { obj = card, propID = prop_id }
        enc.rebuildButtons { obj = card }
    end
end

local function equipped_offset(i)
    local col = math.floor(i / 3)
    local row = i % 3
    return Vector(-1.65 - 1.15 * col, 0.05 + row * (-0.05 / 3),
                  -0.75 + row * (2.2 / 3))
end

local function equip_to(deck, to)
    local enc = encoder()
    if enc == nil then return end

    local data = enc.objGetPropData { obj = to, propID = prop_id }
    local angles = to.getRotation()

    while deck ~= nil and (deck.tag == "Card" or #deck.getObjects() > 0) do
        local card
        if deck.tag == "Card" then
            card = deck
            deck = nil
        else
            card = deck.takeObject {
                position = deck.getPosition(),
                top = true,
                smooth = false,
            }
            deck = deck.remainder or deck
        end

        card.setPosition(to.positionToWorld(equipped_offset(#data.moon_mtg_equip)))
        card.setRotation(angles, false, false)
        card.setScale({0.475, 0.475, 0.475})
        card.locked = true
        to.addAttachment(card)
        table.insert(data.moon_mtg_equip, #to.getAttachments())
    end

    enc.objSetPropData { obj = to, propID = prop_id, data = data }
end

-- This is the exact same equip action, invoked by a hover button.
function equip_hovered_deck(deck, player_color, alt_click)
    if deck == nil or deck.tag ~= "Deck" then return end
    if deck_is_excluded(deck) then
        printToColor("Equipment disabled for Exile, Library and Graveyard.",
                     player_color, {1, 0.7, 0.2})
        return
    end

    local card = deck.takeObject {
        position = deck.getPosition() + Vector(0, 1, 0),
        top = true,
    }
    if card == nil then return end
    local remaining = deck.remainder or deck

    init_card(card)
    equip_to(remaining, card)
end

-- A specific classic UI button CAN be removed safely by index.
-- Other scripted buttons and all context-menu items are preserved.
local function find_equip_button(deck)
    for _, b in ipairs(deck.getButtons() or {}) do
        if b.tooltip == BUTTON_MARKER then return b.index end
    end
    return nil
end

local function remove_equip_button(deck)
    local index = find_equip_button(deck)
    if index ~= nil then deck.removeButton(index) end
end

local function is_hovered(guid)
    for _, other_guid in pairs(hovered) do
        if other_guid == guid then return true end
    end
    return false
end

local function refresh_deck(deck)
    if deck == nil or deck.tag ~= "Deck" then return end

    if not is_hovered(deck.getGUID()) or deck_is_excluded(deck) then
        remove_equip_button(deck)
        return
    end

    if find_equip_button(deck) ~= nil then return end
    deck.createButton {
        click_function = "equip_hovered_deck",
        function_owner = self,
        label = EQUIP_BUTTON_STYLE.label,
        tooltip = BUTTON_MARKER,
        position = EQUIP_BUTTON_STYLE.position,
        rotation = {0, 0, 0},
        scale = EQUIP_BUTTON_STYLE.scale,
        width = EQUIP_BUTTON_STYLE.width,
        height = EQUIP_BUTTON_STYLE.height,
        font_size = EQUIP_BUTTON_STYLE.font_size,
        font_color = EQUIP_BUTTON_STYLE.font_color,
        color = EQUIP_BUTTON_STYLE.color,
        hover_color = EQUIP_BUTTON_STYLE.hover_color,
        press_color = EQUIP_BUTTON_STYLE.press_color,
    }
end

local function refresh_deck_later(deck)
    if not equipmentAlive(deck) then return end
    local ok, guid = pcall(function()
        if deck.tag == "Deck" then return deck.getGUID() end
    end)
    if not ok or not guid then return end
    Wait.frames(function()
        local current = getObjectFromGUID(guid)
        if equipmentAlive(current) then pcall(refresh_deck, current) end
    end, 2)
end

-- Encoder button (for equipped cards) -----------------------------------
-- Leave Encoder responsible for equipment data and button rebuilds.
-- Only toggle this one button using the same hover state as EQUIP ALL.
local function find_unequip_button(card)
    for _, b in ipairs(card.getButtons() or {}) do
        if b.click_function == "unequip_all" and b.tooltip == "unequip all" then
            return b.index
        end
    end
    return nil
end

local function remove_unequip_button(card)
    local index = find_unequip_button(card)
    if index ~= nil then card.removeButton(index) end
end

local function refresh_equipped_card(card)
    if card == nil or card.tag ~= "Card" then return end
    if not is_hovered(card.getGUID()) then
        remove_unequip_button(card)
        return
    end
    if find_unequip_button(card) ~= nil then return end

    local enc = encoder()
    if enc == nil then return end
    -- Hover events also fire on unencoded cards. Never query property data
    -- until Encoder confirms this card has the equipment property enabled.
    if not enc.objectExists { obj = card } then return end
    if not enc.propertyExists { propID = prop_id } then return end
    if not enc.objIsPropEnabled { obj = card, propID = prop_id } then return end

    local flip = enc.getFlip { obj = card } or 1
    if flip == -1 then return end
    local equipped = enc.objGetPropData { obj = card, propID = prop_id }
    if type(equipped) ~= "table" or type(equipped.moon_mtg_equip) ~= "table"
        or #equipped.moon_mtg_equip == 0 then return end

    card.createButton {
        label = "unequip all",
        position = {0, 0.28, 0},
        rotation = {0, 0, 0},
        scale = {0.5, 0.5, 0.5},
        width = 800,
        height = 300,
        font_size = 125,
        font_color = {1, 1, 1},
        color = {0.1, 0.1, 0.1},
        tooltip = "unequip all",
        click_function = "unequip_all",
        function_owner = self,
    }
end

-- Encoder calls this during its button rebuilds. It must not create an
-- UNEQUIP ALL button unless the card is currently being hovered.
function createButtons(params)
    if params == nil then return end
    refresh_equipped_card(params.obj)
end

-- Check only hovered objects for missing buttons after a rebuild or move.
-- This avoids scanning/encoding every card and preserves deck tag checks.
local function refresh_hovered_decks()
    local seen = {}
    for _, guid in pairs(hovered) do
        if guid and not seen[guid] then
            seen[guid] = true
            local obj = getObjectFromGUID(guid)
            if equipmentAlive(obj) then
                pcall(function()
                    if obj.tag == "Deck" then
                        refresh_deck(obj)
                    elseif obj.tag == "Card" then
                        refresh_equipped_card(obj)
                    end
                end)
            end
        end
    end
    Wait.time(refresh_hovered_decks, 0.5)
end

function unequip_all(obj, ply)
    local enc = encoder()
    if enc == nil then return end

    local equipped = enc.objGetPropData { obj = obj, propID = prop_id }
    if #equipped.moon_mtg_equip == 0 then return end

    local origin = obj.getPosition()
    obj.setPosition(origin + Vector(0, #equipped.moon_mtg_equip + 1, 0))

    for i = #equipped.moon_mtg_equip, 1, -1 do
        local new = obj.removeAttachment(equipped.moon_mtg_equip[i] - 1)
        new.setPosition(origin + Vector(0, #equipped.moon_mtg_equip - i + 1, 0))
        new.setScale({1, 1, 1})
        new.locked = false
    end

    enc.objSetPropData {
        obj = obj,
        propID = prop_id,
        data = { moon_mtg_equip = {} },
    }
    remove_unequip_button(obj)
end

-- Events -----------------------------------------------------------------
function Equipment.load()
    self.addContextMenuItem("Register Module", register_module)
    Wait.condition(register_module, function()
        return Global.getVar("Encoder") ~= nil
    end, 30)

    -- Clean only this module's old buttons, never other mods' buttons/menus.
    Wait.frames(function()
        collect_protected_snap_points()
        for _, obj in ipairs(getObjects()) do
            if equipmentAlive(obj) then
                pcall(function()
                    if obj.tag == "Deck" then
                        remove_equip_button(obj)
                    elseif obj.tag == "Card" then
                        remove_unequip_button(obj)
                    end
                end)
            end
        end
        refresh_hovered_decks()
    end, 10)
end

function Equipment.onHover(player_color, obj)
    local old_guid = hovered[player_color]
    local new_guid = nil
    if equipmentAlive(obj) then
        local ok, guid, kind = pcall(function()
            return obj.getGUID(), obj.tag
        end)
        if ok and (kind == "Deck" or kind == "Card") then new_guid = guid end
    end
    hovered[player_color] = new_guid
    if old_guid ~= nil and old_guid ~= new_guid and not is_hovered(old_guid) then
        local previous = getObjectFromGUID(old_guid)
        if equipmentAlive(previous) then
            pcall(function()
                if previous.tag == "Deck" then
                    remove_equip_button(previous)
                elseif previous.tag == "Card" then
                    remove_unequip_button(previous)
                end
            end)
        end
    end
    if new_guid ~= nil then
        pcall(function()
            if obj.tag == "Deck" then refresh_deck(obj)
            else refresh_equipped_card(obj) end
        end)
    end
end

function Equipment.onDrop(player_color, obj)
    if obj == nil then return end
    local ok, guid, kind = pcall(function()
        return obj.getGUID(), obj.tag
    end)
    if not ok or not guid or (kind ~= "Deck" and kind ~= "Card") then return end

    -- Multiple loose cards dropped on a library are consumed by TTS while
    -- merging. Avoid sending a destroyed Card reference to Encoder.
    Wait.frames(function()
        local current = getObjectFromGUID(guid)
        if not equipmentAlive(current) then return end
        pcall(function()
            if current.tag == "Card" then
                init_card(current)
                refresh_equipped_card(current)
            elseif current.tag == "Deck" then
                refresh_deck(current)
            end
        end)
    end, 2)
end

function Equipment.onEnterZone(zone, obj)
    if equipmentAlive(obj) then refresh_deck_later(obj) end
end

function Equipment.onLeaveZone(zone, obj)
    if equipmentAlive(obj) then refresh_deck_later(obj) end
end

function Equipment.onSpawn(obj)
    if equipmentAlive(obj) then refresh_deck_later(obj) end
end


