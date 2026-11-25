-- SPDX-License-Identifier: GPL-3.0-or-later
-- Entry point for the public REFramework edition.
if rawget(_G, "__ghl_qol_loaded") then
    log.warn("[Boneforge Wilds] Another GHL QOL menu is active. Load one edition at a time.")
    return
end
_G.__ghl_qol_loaded = true

local names = {"Meals", "Buffs", "Extras", "Positions", "Map", "Inventory", "Hunter Journal"}
local modules = {"meals", "buffs", "extras", "positions", "teleporter_map", "inventory", "journal"}
local pages = {}
local active = 1
local menu = {}
local ui = {
    muted = imgui.text,
    button = imgui.button,
    toggle = imgui.checkbox,
    slider_float = imgui.slider_float,
}

function ui.section(label, draw)
    if imgui.collapsing_header(label) then draw() end
end

function ui.bind_combo(label, settings, key, rows)
    if #rows == 0 then return false end
    local labels, selected = {}, 1
    for index, row in ipairs(rows) do
        labels[index] = row[2]
        if row[1] == settings[key] then selected = index end
    end
    local changed, index = imgui.combo(label, selected, labels)
    if changed then settings[key] = rows[index][1] end
    return changed
end

function menu:toast(message)
    self.message = message
end

function ui.confirm(request)
    menu._confirm = request
end

for index, module in ipairs(modules) do
    local ok, page = pcall(function()
        local loaded = require("GHLQOL." .. module)
        if loaded.init then loaded.init() end
        return loaded
    end)
    if ok then
        pages[index] = page
    else
        local message = names[index] .. " could not start: " .. tostring(page)
        log.error("[Boneforge Wilds] " .. message)
        pages[index] = {draw = function() imgui.text(message) end}
    end
end

re.on_frame(function()
    for _, page in ipairs(pages) do
        if page.tick then page.tick() end
    end
end)

re.on_draw_ui(function()
    imgui.text("Boneforge Wilds")
    local changed, index = imgui.combo("Page##BoneforgeWilds", active, names)
    if changed then
        active = index
        menu._confirm, menu.message = nil, nil
    end
    pages[active].draw(ui, menu)
    local request = menu._confirm
    if request then
        imgui.separator()
        imgui.text(request.title)
        for _, line in ipairs(request.lines) do imgui.text(line) end
        if imgui.button(request.yes) then
            menu._confirm = nil
            request.on_yes()
        elseif imgui.button(request.no) then
            menu._confirm = nil
            request.on_no()
        end
    end
    if menu.message then imgui.text(menu.message) end
end)
