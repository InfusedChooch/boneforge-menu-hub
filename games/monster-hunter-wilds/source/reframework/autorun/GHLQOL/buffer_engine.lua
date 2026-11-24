-- Private adapter for the installed Buffer mechanics. No original global host.
local R=require("GHLQOL.runtime")
local M={status={modules={},hooks={},errors={}},context=nil}
local native_sdk,native_re=sdk,re
function M.external()
    return type(package.loaded["Buffer.Modules.Character"])=="table"
end
function M.active(owner)
    if M.external() then M.status.external_buffer=true;return false end
    M.status.external_buffer=nil
    return M.status.modules[owner]==true and not (M.blocked and M.blocked[owner]) and R.hunter()~=nil
end
local function failure(key,err)
    M.status.errors[key]=tostring(err):sub(1,1000)
    log.warn("[GHLQOL Buffer] "..key..": "..M.status.errors[key])
end
local serial=0
M.sdk=setmetatable({}, {__index=native_sdk})
function M.sdk.hook(method,pre,post,...)
    local extra=table.pack(...)
    serial=serial+1
    local owner=assert(M.context,"Buffer hook outside module initialization")
    local key=owner..":"..serial
    local ok,err=pcall(function()
        assert(method,"Managed method unavailable")
        native_sdk.hook(method,function(args)
            local storage=thread.get_hook_storage()
            storage[key]=M.active(owner) and not M.status.errors[key]
            if not storage[key] or not pre then return end
            local good,value=pcall(pre,args)
            if good then return value end
            storage[key]=false;failure(key,value)
        end,function(retval)
            if not thread.get_hook_storage()[key] or not post then return retval end
            local good,value=pcall(post,retval)
            if good then return value==nil and retval or value end
            failure(key,value);return retval
        end,table.unpack(extra,1,extra.n))
    end)
    M.status.hooks[key]=ok
    if not ok then failure(key,err) end
end
M.re=setmetatable({}, {__index=native_re})
function M.re.on_frame(fn)
    local owner=assert(M.context)
    local key=owner..":frame:"..tostring(fn)
    native_re.on_frame(function()
        if not M.active(owner) or M.status.errors[key] then return end
        local ok,err=pcall(fn)
        if not ok then failure(key,err) end
    end)
end
return M
