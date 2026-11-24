-- SPDX-License-Identifier: GPL-3.0-or-later
-- Capture only menu registrations while an existing engine starts. Gameplay,
-- reset and config-save callbacks remain registered with REFramework normally.
local M = {}

function M.load(name, start)
    local component = { name = name, loaded = false, callbacks = {}, error = nil }
    local register = re.on_draw_ui
    local ok, err = xpcall(function()
        re.on_draw_ui = function(callback)
            assert(type(callback) == "function", "Menu registration must be a function")
            component.callbacks[#component.callbacks + 1] = callback
        end
        start()
    end, debug.traceback)
    re.on_draw_ui = register
    component.loaded = ok
    if not ok then
        component.error = tostring(err):sub(1, 2000)
        log.error("[ParryMeister] " .. name .. " initialization failed: " .. component.error)
    end
    return component
end

function M.dll(name)
    return M.load(name, function()
        local getter = __sl_entries and __sl_entries[name]
        assert(type(getter) == "function", name .. ".dll entry is missing; retain the original installed DLL")
        local main = getter()
        assert(type(main) == "function", name .. " returned an invalid entry")
        main()
    end)
end

-- Flatten the engine's outer tree into our page. Preserve nested groups and
-- restore both APIs and the native tree stack even if its callback fails.
function M.draw_inline(callback, id)
    local tree, pop = imgui.tree_node, imgui.tree_pop
    local stack, first = {}, true
    imgui.push_id(id or "PMEngine")
    local ok, err = xpcall(function()
        imgui.tree_node = function(...)
            if first then
                first = false
                stack[#stack + 1] = false
                return true
            end
            local open = tree(...)
            if open then stack[#stack + 1] = true end
            return open
        end
        imgui.tree_pop = function()
            assert(#stack > 0, "Unbalanced engine menu tree")
            local native = table.remove(stack)
            if native then pop() end
        end
        callback()
    end, debug.traceback)
    imgui.tree_node, imgui.tree_pop = tree, pop
    for i = #stack, 1, -1 do if stack[i] then pop() end end
    imgui.pop_id()
    if not ok then error(err, 0) end
end

return M
