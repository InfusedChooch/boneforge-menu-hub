-- SPDX-License-Identifier: GPL-3.0-or-later
-- Adapt the QOL release through its RefShell tab API.
local M = {}
local Presentation = require("GHLQOL.presentation")

function M.load(start, core, quest, pages)
    local original_require = require
    local factories, captured = {}, nil
    local ok, err = xpcall(function()
        _G.require = function(name, ...)
            local results = table.pack(original_require(name, ...))
            local shell = results[1]
            if name == "refshell" and type(shell) == "table" and not factories[shell] then
                local create = assert(shell.create, "RefShell.create is missing")
                factories[shell] = create
                shell.create = function(opts)
                    if opts and opts.id == "mhwilds" then
                        assert(not captured, "QOL created more than one main menu")
                        local options = {}
                        for k, v in pairs(opts) do options[k] = v end
                        options.title = "GHL QOL 0.0.23"
                        captured = create(options)
                        return captured
                    end
                    return create(opts)
                end
            end
            return table.unpack(results, 1, results.n)
        end
        start()
        assert(captured and type(captured.add_tab) == "function", "QOL main menu was not captured")
    end, debug.traceback)
    _G.require = original_require
    for shell, create in pairs(factories) do shell.create = create end
    if not ok then error(err, 0) end

    local menu = captured
    if quest then
        local section = menu.ui.section
        menu.ui.section = function(title, draw, ...)
            if title ~= "Quick Actions" then return section(title, draw, ...) end
            return section(title, function(...)
                draw(...)
                imgui.separator()
                quest.draw(menu.ui, menu)
            end, ...)
        end
    end
    local selected = menu.tabs[menu.active_tab]
    local settings
    for i, tab in ipairs(menu.tabs) do
        if tab.name == "Settings" then settings = table.remove(menu.tabs, i); break end
    end
    for _, page in ipairs(pages or {}) do
        local existing
        for _, tab in ipairs(menu.tabs) do if tab.name == page.name then existing = tab; break end end
        if existing then
            local original_draw, extra_draw = existing.draw, page.draw
            existing.draw = function(ui, current, ...)
                original_draw(ui, current, ...)
                extra_draw(ui, current, ...)
            end
        else menu:add_tab(page.name, page.draw) end
    end
    local function parry_page(method, id)
        return function()
            imgui.push_id(id)
            local drawn, draw_err = pcall(Presentation.draw,function()core[method](menu.ui)end,menu.cfg.width)
            imgui.pop_id()
            if not drawn then
                core.status.menu_error = tostring(draw_err):sub(1, 2000)
                log.error("[GHLQOL] Parry menu: " .. core.status.menu_error)
                imgui.text("Parry menu error; see re2_framework_log.txt")
            end
        end
    end
    menu.parry = {
        great_sword = parry_page("draw_great_sword", "GHLQOLParryGreatSword"),
        evade_parry = parry_page("draw_evade_parry", "GHLQOLParryShared"),
    }
    if settings then
        local draw_settings = settings.draw
        settings.draw = function(ui, current, ...)
            local profiles = package.loaded["GHLQOL.profiles"]
            if profiles and profiles.status.active then profiles.draw(ui, current) end
            return draw_settings(ui, current, ...)
        end
        menu.tabs[#menu.tabs + 1] = settings
    end
    for i, tab in ipairs(menu.tabs) do if tab == selected then menu.active_tab = i; break end end
    core.status.window.host = "GHL QOL 0.0.23"
    return menu
end

return M
