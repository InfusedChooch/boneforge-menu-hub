-- SPDX-License-Identifier: GPL-3.0-or-later
-- Native item-buff fields/methods verified against the installed Buffer engine.
local R=require("GHLQOL.runtime")
local O=require("GHLQOL.options")
local M={status={updates=0}}
local cfg=O.data.buffs
function M.init()
    R.hook("mantles","app.mcActiveSkillController","updateMain()",function(args)
        if not cfg.mantle_cooldown and not cfg.mantle_duration then return end
        local obj=R.object(args)
        if not R.same(obj:get_field("_Hunter"),R.hunter()) then return end
        local skills=obj:get_field("_ActiveSkills")
        if not skills then return end
        for _,mantle in pairs(skills) do
            if mantle then
                if cfg.mantle_cooldown and not R.buffer("mantles","instant_cooldown") and not mantle:call("get_IsUse") and mantle:call("get_Timer")>0 then mantle:call("crearTime")
                elseif cfg.mantle_duration and not R.buffer("mantles","unlimited_duration") and mantle:call("get_IsUse") then mantle:call("setTime",mantle:call("get_MaxEffectiveTime")) end
            end
        end
    end)
end
M.items={
    {"might_seed","Might Seed","_Kairiki_Timer",180},
    {"might_pill","Might Pill","_Kairiki_G_Timer",90},
    {"adamant_seed","Adamant Seed","_Nintai_Timer",180},
    {"adamant_pill","Adamant Pill","_Nintai_G_Timer",90},
    {"demon_powder","Demon Powder","_KijinPowder_Timer",180},
    {"hardshell_powder","Hardshell Powder","_KoukaPowder_Timer",180},
    {"dash_juice","Dash Juice","_DashJuice_Timer",600},
    {"hot_drink","Hot Drink","_HotDrink_Timer",600},
    {"cool_drink","Cool Drink","_CoolerDrink_Timer",600},
    {"imunizer","Immunizer","_Immunizer_Timer",300},
    {"demon_drug","Demondrug","_KijinDrink",nil,4},
    {"mega_demondrug","Mega Demondrug","_KijinDrink_G",nil,5},
    {"armor_skin","Armorskin","_KoukaDrink",nil,10},
    {"mega_armorskin","Mega Armorskin","_KoukaDrink_G",nil,11},
}
function M.apply(once)
    local s=R.local_status();assert(s,"Enter the field with your hunter first")
    local buff=assert(s:get_field("_ItemBuff"),"Item buff status unavailable")
    for _,item in ipairs(M.items) do
        local key,_,field,duration,effect=table.unpack(item)
        if cfg[key] and (once or not R.buffer("item_buffs",key)) then
            if effect then
                if buff:get_field(field):get_field("_Timer")<=0 then buff:call("activateItemBuff",effect,1.0,1.0) end
            else buff:set_field(field,duration) end
        end
    end
    M.status.updates=M.status.updates+1
    return "Selected item buffs applied"
end
function M.heal()
    local s=R.local_status();assert(s,"Enter the field with your hunter first")
    local health=assert(s:get_field("_Health"),"Health unavailable")
    assert(not health:call("get_IsDead"),"Cannot heal a fainted hunter")
    health:call("setHealthNormalized",1.0)
    return "Health restored"
end
function M.take_over()
    local b=package.loaded["Buffer.Modules.Character"]
    assert(type(b)=="table" and b.data and b.data.item_buffs,"Buffer is not loaded")
    local old={}
    for _,item in ipairs(M.items) do
        local key=item[1];old[key]=b.data.item_buffs[key]
        cfg[key]=cfg[key] or old[key]==true
    end
    cfg.maintain=true
    O.save();assert(not O.status.save_error,"Cannot save GHL buff selections")
    for _,item in ipairs(M.items) do b.data.item_buffs[item[1]]=false end
    local ok,err=pcall(b.save_config,b)
    if not ok then for k,v in pairs(old) do b.data.item_buffs[k]=v end;error(err) end
    return "Selected buffs transferred; Buffer item buffs are off"
end
local next_time=0
function M.tick()
    if not cfg.maintain or os.clock()<next_time then return end
    next_time=os.clock()+0.25
    local ok,s=pcall(R.local_status)
    if not ok or not s then return end
    local read,err=pcall(M.apply,false)
    M.status.error=not read and tostring(err):sub(1,1000) or nil
end
local timers, next_read, timer_owner = {}, 0, nil
local function draw_timers(ui)
    local ok,status=pcall(R.local_status)
    if not ok or not status then
        timers={};timer_owner=nil;ui.muted("Load your hunter to see buff timers.");return
    end
    local owner=status:get_address()
    if owner~=timer_owner or os.clock()>=next_read then
        timer_owner=owner;next_read=os.clock()+0.25;timers={}
        local buff=status:get_field("_ItemBuff")
        for _,item in ipairs(M.items) do
            local read,t=pcall(function()
                local value=buff:get_field(item[3])
                if item[5] then return value:get_field("_Timer") end
                return value
            end)
            if not read or type(t)~="number" or t~=t or math.abs(t)==math.huge then
                timers[#timers+1]=item[2].." timer unavailable"
            elseif t>0 then
                local seconds=math.ceil(t)
                timers[#timers+1]=string.format("%s  %d:%02d",item[2],seconds//60,seconds%60)
            end
        end
    end
    if #timers==0 then ui.muted("No active item buffs.") end
    for _,line in ipairs(timers) do ui.muted(line) end
end
function M.draw(ui,menu)
    local in_field=O.in_field()
    if not in_field then ui.muted("Selections save now and apply when your hunter is loaded.")end
    ui.section("Active buff timers",function() draw_timers(ui) end,true)
    ui.section("Item buffs",function()
        O.toggle(ui,"maintain","Keep selected buffs active",cfg)
        ui.muted("Select the seeds, pills, powders and drinks you want. Turning maintenance off lets their normal timers run down.")
        for _,item in ipairs(M.items) do O.toggle(ui,item[1],item[2],cfg) end
        if O.button(ui,"Apply selected buffs once",in_field) then O.action(menu,function()return M.apply(true)end) end
        if O.button(ui,"Heal now",in_field) then O.action(menu,M.heal) end
    end,true)
    if type(package.loaded["Buffer.Modules.Character"])=="table" then ui.section("Import from original Buffer",function()
        ui.muted("Copies Buffer's selected item buffs into this page, then switches off only Buffer's item-buff options. Other Buffer features stay as they are.")
        if ui.button("Take over item buffs from Buffer") then O.action(menu,M.take_over) end
    end,false) end
    ui.section("Mantles",function()
        O.toggle(ui,"mantle_cooldown","Instant mantle cooldown",cfg,"mantles")
        O.toggle(ui,"mantle_duration","Keep active mantles running",cfg,"mantles")
        ui.muted("Maintains a mantle after you activate it. Item buffs and mantle choices save automatically.")
    end,false)
    if M.status.error then ui.muted(M.status.error) end
end
return M
