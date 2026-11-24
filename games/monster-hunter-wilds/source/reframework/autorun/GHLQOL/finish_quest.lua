-- SPDX-License-Identifier: GPL-3.0-or-later
-- One confirmed request for one quest. Runtime snapshots fail closed.
local M = {}

function M.new(opts)
    local clock = opts.clock or os.clock
    local pending, used_token = nil, nil
    local Q = { status = { state = "Idle", requests = 0, overrides = 0, completions = 0, armed = false } }
    local function stop(reason)
        pending = nil
        Q.status.armed, Q.status.state = false, reason
    end
    function Q.inspect()
        local ok, snapshot = pcall(opts.snapshot)
        if not ok or type(snapshot) ~= "table" then
            return { allowed = false, reason = "Cannot read quest state" }
        end
        return snapshot
    end
    function Q.arm(token)
        local s = Q.inspect()
        if not opts.ready() then return false, "Quest hook is unavailable" end
        if pending then return false, "A finish request is already pending" end
        if not s.allowed then return false, s.reason end
        if type(token) ~= "string" or not s.director then return false, "Quest identity unavailable" end
        if s.token ~= token then return false, "Quest changed; confirm again" end
        if used_token == token then return false, "Finish already requested for this quest" end
        pending = { token = token, director = s.director, deadline = clock() + 10 }
        Q.status.requests = Q.status.requests + 1
        Q.status.armed, Q.status.state = true, "Waiting for the quest clear check"
        return true
    end
    function Q.tick()
        if not pending then return end
        if not opts.ready() then stop("Quest hook unavailable; request disabled"); return end
        local s = Q.inspect()
        if s.completed and s.director == pending.director then
            Q.status.completions = Q.status.completions + 1
            stop("Quest entered completion flow")
        elseif clock() >= pending.deadline then stop("Timed out; request disabled")
        elseif not s.allowed then stop("Stopped: " .. tostring(s.reason))
        elseif s.token ~= pending.token then stop("Stopped: quest changed") end
    end
    function Q.override(director)
        Q.tick()
        if not pending then return false end
        local s = Q.inspect()
        if not s.allowed or s.token ~= pending.token or director ~= pending.director or director ~= s.director then
            return false
        end
        used_token = pending.token
        Q.status.overrides = Q.status.overrides + 1
        Q.status.state = "Clear condition requested; waiting for native completion"
        return true
    end
    function Q.reset() stop("Script reset; request disabled") end
    function Q.draw(ui, menu)
        local s = Q.inspect()
        local available = opts.ready() and s.allowed and not pending and used_token ~= s.token
        imgui.begin_disabled(not available)
        local ok, err = pcall(ui.actions, {{ "Finish Quest", function()
            local before = Q.inspect()
            if not before.allowed then menu:toast(before.reason, "warning", 2000); return end
            local token = before.token
            ui.confirm({ title = "Finish current quest?",
                lines = { "Complete the current quest through the normal result flow?", "Can affect everyone in this quest, including your party." },
                yes = "Finish Quest", no = "Cancel", on_yes = function()
                    local armed, reason = Q.arm(token)
                    menu:toast(armed and "Finish requested for this quest" or reason, armed and "success" or "warning", 2000)
                end })
        end }}, 1)
        imgui.end_disabled()
        if not ok then error(err, 0) end
        if not opts.ready() then ui.muted("Finish Quest unavailable: " .. tostring(Q.status.hook_error or "API not ready"))
        elseif not s.allowed then ui.muted("Finish Quest: " .. tostring(s.reason))
        else ui.muted("Finish Quest: " .. Q.status.state) end
    end
    return Q
end

return M
