-- SPDX-License-Identifier: GPL-3.0-or-later
local M={capabilities={},errors={}}
function M.call(obj,name,...)
    assert(obj,"Missing object for "..name)
    return obj:call(name,...)
end
function M.field(obj,name) assert(obj,"Missing object for "..name);return obj:get_field(name) end
function M.method(name,signature)
    local td=assert(sdk.find_type_definition(name),"Missing type "..name)
    return assert(td:get_method(signature),"Missing method "..name.."."..signature)
end
function M.static(name,signature,...) return M.method(name,signature):call(nil,...) end
function M.hunter()
    local mm=sdk.get_managed_singleton("app.MissionManager")
    if not mm or mm:call("get_IsGoToLoadingQuest") then return nil end
    local pm=sdk.get_managed_singleton("app.PlayerManager")
    local info=pm and pm:call("getMasterPlayer")
    local hunter=info and info:call("get_Character")
    if not hunter or not hunter:call("get_IsMaster") then return nil end
    local status=hunter:call("get_HunterStatus")
    if not status or status:call("get_IsNpc") then return nil end
    return hunter
end
function M.same(a,b) return a and b and a:get_address()==b:get_address() end
function M.local_status() local h=M.hunter();return h and h:call("get_HunterStatus"),h end
function M.local_field(name) local s=M.local_status();return s and s:get_field(name) end
function M.bound(value,lo,hi,default)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then value=default or lo end
    return math.max(lo,math.min(hi,value))
end
function M.text(guid)
    local ok,value=pcall(M.static,"via.gui.message","get(System.Guid)",guid)
    return ok and tostring(value) or "Unknown"
end
function M.item_name(id)
    local ok,value=pcall(M.static,"app.ItemDef","RawName(app.ItemDef.ID)",id)
    return ok and M.text(value) or ("Item "..tostring(id))
end
function M.enum(name)
    local rows={};local td=assert(sdk.find_type_definition(name),name)
    for _,f in ipairs(td:get_fields()) do
        local n=f:get_name()
        if n~="value__" and n~="MAX" and n~="NONE" and n~="INVALID" then
            local ok,id=pcall(f.get_data,f,nil)
            if ok and type(id)=="number" then rows[#rows+1]={id,n} end
        end
    end
    table.sort(rows,function(a,b)return a[1]<b[1] end);return rows
end
function M.hook(key,name,signature,pre,post)
    local ok,err=pcall(function()
        local method=M.method(name,signature)
        sdk.hook(method,function(args)
            local data={};thread.get_hook_storage()[key]=data
            if M.errors[key] then return end
            if pre then
                local read,value=pcall(pre,args,data)
                if read then return value end
                M.errors[key]=tostring(value):sub(1,1000)
                log.warn("[GHLQOL] Disabled hook "..key..": "..M.errors[key])
            end
        end,function(retval)
            local data=thread.get_hook_storage()[key]
            if not data then return retval end
            if M.errors[key] then if data.restore then pcall(data.restore) end;return retval end
            if not post then return retval end
            local read,value=pcall(post,retval,data)
            if data.restore then pcall(data.restore) end
            if read then return value==nil and retval or value end
            M.errors[key]=tostring(value):sub(1,1000)
            log.warn("[GHLQOL] Disabled hook "..key..": "..M.errors[key]);return retval
        end)
    end)
    M.capabilities[key]=ok
    if not ok then M.errors[key]=tostring(err):sub(1,1000) end
    return ok
end
function M.ready(key) return M.capabilities[key] and not M.errors[key] end
function M.object(args,index) return sdk.to_managed_object(args[index or 2]) end
function M.buffer(section,key)
    local b=package.loaded["Buffer.Modules.Character"]
    return type(b)=="table" and b.data and b.data[section] and b.data[section][key]==true
end
return M
