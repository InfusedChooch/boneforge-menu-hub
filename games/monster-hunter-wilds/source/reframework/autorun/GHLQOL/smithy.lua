-- SPDX-License-Identifier: GPL-3.0-or-later
local R=require("GHLQOL.runtime")
local O=require("GHLQOL.options")
local Data=require("GHLQOL.gogma_data")
local Patch=require("GHLQOL.table_patch")
local Layered=require("GHLQOL.layered")
local M={status={rolls={applied=false},skills={applied=false}}}
O.data.smithy=O.data.smithy or {}
local cfg=O.data.smithy
for _,key in ipairs({"rolls","skills"})do if type(cfg[key])~="table"then cfg[key]={}end end
local rolls,skills=cfg.rolls,cfg.skills
if rolls.preset==nil then rolls.preset=Data.rolls[1].id end
if skills.preset==nil then skills.preset=Data.skills[1].id end
if skills.monster==nil then skills.monster=true end
if skills.lord_soul==nil then skills.lord_soul=true end
if type(rolls.custom)~="table"then rolls.custom={4,0,1,0}end
local controllers,blocked={},{}
local next_tick,inspect,initialized=0,false,false
local metadata={rolls={"app.user_data.ArtianBonusCategoryData.cData"},skills={"app.user_data.ArtianSkillGroupData.cData"}}
local function number(row,field)
    local value=row:get_field(field)
    if type(value)~="number" and value then value=value:get_field("value__")end
    assert(type(value)=="number" and value==value and value%1==0,"Invalid numeric field "..field)
    return value
end
local function preset(list,id)
    for _,entry in ipairs(list)do if entry.id==id then return entry end end
    error("Unknown Gogma preset",0)
end
local function field(object,name)
    return object and object:get_field(name)
end
local function setting()
    local manager=sdk.get_managed_singleton("app.VariousDataManager")
    return field(field(field(manager,"_Setting"),"_EquipDatas"),"_ArtianDataSetting")
end
local function model(key,settings)
    local resource=field(settings,key=="rolls" and "_BonusCategoryData" or "_ArtianSkillGroup")
    local array=field(resource,"_Values")
    if not array then return nil end
    local expected=key=="rolls" and 4 or #Data.skill_rows
    -- get_elements returns a native vector on supported hosts, not a Lua table.
    local count=array:get_size()
    M.status[key].observed_rows=count;M.status[key].expected_rows=expected
    assert(count==expected,"Gogma "..key.." table changed; expected "..expected.." rows, got "..tostring(count))
    local result={key=tostring(resource:get_address())..":"..tostring(array:get_address()),cells={},rows={}}
    local seen={}
    for position=0,count-1 do
        local row=assert(array:get_element(position),"Missing Gogma row at position "..position)
        local index=number(row,"_Index")
        assert(index>=0 and index<expected and not seen[index],"Unexpected or duplicate Gogma row")
        seen[index]=true;result.rows[index+1]=row
        if key=="rolls" then
            assert(number(row,"_BonusCategory")==({0,1,3,2})[index+1],"Roll category identity changed")
        else
            local identity=Data.skill_rows[index+1]
            for i,name in ipairs({"_Index","_ArtianSkillType","_GroupSkillId","_SeriesSkillId"})do
                assert(number(row,name)==identity[i],"Skill identity changed at row "..index)
            end
        end
    end
    for _,row in ipairs(result.rows)do
        result.cells[#result.cells+1]={object=row,field="_Probability"}
        if key=="rolls"then result.cells[#result.cells+1]={object=row,field="_GrindingMaxNum"}end
    end
    return result
end
local function desired(key,controller)
    local values={}
    if key=="rolls"then
        local counts=rolls.preset=="custom" and rolls.custom or preset(Data.rolls,rolls.preset).counts
        local total=0
        for i=1,4 do
            local n=counts[i]
            assert(type(n)=="number" and n==n and n%1==0 and n>=0 and n<=5,"Custom roll counts must be whole numbers from 0 to 5")
            total=total+n;values[#values+1]=60;values[#values+1]=n
        end
        assert(total==5,"Choose exactly five custom rolls; nothing applied")
    else
        local chosen=preset(Data.skills,skills.preset)
        local monster,lord=skills.monster==true,skills.lord_soul==true
        if not monster and not lord then return nil end
        local sum=0
        for i,identity in ipairs(Data.skill_rows)do
            local allowed
            if monster and lord then allowed=identity[1]==chosen.index
            else allowed=(not monster or identity[3]==chosen.group) and (not lord or identity[4]==chosen.series)end
            -- The exact collection uses one selected row with weight 1. A single
            -- constraint retains baseline weighting for the unrestricted trait.
            local value=allowed and (monster and lord and 1 or controller.patch.original[i]) or 0
            assert(value>=0,"Invalid baseline skill probability")
            values[i]=value;sum=sum+value
        end
        assert(sum>0,"No eligible skills in the baseline; disable conflicting Gogma skill mods")
    end
    return values
end
local function signature(key)
    if key=="rolls"then return tostring(rolls.preset)..":"..table.concat({tostring(rolls.custom[1]),tostring(rolls.custom[2]),tostring(rolls.custom[3]),tostring(rolls.custom[4])},",")end
    return tostring(skills.preset)..":"..tostring(skills.monster)..":"..tostring(skills.lord_soul)
end
local function restore(key)
    local controller=controllers[key]
    if not controller then M.status[key].applied=false;return true end
    local ok,err,foreign=controller.patch:restore()
    if not ok then M.status[key].error="Restore pending: "..tostring(err);return false end
    controllers[key]=nil;M.status[key].applied=false
    M.status[key].restore_note=foreign>0 and ("Preserved "..foreign.." changes made by another writer") or nil
    return true
end
local function update(key,settings)
    local status=M.status[key]
    local options=key=="rolls" and rolls or skills
    if options.enabled~=true then
        if restore(key)then status.error=nil;blocked[key]=nil end
        return
    end
    if not R.capabilities["gogma_"..key]then return end
    local sig=signature(key)
    if blocked[key]==sig then return end
    local ok,err=pcall(function()
        local data=model(key,settings)
        if not data then status.waiting="Waiting for game equipment data";return end
        status.waiting=nil;status.rows=#data.rows
        local old=controllers[key]
        if old and old.key~=data.key then assert(restore(key),"Could not restore previous data")end
        local controller=controllers[key]
        if not controller then controller={key=data.key,patch=Patch.new(data.cells)};controllers[key]=controller end
        local values=desired(key,controller)
        if not values then assert(restore(key),"Restore failed");status.message="Normal baseline probabilities";return end
        local applied,reason=controller.patch:apply(values)
        assert(applied,reason)
        status.applied=true;status.error=nil;status.message="Applied to future rolls";status.signature=sig
        if key=="rolls"then status.counts={values[2],values[4],values[6],values[8]}
        else status.preset=preset(Data.skills,skills.preset).label end
    end)
    if not ok then
        local reason=tostring(err):sub(1,1200)
        local restored=restore(key)
        status.error=reason..(not restored and "; "..tostring(status.error) or "");blocked[key]=sig
        log.warn("[GHLQOL] Gogma "..key.." stopped: "..reason)
    end
end
function M.init()
    if initialized then return end;initialized=true
    Layered.init();M.status.layered=Layered.status
    for key,names in pairs(metadata)do
        local ok,err=pcall(function()for _,name in ipairs(names)do assert(sdk.find_type_definition(name),"Missing type "..name)end end)
        R.capabilities["gogma_"..key]=ok
        if not ok then R.errors["gogma_"..key]=tostring(err)end
    end
    re.on_script_reset(function()restore("rolls");restore("skills")end)
end
function M.tick(force)
    M.status.payments=rawget(_G,"__ghl_smithy_cost_status")
    if not force and os.clock()<next_tick then return end
    next_tick=os.clock()+0.5
    -- Disabling must restore our cells even while the singleton is unavailable.
    for key,options in pairs({rolls=rolls,skills=skills})do
        if options.enabled~=true then update(key,nil)end
    end
    if not inspect and rolls.enabled~=true and skills.enabled~=true and not next(controllers)then return end
    local ok,settings=pcall(setting)
    if not ok then M.status.lookup_error=tostring(settings):sub(1,1000);return end
    M.status.lookup_error=nil
    if inspect then
        for _,key in ipairs({"rolls","skills"})do
            local read,data=pcall(model,key,settings)
            M.status[key].available=read and data~=nil
            if read and data then M.status[key].rows=#data.rows;M.status[key].inspection_error=nil
            else M.status[key].inspection_error=not read and tostring(data):sub(1,1000) or "Waiting for game equipment data"end
        end
        inspect=false
    end
    update("rolls",settings);update("skills",settings)
end
local function changed()
    O.save();next_tick=0
end
local function choose(ui,label,key,tbl,entries,custom)
    local ids,labels,selected={},{},1
    for _,entry in ipairs(entries)do ids[#ids+1]=entry.id;labels[#labels+1]=entry.label;if tbl[key]==entry.id then selected=#ids end end
    if custom then ids[#ids+1]="custom";labels[#labels+1]="Custom five-roll split";if tbl[key]=="custom"then selected=#ids end end
    ui.muted(label);imgui.push_item_width(-1)
    local ok,edit,index=pcall(imgui.combo,"##"..label,selected,labels)
    imgui.pop_item_width()
    if not ok then error(edit,0)end
    if edit and ids[index]then tbl[key]=ids[index];changed()end
end
local function toggle(ui,label,tbl,key)
    local edit,value=ui.toggle(label,tbl[key]==true)
    if edit then tbl[key]=value;changed()end
end
local function state(ui,key)
    local s=M.status[key]
    if s.error then ui.muted("Not applied: "..s.error)
    elseif not R.capabilities["gogma_"..key]then ui.muted("Unavailable: "..tostring(R.errors["gogma_"..key]))
    elseif s.waiting then ui.muted(s.waiting)
    elseif s.applied then ui.muted("Active for future rolls")
    elseif s.inspection_error then ui.muted(s.inspection_error)
    else ui.muted("Off: using baseline game/mod values")end
    if s.restore_note then ui.muted(s.restore_note)end
end
function M.draw(ui)
    Layered.draw(ui)
    inspect=true
    ui.section("Gogma reinforcement rolls",function()
        toggle(ui,"Enable roll preset",rolls,"enabled")
        choose(ui,"Roll distribution","preset",rolls,Data.rolls,true)
        if rolls.preset=="custom"then
            local total=0
            for i,label in ipairs({"Attack","Affinity","Sharpness","Element"})do
                local value=R.bound(rolls.custom[i],0,5,0)
                ui.muted(label);local edit,n=ui.slider_float("##gogma_count_"..i,value,0,5,"%.0f")
                if edit then rolls.custom[i]=math.floor(n+0.5);changed()end
                total=total+(tonumber(rolls.custom[i]) or 0)
            end
            ui.muted("Total: "..total.." / 5. Exactly five required.")
        end
        ui.muted("Uses the collection's category limits and weight 60. Use zero Sharpness for weapons that cannot roll it.")
        state(ui,"rolls")
    end,true)
    ui.section("Gogma skill rolls",function()
        toggle(ui,"Enable skill preset",skills,"enabled")
        choose(ui,"Skill combination","preset",skills,Data.skills)
        toggle(ui,"Limit to selected monster bonus",skills,"monster")
        toggle(ui,"Require Lord Soul",skills,"lord_soul")
        ui.muted("Both limits reproduce the collection. With one limit, the other trait follows the baseline probabilities.")
        state(ui,"skills")
    end,true)
    ui.muted("Affects new reinforcement/re-roll generation. Existing saved bonuses are not edited. Off restores the prior table values; matching Fluffy mods still apply if installed.")
    if M.status.lookup_error then ui.muted(M.status.lookup_error)end
    if ui.button("Retry / inspect Gogma data")then blocked={};inspect=true;next_tick=0 end
end
return M
