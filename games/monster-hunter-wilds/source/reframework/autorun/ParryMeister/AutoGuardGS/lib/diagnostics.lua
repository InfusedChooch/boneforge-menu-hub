-- Local AutoGuardGS diagnostic export. Game writes remain in reframework/data.
local M = {}

function M.new(opts)
    local clock = opts.clock or os.clock
    local records, hits = {}, {}
    local started = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local session = os.date("!%Y%m%dT%H%M%SZ") .. "-" .. tostring(math.floor(clock() * 1000))
    local next_dump, warned = 0, false
    local D = { status = "Waiting for first dump" }

    local function push(list, item, limit)
        if #list >= limit then table.remove(list, 1) end
        list[#list + 1] = item
    end

    function D.record(level, text)
        push(records, { time_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"), level = level, text = tostring(text):sub(1, 2000) }, 100)
    end

    function D.hit(reason, detail)
        push(hits, { time_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"), reason = reason, detail = tostring(detail):sub(1, 2000) }, 200)
    end

    function D.tick(guard, force)
        local now = clock()
        if not force and now < next_dump then return end
        next_dump = now + 5
        local ok, result = pcall(function()
            return json.dump_file("AutoGuardGS-diagnostics.json", {
                schema_version = 1, session_id = session, started_utc = started,
                updated_utc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                mod = "Parry Meister v0.4.0 (predictive tackle and unified controls)",
                integration = _G.__parry_meister_status,
                guard_ready = guard.ready, last_hit = guard.last_hit,
                config = opts.config, counters = opts.stats,
                forecast = D.forecast, tackle = guard.tackle_status,
                recent_hits = hits, recent_logs = records,
            }, 2)
        end)
        if not ok or result ~= true then
            D.status = "Diagnostic dump failed (see REFramework log)"
            if not warned then
                warned = true
                log.warn("[AutoGuardGS] diagnostic dump failed: " .. tostring(result))
            end
            return
        end
        D.status = "Diagnostics saved automatically every 5 seconds"
        warned = false
    end

    return D
end

return M
