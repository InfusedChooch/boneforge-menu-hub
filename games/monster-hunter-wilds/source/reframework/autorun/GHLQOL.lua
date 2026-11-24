-- SPDX-License-Identifier: GPL-3.0-or-later
-- Single loader for the private GHL QOL 0.0.23 consolidated package.
if _G.__ghl_qol_loaded then return end
_G.__ghl_qol_loaded = true

local status = { name = "GHL QOL", version = "0.0.23", loaded = false, tabs = {} }
status.storage = rawget(_G, "__ghl_storage_status")
status.embedded = rawget(_G, "__ghl_embedded_status")
status.profiles = rawget(_G, "__ghl_profiles_status")
status.runtime = rawget(_G, "__ghl_runtime")
_G.__ghl_qol_status = status
local core = require("ParryMeister.core")
local Host = require("GHLQOL.host")
local quest = require("GHLQOL.quest_runtime").new()
local features = require("GHLQOL.features")
status.finish_quest = quest.status
status.features = features.status
local ok, menu = xpcall(function()
    return Host.load(function() require("GHLQOL.vendor.mhwilds_qol") end, core, quest, features.pages)
end, debug.traceback)
status.loaded = ok
if ok then
    status.native_menu = require("GHLQOL.native_bridge").attach(menu)
    for _, tab in ipairs(menu.tabs) do status.tabs[#status.tabs + 1] = tab.name end
    log.info("[GHLQOL] 0.0.23 loaded; Parry Meister attached to Weapons")
else
    status.error = tostring(menu):sub(1, 2000)
    log.error("[GHLQOL] initialization failed: " .. status.error)
    re.on_draw_ui(function() imgui.text("GHL QOL startup failed; see re2_framework_log.txt") end)
end

local next_dump = 0
re.on_frame(function()
    quest.tick()
    features.tick()
    local window = core.status.window
    window.open = ok and menu.cfg.open == true or false
    local active = ok and menu.tabs[menu.active_tab]
    local weapons = features.status.weapons
    window.visible = window.open and active and active.name == "Weapons" and weapons and weapons.parry_visible == true or false
    status.menu_open, status.active_tab = window.open, active and active.name or nil
    status.parry_render_count = window.render_count
    if os.clock() < next_dump then return end
    next_dump = os.clock() + 5
    local cursor = rawget(_G, "refcursor")
    if type(cursor) == "table" and type(cursor.status) == "function" then
        local cursor_ok, cursor_status = pcall(cursor.status)
        if cursor_ok and type(cursor_status) == "table" then status.cursor = cursor_status end
    end
    status.updated_utc = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local dumped, result = pcall(json.dump_file, "GHLQOL-status.json", status, 2)
    if not dumped or result ~= true then
        if not status.dump_error then log.warn("[GHLQOL] status export failed") end
        status.dump_error = tostring(result)
    else
        status.dump_error = nil
    end
end)
