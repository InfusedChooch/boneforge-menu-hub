-- GHL host for the private Buffer mechanics; settings and UI are independent.
local E=require("GHLQOL.buffer_engine")
local C=require("GHLQOL.vendor.Buffer.Misc.Config")
local L=require("GHLQOL.vendor.Buffer.Misc.Language")
local O=require("GHLQOL.options")
local R=require("GHLQOL.runtime")
local M={status=E.status,modules={}}
local next_check=0
function M.tick()
    if os.clock()<next_check then return end;next_check=os.clock()+1
    local gs=C.read_file("WpSeries_GreatSword_Config.json") or {}
    E.blocked=E.blocked or {}
    E.blocked.great_sword=gs.ReduceChargeTime or gs.ExtendChargeTime or gs.AttackEnhance or false
    M.status.gs_native_priority=E.blocked.great_sword
end
M.weapons={
    {"Great Sword","GreatSword","great_sword",0},
    {"Sword & Shield","SwordAndShield","sword_and_shield",1},
    {"Dual Blades","DualBlades","dual_blades",2},
    {"Long Sword","Longsword","long_sword",3},
    {"Hammer","Hammer","hammer",4},
    {"Hunting Horn","HuntingHorn","hunting_horn",5},
    {"Lance","Lance","lance",6},
    {"Gunlance","Gunlance","gunlance",7},
    {"Switch Axe","SwitchAxe","switch_axe",8},
    {"Charge Blade","ChargeBlade","charge_blade",9},
    {"Insect Glaive","InsectGlaive","insect_glaive",10},
    {"Bow","Bow","bow",11},
    {"Heavy Bowgun","HeavyBowgun","heavy_bowgun",12},
    {"Light Bowgun","LightBowgun","light_bowgun",13},
}
function M.migrate()
    local own=C.get_config()
    if own._ghl_migrated then return end
    local old=C.read_file("Buffer/Config.json") or {}
    local char=old.character or {}
    for k,v in pairs(char.item_buffs or {}) do if v then O.data.buffs[k]=true;O.data.buffs.maintain=true end end
    for oldkey,newkey in pairs({instant_cooldown="mantle_cooldown",unlimited_duration="mantle_duration"}) do
        if char.mantles and char.mantles[oldkey] then O.data.buffs[newkey]=true end
    end
    for oldkey,newkey in pairs({no_ticket_consumption="free_vouchers",no_ingredient_consumption="free_ingredients",unlimited_timer="freeze_timer"}) do
        if char.meals and char.meals[oldkey] then O.data.meals[newkey]=true end
    end
    O.save();assert(not O.status.save_error,"Cannot save transferred meal/buff options")
    -- Current GHL pages exclusively own these three groups.
    char.item_buffs={};char.mantles={};char.meals={}
    old.character=char;old.window=nil;old._ghl_migrated=true
    C.data=old;C.save_section({})
    M.status.migrated=true
end
function M.init()
    M.migrate()
    M.tick()
    local entries={{"Character","character"},{"Miscellaneous","miscellaneous"}}
    for _,row in ipairs(M.weapons) do entries[#entries+1]={row[2],row[3]} end
    for _,entry in ipairs(entries) do
        local name,key=entry[1],entry[2]
        E.context=key
        local ok,module=pcall(require,"GHLQOL.vendor.Buffer.Modules."..name)
        if ok then
            local started,err=pcall(module.init,module)
            if started then M.modules[key]=module;M.status.modules[key]=true
            else M.status.errors[key]=tostring(err):sub(1,1000) end
        else M.status.errors[key]=tostring(module):sub(1,1000) end
        E.context=nil
    end
    re.on_script_reset(function()
        for _,module in pairs(M.modules) do if module.reset then pcall(module.reset,module) end end
    end)
    re.on_config_save(function()
        for _,module in pairs(M.modules) do pcall(module.save_config,module) end
    end)
end
function M.option(group,key)
    local module=M.modules[group]
    return not E.external() and M.status.modules[group] and module and module.data[key]
end
local function sorted(tbl)
    local keys={};for k in pairs(tbl) do keys[#keys+1]=k end;table.sort(keys);return keys
end
local limits={
    charge_level={-1,3},super_charge_level={-1,2},counter_charge_level={-1,3},rush_level={-1,1},
    shell_level={-1,2},aura_level={-1,3},power={-1,200},speed={-1,100},recovery={-1,100},
    _charge_time={0,100},attack={-1,5000},defence={-1,5000},critical_chance={-1,100},
    elemental_attack={-1,2000},element={-1,9},state={-1,2},
}
local labels={
    ["character.health.healing"]="Recover red health",
    ["character.stats.use_bonus_mode"]="Add bonuses to existing stats",
    ["character.blights_and_conditions.conditions.all"]="All conditions",
    ["character.blights_and_conditions.blights.all"]="All blights",
}
local function controls(ui,module,tbl,prefix)
    local changed=false
    for _,key in ipairs(sorted(tbl)) do
        local value=tbl[key];local path=prefix.."."..key
        local label=labels[path] or L.get(path:gsub("%._charge_time$",".charge_time"))
        if key:match("^_.*_value$") then label=key:match("^_(.*)_value$"):gsub("^%l",string.upper).." resistance" end
        if type(value)=="boolean" then
            local update,new=ui.toggle(label,value)
            if update then tbl[key]=new;changed=true end
        elseif type(value)=="number" then
            if path=="character.stats.element" then
                local elements={{-1,"Disabled"},{0,"None"},{1,"Fire"},{2,"Water"},{3,"Ice"},{4,"Thunder"},{5,"Dragon"},{6,"Poison"},{7,"Paralysis"},{8,"Sleep"},{9,"Blast"}}
                if ui.bind_combo("Weapon element",tbl,key,elements) then changed=true end
                goto continue
            end
            local range=limits[key] or {-100,100}
            if module.title=="hammer" and key=="charge_level" then range={-1,2} end
            if module.title=="gunlance" and key=="shell_level" then range={-1,6} end
            ui.muted(label..(range[1]==-1 and " (-1 disables)" or ""))
            local update,new=ui.slider_float("##"..path,value,range[1],range[2],"%.0f")
            if update then tbl[key]=math.floor(R.bound(new,range[1],range[2],value)+0.5);changed=true end
        elseif type(value)=="table" then
            ui.section(L.get(path..".title"),function()if controls(ui,module,value,path) then changed=true end end,false)
        end
        ::continue::
    end
    return changed
end
function M.draw_group(ui,key,data,prefix)
    local module=M.modules[key]
    if not module then ui.muted("Unavailable: "..tostring(M.status.errors[key]));return end
    if controls(ui,module,data or module.data,prefix or key) then
        if module.update_cached_modifications then
            local ok,err=pcall(module.update_cached_modifications,module)
            if not ok then M.status.errors[key..":settings"]=tostring(err) end
        end
        local ok,err=pcall(module.save_config,module)
        if not ok then M.status.errors[key..":save"]=tostring(err) end
    end
end
function M.draw(ui)
    if E.external() then ui.muted("Original Buffer is loaded. Disable it in Vortex and restart; the private component is suspended.") end
    ui.muted("Health, protection and item-use options for your hunter. Item buffs and mantles are in Buffs; weapon-specific options are in Weapons.")
    local module=M.modules.character
    if module then
        local d=module.data
        for _,entry in ipairs({{"Health","health"},{"Stamina","stamina"},{"Blights and conditions","blights_and_conditions"},{"Stats","stats"}}) do
            ui.section(entry[1],function()M.draw_group(ui,"character",d[entry[2]],"character."..entry[2])end,false)
        end
        ui.section("Inventory and protection",function()
            for _,key in ipairs({"invincible","unlimited_sharpness","unlimited_consumables","unlimited_slingers"}) do
                local change,value=ui.toggle(L.get("character."..key),d[key])
                if change then d[key]=value;module:save_config() end
            end
            ui.muted("Consumables and slinger preservation are available in party hunts. Keep the overlapping Hunter cheats off.")
        end,true)
    end
    ui.section("Akuma and other abilities",function()M.draw_group(ui,"miscellaneous")end,false)
    ui.section("Component status",function()
        for _,key in ipairs(sorted(M.status.modules)) do ui.muted(key..": "..tostring(M.status.modules[key])) end
        for key,err in pairs(M.status.errors) do ui.muted(key..": "..err) end
        ui.muted("Private Buffer 1.1.6 mechanics by Bimmr; hosted by GHL QOL. Original keybinds and popout are not loaded.")
    end,false)
end
return M
