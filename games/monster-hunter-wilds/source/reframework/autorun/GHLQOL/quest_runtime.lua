-- SPDX-License-Identifier: GPL-3.0-or-later
-- REFramework equivalent of CE record 2168 / IsTargetAllClearHook.CEA.
-- The original method runs normally; only a confirmed current-quest request
-- may replace its Boolean result. No offsets, executable patches or CE runtime.
local Finish = require("GHLQOL.finish_quest")
local M = {}

function M.new()
    local ready = false
    local function boolean(obj, method)
        local value = obj:call(method)
        assert(type(value) == "boolean", method .. " did not return a Boolean")
        return value
    end
    local function snapshot()
        local s = { allowed = false }
        local mm = sdk.get_managed_singleton("app.MissionManager")
        if not mm then s.reason = "Waiting for the game"; return s end
        local director = mm:call("get_QuestDirector")
        if not director then s.reason = "No quest director"; return s end
        s.director = director:get_address()
        s.completed = boolean(mm, "get_IsQuestSuccessFreePlayTime") or boolean(director, "isQuestClearShowing")
        if s.completed or boolean(mm, "get_IsFixQuestFinish") or boolean(mm, "get_IsQuestResult") then
            s.reason = "Quest is already ending"; return s
        end
        if boolean(mm, "get_IsGoToLoadingQuest") or boolean(mm, "get_IsMissionRetryToObjUnloaded")
            or boolean(mm, "get_IsQuestJoinFailedLoading") then
            s.reason = "Quest is loading or changing"; return s
        end
        if not boolean(mm, "get_IsActiveQuest") or not boolean(mm, "get_IsPlayingQuest")
            or not boolean(director, "isPlayingQuest") then
            s.reason = "Start a quest first"; return s
        end
        local pm = sdk.get_managed_singleton("app.PlayerManager")
        local master = pm and pm:call("getMasterPlayer")
        local hunter = master and master:call("get_Character")
        if not hunter or not boolean(hunter, "get_IsMaster") then
            s.reason = "Local hunter is unavailable"; return s
        end
        -- Party quests are explicitly supported by the local request policy.
        -- Native quest completion remains responsible for network propagation.
        local quest = director:call("get_QuestData")
        local mission = director:call("getActiveMissionID")
        local started = director:call("get_QuestStartedTime")
        if not quest or type(mission) ~= "number" or mission < 0 or type(started) ~= "number" or started <= 0 then
            s.reason = "Quest identity is not ready"; return s
        end
        s.token = table.concat({tostring(s.director), tostring(quest:get_address()), tostring(mission), tostring(started)}, ":")
        s.allowed, s.reason = true, "Ready"
        return s
    end
    local Q = Finish.new({ snapshot = snapshot, ready = function() return ready end })
    local validating, logged_request = {}, nil
    local ok, err = pcall(function()
        assert(thread and thread.get_hook_storage and thread.get_id, "Thread-local hook storage is unavailable")
        local td = assert(sdk.find_type_definition("app.cQuestDirector"), "Quest director type missing")
        local method = assert(td:get_method("isTargetClearAll()"), "isTargetClearAll() missing")
        assert(method:get_return_type():get_full_name() == "System.Boolean", "Quest predicate signature changed")
        sdk.hook(method, function(args)
            local storage = thread.get_hook_storage()
            storage.ghl_finish_director = nil
            if Q.status.armed and not validating[thread.get_id()] then
                local read, address = pcall(function() return sdk.to_managed_object(args[2]):get_address() end)
                if read then storage.ghl_finish_director = address end
            end
        end, function(retval)
            local address = thread.get_hook_storage().ghl_finish_director
            if not address then return retval end
            local id = thread.get_id()
            validating[id] = true
            local read, override = pcall(Q.override, address)
            validating[id] = nil
            if not read then
                Q.reset()
                Q.status.last_error = tostring(override):sub(1, 1000)
                log.warn("[GHLQOL] Finish Quest validation failed; request disabled")
                return retval
            end
            if override then
                if logged_request ~= Q.status.requests then
                    logged_request = Q.status.requests
                    log.info("[GHLQOL] Finish Quest: current quest clear condition requested")
                end
                return sdk.to_ptr(1)
            end
            return retval
        end)
        ready = true
    end)
    Q.status.hook_ready = ready
    if not ok then
        Q.status.hook_error = tostring(err):sub(1, 2000)
        log.warn("[GHLQOL] Finish Quest unavailable: " .. Q.status.hook_error)
    end
    re.on_script_reset(Q.reset)
    return Q
end

return M
