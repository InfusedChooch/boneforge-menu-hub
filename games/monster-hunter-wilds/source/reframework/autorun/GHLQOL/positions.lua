-- SPDX-License-Identifier: GPL-3.0-or-later
local R=require("GHLQOL.runtime")
local O=require("GHLQOL.options")
local M={status={saves=0,requests=0,attempts=0,dispatched=0,moves=0,failures=0}}
local saved,backup,pending,verifying
local next_probe=0
local metadata_done=false
local observation_times={0.15,0.5,1.0}
local arrival_tolerance=3
local function xyz(v) return {x=v.x,y=v.y,z=v.z} end
local function distance_squared(a,b)return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2 end
local function text(err) return tostring(err):sub(1,1000) end
local function read(stage,fn)
    local ok,value=pcall(fn)
    if not ok then error(stage..": "..text(value),0) end
    return value
end
local function action(name,fn,outcome)
    M.status.last_action=name;M.status.last_action_utc=os.date("!%Y-%m-%dT%H:%M:%SZ")
    local ok,value=pcall(fn)
    if not ok then
        M.status.failures=M.status.failures+1;M.status.last_outcome="error"
        M.status.last_error=text(value);M.status.last_error_action=name
        M.status.last_error_utc=M.status.last_action_utc
        if log and log.warn then log.warn("[GHLQOL Positions] "..name..": "..M.status.last_error) end
        error(value,0)
    end
    M.status.last_outcome=outcome or "success";M.status.last_result=value
    next_probe=0
    return value
end
local function current_scene(go)
    local ok,scene=pcall(go.call,go,"get_Scene")
    if ok and scene then M.status.scene_source="GameObject.get_Scene";return scene end
    -- Wilds can return nil here. Use the same route as pinned REFramework's
    -- shared/sdk/SceneManager.cpp get_current_scene(), retaining scene identity.
    return read("SceneManager.get_CurrentScene",function()
        local td=assert(sdk.find_type_definition("via.SceneManager"),"Scene manager type unavailable")
        assert(td:get_method("get_CurrentScene"),"Current scene getter unavailable")
        local manager=assert(sdk.get_native_singleton("via.SceneManager"),"Scene manager unavailable")
        local current=assert(sdk.call_native_func(manager,td,"get_CurrentScene"),"Current scene unavailable")
        M.status.scene_source="SceneManager.get_CurrentScene"
        return current
    end)
end
local function context()
    local h=read("Hunter lookup",function()return assert(R.hunter(),"Enter the field first")end)
    local pm=read("Player manager",function()return assert(sdk.get_managed_singleton("app.PlayerManager"),"Unavailable")end)
    local info=read("PlayerManager.getMasterPlayer",function()return assert(pm:call("getMasterPlayer"),"Master player unavailable")end)
    read("Master hunter identity",function()
        local current=assert(info:call("get_Character"),"Master hunter unavailable")
        assert(current:get_address()==h:get_address(),"Master hunter changed during lookup")
    end)
    -- PlayerInfo.get_Object is the root used by the reference movement feature;
    -- Hunter.get_GameObject can be a different object whose position is restored.
    local go=read("PlayerInfo.get_Object",function()return assert(info:call("get_Object"),"Master player object unavailable")end)
    local scene=current_scene(go)
    local mm=read("Mission manager",function()return assert(sdk.get_managed_singleton("app.MissionManager"),"Unavailable")end)
    local q=read("MissionManager.get_QuestDirector",function()return mm:call("get_QuestDirector")end)
    local data=read("QuestDirector.get_QuestData",function()return q and q:call("get_QuestData")end)
    local key=read("Scene/hunter/quest identity",function()
        return table.concat({tostring(h:get_address()),tostring(go:get_address()),tostring(scene:get_address()),tostring(data and data:get_address() or 0)},":")
    end)
    M.status.identity={hunter=h:get_address(),master_object=go:get_address(),scene=scene:get_address(),quest=data and data:get_address() or 0}
    local ok,child=pcall(function()local obj=h:call("get_GameObject");return obj and obj:get_address()end)
    if ok then M.status.identity.hunter_object=child end
    local trans=read("GameObject.get_Transform",function()return assert(go:call("get_Transform"),"Transform unavailable")end)
    local pos=read("Transform.get_Position",function()return xyz(trans:call("get_Position"))end)
    return key,trans,pos,go
end
local function checked(point)
    assert(point and type(point.key)=="string","No position saved")
    for _,k in ipairs({"x","y","z"}) do local n=point.pos[k];assert(type(n)=="number" and n==n and math.abs(n)<100000,"Invalid position") end
    local key,trans,current,go=context()
    assert(key==point.key,"Scene, hunter or quest changed; save a new position")
    local p=point.pos
    assert(distance_squared(p,current)<10000^2,"Destination is outside this local area")
    return trans,current,key,go
end
function M.save()
    return action("save",function()
        local key,_,pos=context();saved={key=key,pos=pos}
        M.status.saves=M.status.saves+1;M.status.saved_position=xyz(pos)
        return "Position saved for this scene and quest"
    end)
end
function M.move(point)
    return action("queue move",function()
        assert(not pending and not verifying,"Wait for position verification before another move")
        checked(point)
        pending={key=point.key,pos=xyz(point.pos),source=point.source}
        M.status.queued=true
        return "Position change queued for the next motion update"
    end,"queued")
end
local function dispatch(point)
    M.status.attempts=M.status.attempts+1
    return action("move",function()
        M.status.partial_dispatch=false;M.status.controller=nil
        local trans,current,key,go=checked(point)
        local controller=read("Character controller preflight",function()
            local td=assert(sdk.find_type_definition("via.physics.CharacterController"),"Controller type unavailable")
            local warp=assert(td:get_method("warp()"),"Controller warp method unavailable")
            assert(warp:get_num_params()==0,"Controller warp signature changed")
            local ty=assert(sdk.typeof("via.physics.CharacterController"),"Controller runtime type unavailable")
            return assert(go:call("getComponent(System.Type)",ty),"Master player character controller unavailable")
        end)
        local telemetry={address=controller:get_address()};M.status.controller=telemetry
        local function sample(name)
            local ok,value=pcall(function()return xyz(controller:call("get_Position"))end)
            if ok then telemetry[name]=value else telemetry[name.."_error"]=text(value)end
        end
        sample("before")
        M.status.last_move_source=point.source or "Direct move"
        M.status.destination=xyz(point.pos);M.status.origin=xyz(current)
        read("Transform.set_Position",function()trans:call("set_Position",Vector3f.new(point.pos.x,point.pos.y,point.pos.z))end)
        -- Keep Return as soon as the transform was written, even if the following
        -- controller synchronization fails. Never retry either operation.
        backup={key=key,pos=current}
        M.status.dispatched=M.status.dispatched+1
        M.status.verification={outcome="pending",samples={},tolerance=arrival_tolerance}
        verifying={key=key,pos=xyz(point.pos),started=os.clock(),index=1}
        local synced,err=pcall(function()read("CharacterController.warp",function()controller:call("warp")end)end)
        sample("after")
        if not synced then
            telemetry.sync_error=text(err);verifying.sync_error=text(err)
            M.status.partial_dispatch=true
            M.status.last_result="Position partially dispatched; controller synchronization failed"
            error(err,0)
        end
        return "Position change dispatched; checking that it persists"
    end,"pending")
end
local function observe()
    local check=verifying
    if not check or os.clock()-check.started<observation_times[check.index] then return end
    local out=M.status.verification
    local ok,err=pcall(function()
        local key,_,pos=context()
        assert(key==check.key,"Scene, hunter or quest changed during position verification")
        local d=distance_squared(pos,check.pos)
        assert(d==d and d<math.huge,"Invalid observed position")
        out.samples[#out.samples+1]={elapsed=os.clock()-check.started,position=xyz(pos),distance_squared=d}
        out.distance_squared=d
    end)
    if not ok or check.index==#observation_times then
        verifying=nil
        local arrived=ok and not check.sync_error and out.distance_squared<=arrival_tolerance^2
        out.outcome=arrived and "observed" or "failed"
        out.updated_utc=os.date("!%Y-%m-%dT%H:%M:%SZ")
        pcall(action,"verify move",function()
            assert(ok,"Position verification unavailable: "..text(err))
            assert(not check.sync_error,"Controller synchronization failed after the transform write: "..text(check.sync_error))
            assert(arrived,"Position change did not persist or did not reach the destination; no retry was made")
            M.status.moves=M.status.moves+1
            return "Position observed near the destination after the motion update"
        end)
    else check.index=check.index+1 end
end
function M.waypoint()
    local key=context();local gui=assert(sdk.get_managed_singleton("app.GUIManager"),"GUI manager unavailable")
    local map=assert(gui:call("getMapNaviData"),"Set a map waypoint first")
    local list=map:call("get_SortedPoints");local count=list and list:call("get_Count") or 0
    assert(count>0,"No active waypoint route")
    local pos=xyz(list:call("get_Item",count-1));pos.y=pos.y+1.5
    return {key=key,pos=pos}
end
function M.monster()
    local key,_,current=context()
    local em=assert(sdk.get_managed_singleton("app.EnemyManager"),"Enemy manager unavailable")
    local dyn=em:get_field("_EnemyCharacterValidList");local list=dyn:get_field("_Array")
    local count=math.min(dyn:get_field("_Count"),128);local best,distance
    for i=0,count-1 do
        local info=list:get_element(i)
        local holder=info and info:call("get_Context");local enemy=holder and holder:call("get_Em")
        if enemy and enemy:call("get_IsBoss") and info:call("get_CharacterValid") then
            local pos=xyz(info:call("get_Pos"));local d=(pos.x-current.x)^2+(pos.y-current.y)^2+(pos.z-current.z)^2
            if not distance or d<distance then best=pos;distance=d end
        end
    end
    assert(best,"No spawned large monster found in this scene")
    best.x=best.x+3;best.y=best.y+1.5
    return {key=key,pos=best}
end
local function confirm(ui,menu,label,point)
    checked(point)
    local target={key=point.key,pos=xyz(point.pos),source=label}
    M.status.last_request_destination=xyz(target.pos)
    ui.confirm({title=label.."?",lines={"Move within the current scene?",
        string.format("Destination: X %.1f, height %.1f, Z %.1f",target.pos.x,target.pos.y,target.pos.z),
        "Your previous position is kept for returning."},yes="Move",no="Cancel",
        on_yes=function()O.action(menu,function()return M.move(target)end)end,
        on_no=function()M.status.last_outcome="cancelled";M.status.last_result="Move cancelled"end})
    return "Waiting for Move confirmation"
end
function M.request(ui,menu,label,point_or_supplier)
    M.status.requests=M.status.requests+1
    M.status.last_request=label;M.status.last_request_destination=nil
    menu._confirm=nil
    local ok,err=pcall(function()return action("request: "..label,function()
        assert(not pending and not verifying,"Wait for position verification before another move")
        local point=type(point_or_supplier)=="function" and point_or_supplier() or point_or_supplier
        return confirm(ui,menu,label,point)
    end)end)
    if not ok then menu:toast(tostring(err):sub(1,200),"warning",2500)end
    return ok
end
function M.snapshot()
    -- Read only. The map polls this while visible; drawing and selecting never
    -- call a movement setter. Destinations still pass request/move/dispatch checks.
    local key,_,pos=context()
    local out={key=key,position=xyz(pos),markers={},busy=pending~=nil or verifying~=nil,errors={}}
    local function add(id,name,point)
        if point and point.key==key then
            out.markers[#out.markers+1]={id=id,name=name,kind=id,key=key,pos=xyz(point.pos)}
        end
    end
    add("saved","Saved position",saved);add("previous","Previous position",backup)
    for _,row in ipairs({{"waypoint","Map waypoint",M.waypoint},{"monster","Near nearest monster",M.monster}})do
        local ok,point=pcall(row[3])
        if ok then add(row[1],row[2],point)else out.errors[row[1]]=text(point)end
    end
    return out
end
local function waypoint_probe(current)
    local out={updated_utc=os.date("!%Y-%m-%dT%H:%M:%SZ"),errors={}}
    M.status.waypoint=out
    local function sample(key,fn)
        local ok,value=pcall(fn)
        if not ok then out.errors[key]=text(value) end
        if ok then return value end
    end
    local function route(map)
        local info={available=map~=nil}
        if not map then return info end
        info.mode=sample("route mode",function()return map:call("get_Type")end)
        local list=map:call("get_SortedPoints")
        info.count=list and list:call("get_Count") or 0
        assert(type(info.count)=="number" and info.count>=0 and info.count<=10000,"Invalid route point count")
        if info.count>0 then
            info.first=xyz(list:call("get_Item",0));info.last=xyz(list:call("get_Item",info.count-1))
            if current then
                local function distance(p)return (p.x-current.x)^2+(p.y-current.y)^2+(p.z-current.z)^2 end
                info.first_distance_squared=distance(info.first);info.last_distance_squared=distance(info.last)
            end
        end
        return info
    end
    local gui=sample("GUIManager",function()return assert(sdk.get_managed_singleton("app.GUIManager"),"Unavailable")end)
    if not gui then return end
    out.navigation=sample("isNavigation",function()return gui:call("isNavigation")end)
    out.route=sample("GUI route",function()return route(gui:call("getMapNaviData"))end)
    local ctrl=sample("navigation controller",function()return gui:get_field("_MapNaviPointCtrl")end)
    if ctrl then
        out.flags={}
        for _,name in ipairs({"get_IsNavigating","IsPorterNavigating","IsGuideInsectNavigating","IsGuideInsectNaviFinished"})do
            out.flags[name]=sample(name,function()return ctrl:call(name)end)
        end
        out.controller_route=sample("controller route",function()return route(ctrl:call("get_MapNaviData"))end)
        out.controller_field_route=sample("controller route field",function()return route(ctrl:get_field("_MapNaviData"))end)
    end
    -- Inspect only metadata and selected existing fields, never invoke unknown
    -- marker methods. At most five objects and one child level are described.
    local remaining=5
    local function relevant(name)
        name=name:lower()
        for _,word in ipairs({"marker","target","navi","cursor","point","select","icon"})do
            if name:find(word,1,true)then return true end
        end
        return false
    end
    local function describe(obj,depth)
        if not obj or remaining==0 then return nil end
        remaining=remaining-1
        local td=obj:get_type_definition()
        local result={type=td:get_full_name(),fields={},methods={}}
        for i,method in ipairs(td:get_methods() or {})do
            if i>512 or #result.methods>=40 then break end
            local name=method:get_name()
            if relevant(name)then result.methods[#result.methods+1]=name end
        end
        for i,field in ipairs(td:get_fields() or {})do
            if i>256 or #result.fields>=32 then break end
            local name=field:get_name();local ft=field:get_type();local type_name=ft and ft:get_full_name() or "unknown"
            if relevant(name) or relevant(type_name)then
                local row={name=name,type=type_name};result.fields[#result.fields+1]=row
                local value=sample("map field "..name,function()return obj:get_field(name)end)
                if type(value)=="boolean" or type(value)=="number" then row.value=value
                elseif type(value)=="string" then row.value=value:sub(1,160)
                elseif value~=nil then
                    local ok,v=pcall(xyz,value)
                    if ok and type(v.x)=="number" and type(v.y)=="number" and type(v.z)=="number" then row.position=v
                    elseif depth==0 and remaining>0 then row.object=sample("map child "..name,function()return describe(value,1)end)end
                end
            end
        end
        return result
    end
    out.map=sample("MAP3D metadata",function()return describe(gui:get_field("<MAP3D>k__BackingField"),0)end)
end
local function validation(point,missing)
    if not point then return {available=false,reason=missing} end
    local ok,err=pcall(checked,point)
    return {available=ok,reason=not ok and text(err) or nil}
end
local function movement_metadata()
    if metadata_done then return end
    metadata_done=true
    local out={read_only=true,types={},errors={}}
    M.status.movement_metadata=out
    local queue={"app.HunterCharacter","System.Nullable`1<via.Quaternion>","via.physics.CharacterController"}
    local seen={}
    local queued={};for _,name in ipairs(queue)do queued[name]=true end
    local index=1
    local function relevant(name)
        name=name:lower()
        return name:find("warp",1,true) or name:find("position",1,true) or name:find("controller",1,true) or name:find("transform",1,true)
    end
    local function enqueue(td,priority)
        if not td or index>8 then return end
        local name=td:get_full_name()
        if queued[name] or seen[name] or (#queue>=8 and not priority)then return end
        if #queue>=8 then queued[queue[8]]=nil;queue[8]=nil end
        if priority then table.insert(queue,math.max(index,4),name)else queue[#queue+1]=name end
        queued[name]=true
    end
    local function signature(method)
        local item={name=method:get_name(),params={},param_names={},returns=method:get_return_type():get_full_name()}
        for j,param in ipairs(method:get_param_types() or {})do
            if j>8 then break end
            item.params[#item.params+1]=param:get_full_name()
        end
        for j,param in ipairs(method:get_param_names() or {})do
            if j>8 then break end
            item.param_names[#item.param_names+1]=param
        end
        return item
    end
    -- Resolve this overload directly so broad signature limits cannot hide it.
    local ok,err=pcall(function()
        local td=assert(sdk.find_type_definition("app.HunterCharacter"),"Hunter type unavailable")
        local method=assert(td:get_method("warp(via.vec3, System.Nullable`1<via.Quaternion>, System.Boolean)"),"Warp overload unavailable")
        out.warp=signature(method)
    end)
    if not ok then out.errors.warp=text(err)end
    while index<=#queue and index<=8 do
        local name=queue[index];index=index+1
        if not seen[name] then
            seen[name]=true
            local ok,err=pcall(function()
                local td=assert(sdk.find_type_definition(name),"Type unavailable")
                local row={name=name,methods={},fields={}};out.types[#out.types+1]=row
                local parent=td:get_parent_type()
                if parent then row.parent=parent:get_full_name();enqueue(parent,true) end
                for i,method in ipairs(td:get_methods() or {})do
                    if i>768 or #row.methods>=48 then break end
                    local method_name=method:get_name()
                    if relevant(method_name)then
                        local item=signature(method)
                        row.methods[#row.methods+1]=item
                        if item.returns:lower():find("controller",1,true)then enqueue(method:get_return_type())end
                    end
                end
                for i,field in ipairs(td:get_fields() or {})do
                    if i>256 or #row.fields>=32 then break end
                    local field_name=field:get_name();local ft=field:get_type();local type_name=ft:get_full_name()
                    if name:find("Nullable",1,true) or relevant(field_name) or relevant(type_name)then
                        row.fields[#row.fields+1]={name=field_name,type=type_name}
                        if type_name:lower():find("controller",1,true)then enqueue(ft)end
                    end
                end
            end)
            if not ok then out.errors[name]=text(err)end
        end
    end
end
local function probe()
    if os.clock()<next_probe then return end
    next_probe=os.clock()+1
    -- Read only, and only while this page is drawn. No teleport is scheduled.
    local ok,key,_,pos=pcall(context)
    M.status.context={available=ok,updated_utc=os.date("!%Y-%m-%dT%H:%M:%SZ")}
    if ok then M.status.context.key=key;M.status.context.position=pos
    else M.status.context.error=text(key) end
    waypoint_probe(ok and pos or nil)
    M.status.saved=validation(saved,"No position saved this session. Use Save current position first.")
    M.status.previous=validation(backup,"No previous position yet. Complete a move first.")
end
function M.draw(ui,menu)
    local in_field=O.in_field()
    probe()
    ui.muted("Positions stay in memory for the current scene, hunter and quest, and are cleared by restart or script reset. Teleports do not load other maps.")
    if not in_field then ui.muted("Load your hunter to save or move to a position.")end
    if M.status.context.error then ui.muted("Position read failed: "..M.status.context.error) end
    if M.status.last_outcome=="error" then ui.muted("Last "..M.status.last_error_action.." failed: "..M.status.last_error) end
    if M.status.verification and M.status.verification.outcome=="failed" then ui.muted("The last move was not verified. It may have snapped back; no retry was made.")end
    if pending or verifying then ui.muted(M.status.last_result)end
    local available=in_field and not pending and not verifying
    if O.button(ui,"Save current position",available) then menu._confirm=nil;O.action(menu,M.save);probe() end
    for _,entry in ipairs({{"Go to saved position",function()return saved end},{"Return to previous position",function()return backup end},{"Go to map waypoint",M.waypoint},{"Go near nearest large monster",M.monster}}) do
        local enabled=available
        local state=entry[1]=="Go to saved position" and M.status.saved or entry[1]=="Return to previous position" and M.status.previous
        if state then enabled=enabled and state.available end
        if O.button(ui,entry[1],enabled) then
            -- A failed replacement must not leave an earlier saved-point Move
            -- button alive with its old callback and destination.
            M.request(ui,menu,entry[1],entry[2])
        end
        if state and not state.available then ui.muted(state.reason) end
    end
end
re.on_application_entry("UpdateMotionFrame",function()
    movement_metadata()
    if pending then
        local point=pending;pending=nil;M.status.queued=false
        pcall(dispatch,point)
    else observe()end
end)
re.on_script_reset(function()
    saved=nil;backup=nil;pending=nil;verifying=nil;next_probe=0
    M.status.saved_position=nil;M.status.queued=false;M.status.verification=nil;M.status.partial_dispatch=false
end)
return M
