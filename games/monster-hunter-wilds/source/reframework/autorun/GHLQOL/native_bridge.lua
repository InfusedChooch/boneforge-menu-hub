-- SPDX-License-Identifier: GPL-3.0-or-later
-- The native renderer shares the existing RefShell schedule and live menu table.
local M = {}

function M.attach(menu)
    if menu.__ghl_native_status then return menu.__ghl_native_status end
    local status = {available = false, enabled = false, backend = "Lua"}
    menu.__ghl_native_status = status
    local original = menu.draw_window
    if type(original) ~= "function" then
        status.error = "Window renderer unavailable"
        return status
    end
    local previous, blocked, last_state
    local function publish(available, enabled, err)
        status.available, status.enabled = available, enabled
        status.backend, status.error = enabled and "Native" or "Lua", err
        local state = tostring(available) .. ":" .. tostring(enabled) .. ":" .. tostring(err)
        if state ~= last_state then
            last_state = state
            local writer = log and log[err and "warn" or "info"]
            if writer then writer("[GHLQOL] " .. (err or (enabled and "Native menu active" or "Using Lua menu"))) end
        end
    end
    menu.draw_window = function(self, ...)
        local bridge = rawget(_G, "ghl_native")
        if bridge ~= previous then previous, blocked = bridge, nil end
        if type(bridge) ~= "table" or type(bridge.ready) ~= "function" or type(bridge.draw) ~= "function" then
            publish(false, false)
            return original(self, ...)
        end
        if blocked == bridge then return original(self, ...) end
        local ok, ready = pcall(bridge.ready)
        if not ok then
            blocked = bridge
            publish(false, false, tostring(ready):sub(1, 1000))
            return
        end
        if ready ~= true then
            publish(false, false)
            return original(self, ...)
        end
        local drawn, rendered, err = pcall(bridge.draw, self)
        if not drawn then
            blocked = bridge
            publish(true, false, tostring(rendered):sub(1, 1000))
            -- Native-owned scopes must unwind; never draw a second window now.
            return
        end
        if rendered == true then
            publish(true, true)
            return
        end
        -- Contract: false means no window was opened, so fallback is safe now.
        if rendered == false then
            if err ~= nil then blocked = bridge end
            publish(true, false, err ~= nil and tostring(err):sub(1, 1000) or nil)
            return original(self, ...)
        end
        blocked = bridge
        publish(true, false, "Native renderer returned an invalid result")
    end
    return status
end

return M
