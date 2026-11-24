-- SPDX-License-Identifier: GPL-3.0-or-later
-- Parry Meister: a local unified interface for the three installed engines.
-- Original authorship and licenses are retained in the accompanying sources.
if _G.__parry_meister_core then return _G.__parry_meister_core end
_G.__parry_meister_loaded = true

local VERSION = "0.4.0"
local Bridge = require("ParryMeister.bridge")
local Ui = require("ParryMeister.AutoGuardGS.lib.ui")
local status = { name = "Parry Meister", version = VERSION, components = {} }
_G.__parry_meister_status = status

local defense
local automatic = Bridge.load("Greatsword automatic defense", function()
    defense = require("ParryMeister.auto_guard")
    assert(type(defense) == "table" and type(defense.draw) == "function", "Invalid defense module")
end)
local enhancements = Bridge.dll("WpSeries_GreatSword")
local windows = Bridge.dll("GenSeries_ParryWindow")
local components = { automatic, enhancements, windows }

for _, component in ipairs(components) do
    component.status = {
        name = component.name, loaded = component.loaded,
        menu_callbacks = #component.callbacks, error = component.error,
    }
    status.components[#status.components + 1] = component.status
    if component.loaded then
        log.info(string.format("[ParryMeister] %s loaded; captured %d menu callbacks", component.name, #component.callbacks))
    end
end

local function menu_error(err)
    status.menu_error = tostring(err):sub(1, 2000)
    log.error("[ParryMeister] menu error: " .. status.menu_error)
end
local U = Ui.new({ retry = 2, on_error = menu_error })

local function draw_component(component)
    if not component.loaded then
        imgui.text(component.name .. ": failed to start; see log and integration status")
        return
    end
    if #component.callbacks == 0 then
        imgui.text(component.name .. ": engine started, but no menu was captured; see integration status")
        return
    end
    for index, callback in ipairs(component.callbacks) do
        U.part(component.name .. index, function() Bridge.draw_inline(callback, component.name .. index) end)
    end
end

local function draw_great_sword(ui)
    if ui then
        ui.section("Automatic defense",function()
            if defense and automatic.loaded then U.part("defense",defense.draw) else draw_component(automatic) end
        end,true)
        ui.section("Great Sword enhancements",function()
            ui.muted("Guard angle is controlled above. Perfect-guard and parry timing are in Weapons > Evade / Parry.")
            draw_component(enhancements)
        end,false)
        return
    end
    imgui.text("Automatic defense")
    if defense and automatic.loaded then
        U.part("defense", defense.draw)
    else
        draw_component(automatic)
    end
    imgui.separator()
    imgui.text("Greatsword enhancements")
    imgui.text("Timing is in Weapons > Evade / Parry; leave enhancement perfect-guard/parry extensions off.")
    imgui.text("Guard angle is controlled above; leave the enhancement guard-angle override off.")
    draw_component(enhancements)
end

local function draw_evade_parry(ui)
    if ui then
        ui.muted("Adjust perfect-guard and offset windows for the supported weapons below.")
        ui.muted("Automatic evade is not implemented. Great Sword's automatic guard, tackle and offset are in its weapon tab.")
        ui.section("Weapon parry timing",function()draw_component(windows)end,true)
        ui.section("Status and credits",function()
            for _,component in ipairs(components)do
                ui.muted(component.name..": "..(component.loaded and "Loaded" or "Unavailable"))
                if component.error then ui.muted(component.error)end
            end
            ui.muted("AutoGuardGS by GGG; native enhancement and timing engines retain their original authorship.")
        end,false)
        return
    end
    imgui.separator()
    imgui.text("Parry and perfect-guard timing (all supported weapons)")
    imgui.text("Automatic evade is not implemented; Great Sword automation is in its weapon tab.")
    draw_component(windows)
    imgui.separator()
    U.tree("Integration status and credits##PMStatus", function()
        for _, component in ipairs(components) do
            imgui.text(component.name .. ": " .. (component.loaded and "loaded" or "FAILED"))
            if component.error then imgui.text(component.error) end
        end
        imgui.text("Automatic guard/tackle/offset currently supports greatsword.")
        imgui.text("Other weapon counters can be added as separate engine adapters.")
        imgui.text("AutoGuardGS by GGG; original DLL engines retained unchanged.")
        imgui.text("Settings use the existing three configuration files.")
    end)
end

local core = { status = status }
status.window = { host = "GHL QOL 0.0.10", embedded = true, open = false, visible = false, render_count = 0 }
function core.draw_great_sword(ui)
    status.window.render_count = status.window.render_count + 1
    draw_great_sword(ui)
end
function core.draw_evade_parry(ui)
    status.window.render_count = status.window.render_count + 1
    draw_evade_parry(ui)
end
function core.draw(ui)
    status.window.render_count = status.window.render_count + 1
    draw_great_sword(ui)
    draw_evade_parry(ui)
end
_G.__parry_meister_core = core

local next_status = 0
re.on_frame(function()
    if os.clock() < next_status then return end
    next_status = os.clock() + 5
    status.updated_utc = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local ok, result = pcall(json.dump_file, "ParryMeister-status.json", status, 2)
    if not ok or result ~= true then
        if not status.dump_error then log.warn("[ParryMeister] could not write integration status") end
        status.dump_error = tostring(result)
    else
        status.dump_error = nil
    end
end)

log.info("[ParryMeister] v" .. VERSION .. " loaded")

return core
