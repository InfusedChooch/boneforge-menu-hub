-- SPDX-License-Identifier: GPL-3.0-or-later
-- A profile changes the next launch's settings, never the running engines.
local existing=rawget(_G,"__ghl_profiles_module")
if existing then return existing end
local M={status={active=false}}
local path="GHLQOL-profiles.json"
local names={"refshell_mhwilds.json","AutoGuardGS.json","WpSeries_GreatSword_Config.json",
    "GenSeries_ParryWindow_Config.json","GHLQOL-gameplay.json","GHLQOL-buffer.json"}
local owned,patterns={},{}
for _,name in ipairs(names)do owned[name]=true;patterns[name]=name;patterns[name:gsub("%.",[[\.]])]=name end
local store,running_id,original,staged,stage_error
local savers,seen_savers={},{}
local choice,new_name,message=nil,"",""
local max_bytes=8*1024*1024

local function copy(value)
    local seen,nodes={},0
    local function check(v,depth)
        nodes=nodes+1
        assert(depth<=32 and nodes<=200000,"Profile JSON exceeds structural limits")
        local kind=type(v)
        if kind=="number" then assert(v==v and math.abs(v)<math.huge,"Profile JSON contains a non-finite number")
        elseif kind=="string" then assert(#v<=max_bytes,"Profile JSON string is too large")
        elseif kind=="table" then
            assert(not seen[v],"Profile JSON contains a cycle")
            seen[v]=true
            local result={}
            local count,largest,strings=0,0,0
            for k,item in pairs(v)do
                if type(k)=="number" then
                    assert(k>=1 and k%1==0,"Profile JSON has an invalid array index")
                    count=count+1;largest=math.max(largest,k)
                else assert(type(k)=="string" and #k<=1024,"Profile JSON has an invalid key");strings=strings+1 end
                result[k]=check(item,depth+1)
            end
            assert(count==0 or strings==0 and count==largest,"Profile JSON has a sparse or mixed array")
            seen[v]=nil
            return result
        else assert(kind=="boolean","Profile JSON contains an unsupported value")end
        return v
    end
    return check(value,0)
end
local function encode(value)
    -- REFramework serializes an empty Lua table as null, then decodes it as nil.
    -- Preserve empty settings tables as JSON objects without changing the schema.
    local chunks,bytes={},0
    local function emit(text)
        assert(type(text)=="string" and #text>0,"Cannot encode profile JSON")
        bytes=bytes+#text;assert(bytes<=max_bytes,"Profile JSON exceeds the size limit")
        chunks[#chunks+1]=text
    end
    local function write(v)
        if type(v)~="table"then emit(json.dump_string(v));return end
        if #v>0 then
            emit("[")
            for i,item in ipairs(v)do if i>1 then emit(",")end;write(item)end
            emit("]")
        else
            local keys={};for key in pairs(v)do keys[#keys+1]=key end;table.sort(keys)
            emit("{")
            for i,key in ipairs(keys)do
                if i>1 then emit(",")end
                emit(json.dump_string(key));emit(":");write(v[key])
            end
            emit("}")
        end
    end
    write(value)
    return table.concat(chunks)
end
local function valid_name(name)
    assert(type(name)=="string","Enter a profile name")
    name=name:match("^%s*(.-)%s*$")
    assert(#name>0 and #name<=64 and not name:find("[%z\1-\31\127/\\#]"),"Use a name of 1-64 bytes without control characters, slashes or #")
    return name
end
local function files(value)
    assert(type(value)=="table","Profile files must be an object")
    for name in pairs(value)do assert(owned[name],"Profile contains an unsupported settings file")end
    for _,name in ipairs(names)do assert(type(value[name])=="table","Profile is missing settings: "..name)end
end
local function find(bundle,id)
    for _,profile in ipairs(bundle.profiles)do if profile.id==id then return profile end end
end
local function validate(bundle)
    assert(type(bundle)=="table" and bundle.schema==1,"Unsupported profile store schema")
    for key in pairs(bundle)do assert(key=="schema" or key=="selected" or key=="profiles","Unknown profile store field")end
    assert(type(bundle.profiles)=="table" and #bundle.profiles>=1 and #bundle.profiles<=32,"Profile store must contain 1-32 profiles")
    local ids,labels,count={},{},0
    for index,profile in pairs(bundle.profiles)do
        assert(type(index)=="number" and index>=1 and index%1==0 and index<=#bundle.profiles,"Invalid profile array")
        count=count+1
        assert(type(profile)=="table","Invalid profile record")
        for key in pairs(profile)do assert(key=="id" or key=="name" or key=="files","Unknown profile field")end
        assert(type(profile.id)=="string" and #profile.id<=16 and profile.id:match("^p[1-9]%d*$") and not ids[profile.id],"Invalid or duplicate profile id")
        local name=valid_name(profile.name)
        assert(name==profile.name and not labels[name:lower()],"Invalid or duplicate profile name")
        ids[profile.id]=true;labels[name:lower()]=true;files(profile.files)
    end
    assert(count==#bundle.profiles and type(bundle.selected)=="string" and ids[bundle.selected],"Selected profile is missing")
    return bundle
end
local function failure(err)
    M.status.error=tostring(err):sub(1,1000)
    if staged then stage_error=M.status.error end
    return false,M.status.error
end
local function publish()
    local active,next_profile=find(store,running_id),find(store,store.selected)
    M.status.running_id=running_id;M.status.running_name=active.name
    M.status.selected_id=store.selected;M.status.selected_name=next_profile.name
    M.status.pending=running_id~=store.selected;M.status.count=#store.profiles
end
local function commit(candidate)
    local ok,value,encoded=pcall(function()
        local snapshot=validate(copy(candidate));return snapshot,encode(snapshot)
    end)
    if not ok then return failure(value)end
    local called,written,err=pcall(original.write,path,encoded)
    if not called or written~=true then return failure(called and (err or "Profile write was refused") or written)end
    local storage=rawget(_G,"__ghl_storage_status")
    if storage and storage.writes then storage.writes[path]=(storage.writes[path] or 0)+1 end
    store=value;M.status.error=nil
    if running_id then publish()end
    return true
end
local function active_bundle()return staged or store end

function M.install()
    if rawget(_G,"__ghl_profiles_status") then
        assert(M.status.active,M.status.error or "Profile initialization failed")
        return M.status
    end
    _G.__ghl_profiles_module=M;_G.__ghl_profiles_status=M.status
    original={load=json.load_file,dump=json.dump_file,glob=fs and fs.glob,
        write=rawget(_G,"__ghl_storage") and __ghl_storage.write}
    -- Routing is installed before validation, so failed startup cannot overwrite
    -- a corrupt bundle or fall back to the legacy six files.
    json.load_file=function(name,...)
        if not owned[name]then return original.load(name,...)end
        assert(M.status.active,M.status.error or "Profiles are unavailable")
        return copy(find(active_bundle(),running_id).files[name])
    end
    json.dump_file=function(name,value,...)
        if not owned[name]then return original.dump(name,value,...)end
        if not M.status.active then return false,M.status.error or "Profiles are unavailable"end
        local ok,snapshot=pcall(function()assert(type(value)=="table","Settings must be an object or array");return copy(value)end)
        if not ok then return failure(snapshot)end
        if staged then find(staged,running_id).files[name]=snapshot;return true end
        local candidate=copy(store);find(candidate,running_id).files[name]=snapshot
        return commit(candidate)
    end
    if original.glob then fs.glob=function(pattern,modifier,...)
        local name=(modifier==nil or modifier=="") and patterns[pattern]
        if not name then return original.glob(pattern,modifier,...)end
        assert(M.status.active,M.status.error or "Profiles are unavailable")
        return {name}
    end end
    local ok,err=pcall(function()
        assert(type(json.dump_string)=="function" and type(json.load_string)=="function","Profile JSON API unavailable")
        assert(type(original.write)=="function","Atomic profile storage is unavailable")
        local loaded=original.load(path)
        if loaded~=nil then store=validate(copy(loaded));encode(store)
        else
            local blank=copy(require("GHLQOL.profile_defaults").new());files(blank)
            local current=copy(blank);local imported=false
            for _,name in ipairs(names)do
                local value=original.load(name)
                if value~=nil then assert(type(value)=="table","Invalid legacy settings: "..name);current[name]=copy(value);imported=true end
            end
            local candidate={schema=1,selected=imported and "p2" or "p1",profiles={{id="p1",name="Default",files=blank}}}
            if imported then candidate.profiles[2]={id="p2",name="Current setup",files=current}end
            local written,reason=commit(candidate);assert(written,reason)
        end
        local latch=rawget(_G,"__ghl_storage") and __ghl_storage.profile_session
        assert(type(latch)=="function","Profile session latch is unavailable")
        local session,reason=latch(store.selected)
        assert(session,reason or "Profile session latch refused initialization")
        running_id=session
        assert(type(running_id)=="string" and find(store,running_id),"Running profile is missing; restart Wilds")
        M.status.active=true;publish()
    end)
    if not ok then failure(err);error(M.status.error,0)end
    return M.status
end
function M.start(load_fn)
    assert(M.status.active,M.status.error or "Install profiles before starting engines")
    local register=re.on_config_save
    re.on_config_save=function(callback,...)
        local result=table.pack(register(callback,...))
        if type(callback)=="function" and not seen_savers[callback]then seen_savers[callback]=true;savers[#savers+1]=callback end
        return table.unpack(result,1,result.n)
    end
    local result=table.pack(xpcall(load_fn,debug.traceback))
    re.on_config_save=register
    if not result[1]then error(result[2],0)end
    return table.unpack(result,2,result.n)
end
function M.list()
    local result={}
    for _,profile in ipairs(store and store.profiles or {})do result[#result+1]={id=profile.id,name=profile.name}end
    return result
end
function M.select(id)
    if not M.status.active then return failure("Profiles are unavailable")end
    if not find(store,id)then return failure("Profile does not exist")end
    if id==store.selected then return true end
    local candidate=copy(store);candidate.selected=id
    return commit(candidate)
end
function M.create(name,copy_current)
    if not M.status.active then return failure("Profiles are unavailable")end
    local ok,result=pcall(function()
        name=valid_name(name)
        assert(#store.profiles<32,"The limit is 32 profiles")
        for _,profile in ipairs(store.profiles)do assert(profile.name:lower()~=name:lower(),"That profile name already exists")end
        assert(not staged,"Profile save is already in progress")
        local candidate=copy(store)
        if copy_current then
            staged=candidate;stage_error=nil
            for _,save in ipairs(savers)do
                local saved,err=pcall(save)
                if not saved then stage_error=tostring(err);break end
            end
            staged=nil
            assert(not stage_error,stage_error)
        end
        local snapshot=copy_current and copy(find(candidate,running_id).files) or copy(require("GHLQOL.profile_defaults").new())
        files(snapshot)
        local index=1;while find(candidate,"p"..index)do index=index+1 end
        local id="p"..index
        candidate.profiles[#candidate.profiles+1]={id=id,name=name,files=snapshot};candidate.selected=id
        return candidate
    end)
    staged=nil
    if not ok then return failure(result)end
    return commit(result)
end
function M.draw(ui,menu)
    ui.section("Profiles",function()
        if not M.status.active then ui.muted(M.status.error or "Profiles are unavailable");return end
        ui.muted("Running profile: "..M.status.running_name)
        if M.status.pending then ui.muted("Next launch: "..M.status.selected_name..". Restart Wilds to apply.")end
        local entries,labels,index=M.list(),{},1
        choice=choice or store.selected
        for i,entry in ipairs(entries)do labels[i]=entry.name;if entry.id==choice then index=i end end
        ui.muted("Profile for next launch")
        imgui.push_item_width(-1)
        local result=table.pack(pcall(imgui.combo,"##ghl_profile_select",index,labels))
        imgui.pop_item_width()
        if not result[1]then ui.muted("Profile selector unavailable: "..tostring(result[2]));return end
        local changed,value=result[2],result[3]
        if changed and entries[value]then choice=entries[value].id end
        local function report(ok,err)
            message=ok and "Saved. Restart Wilds to apply the selected profile." or tostring(err)
            if ok then choice=store.selected end
        end
        if ui.button("Use on next launch")then report(M.select(choice))end
        local typed,value=ui.input_text("ghl_profile_name",new_name,{label="New profile name"})
        if typed then new_name=value end
        if ui.button("New blank profile")then report(M.create(new_name,false))end
        if ui.button("Save as new profile")then report(M.create(new_name,true))end
        ui.muted("Edits save to the running profile. New blank profiles start with optional features off.")
        if message~=""then ui.muted(message)end
        if M.status.error then ui.muted("Profile save failed: "..M.status.error)end
    end,true)
end
return M
