-- SPDX-License-Identifier: GPL-3.0-or-later
-- REFramework's file API is sandboxed. Only GHL's exact names use native storage.
local M={}
local settings={"refshell_mhwilds.json","AutoGuardGS.json","WpSeries_GreatSword_Config.json",
    "GenSeries_ParryWindow_Config.json","GHLQOL-gameplay.json","GHLQOL-buffer.json","GHLQOL-buffer-cache.json"}
local diagnostics={"GHLQOL-status.json","ParryMeister-status.json","AutoGuardGS-diagnostics.json"}
local profiles="GHLQOL-profiles.json"

function M.install()
    if rawget(_G,"__ghl_storage_status") then
        assert(_G.__ghl_storage_status.active,_G.__ghl_storage_status.error or "GHL storage initialization failed")
        return _G.__ghl_storage_status
    end
    local native=assert(rawget(_G,"__ghl_storage"),"GHL Documents storage is unavailable")
    assert(type(json.load_string)=="function" and type(json.dump_string)=="function","JSON string API unavailable")
    local original={load=json.load_file,dump=json.dump_file,glob=fs and fs.glob}
    local owned,patterns,blocked={},{},{}
    for _,names in ipairs({settings,diagnostics,{profiles}})do for _,name in ipairs(names)do
        owned[name]=true;patterns[name]=name;patterns[name:gsub("%.",[[\.]])]=name
    end end
    local status={root=assert(__ghl_paths and __ghl_paths.root,"GHL Documents path unavailable"),active=false,reads={},writes={}}
    _G.__ghl_storage_status=status
    local function fail(name,reason)
        local message="GHL storage "..name..": "..tostring(reason)
        blocked[name]=message;status.error=message
        error(message,0)
    end
    local function load(name)
        if blocked[name] then error(blocked[name],0)end
        local text,err=native.read(name)
        if err then fail(name,err)end
        if text==nil then return nil end
        local ok,value=pcall(json.load_string,text)
        if not ok or type(value)~="table" then fail(name,"JSON is invalid; existing file preserved")end
        return value
    end
    json.load_file=function(name,...)
        if not owned[name] then return original.load(name,...)end
        status.reads[name]=(status.reads[name] or 0)+1
        return load(name)
    end
    json.dump_file=function(name,value,indent,...)
        if not owned[name] then return original.dump(name,value,indent,...)end
        if blocked[name] then return false,blocked[name]end
        if type(value)~="table" then return false,"GHL JSON must be an object or array" end
        local ok,text=pcall(json.dump_string,value,indent==nil and 4 or indent)
        if not ok or type(text)~="string" or text=="" then return false,"Cannot encode GHL JSON" end
        local written,err=native.write(name,text)
        if written~=true then status.error="GHL storage "..name..": "..tostring(err);return false,status.error end
        status.writes[name]=(status.writes[name] or 0)+1
        return true
    end
    if original.glob then fs.glob=function(pattern,modifier,...)
        local name=(modifier==nil or modifier=="") and patterns[pattern]
        if not name then return original.glob(pattern,modifier,...)end
        if blocked[name] then error(blocked[name],0)end
        local found,err=native.exists(name)
        if err then fail(name,err)end
        return found and {name} or {}
    end end
    -- Install routing before validation: even failed startup cannot write old files.
    local has_profiles=load(profiles)~=nil
    for _,name in ipairs(settings)do
        -- After import the profile bundle owns preferences; old files are recovery copies.
        if not has_profiles or name=="GHLQOL-buffer-cache.json" then
            local ok,err=native.migrate(name)
            if ok~=true then fail(name,err)end
            load(name)
        end
    end
    status.active=true
    return status
end
return M
