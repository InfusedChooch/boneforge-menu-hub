-- SPDX-License-Identifier: GPL-3.0-or-later
local R=require("GHLQOL.runtime")
local O=require("GHLQOL.options")
local cfg=O.data.weapons
local M={}
local function support() return package.loaded["GHLQOL.support"] end
local overlaps={
    bow_charge={"bow","charge_level"},hammer_charge={"hammer","instant_charge","charge_level"},
    hammer_super={"hammer","instant_charge","super_charge_level"},gunlance_charge={"gunlance","instant_charge"},
    switch_axe={"switch_axe","powered_axe"},switch_sword={"switch_axe","max_sword_charge"},
    cb_axe={"charge_blade","axe_enhanced"},cb_sword={"charge_blade","sword_enhanced"},cb_shield={"charge_blade","shield_enhanced"},
    ls_spirit={"long_sword","max_spirit_gauge"},hbg_energy={"heavy_bowgun","max_special_ammo"},
    hbg_snipe={"heavy_bowgun","max_special_ammo"},
}
local function active(key)
    if not cfg[key] then return false end
    local s,row=support(),overlaps[key]
    if s and row then for i=2,#row do
        local value=s.option(row[1],row[i])
        if value==true or type(value)=="number" and value>=0 then return false end
    end end
    return true
end
local function weapon(kind)
    local h=R.hunter()
    if not h or kind and h:call("get_WeaponType")~=kind then return nil end
    return h:call("get_WeaponHandling")
end
local function local_weapon(obj,kind) return R.same(obj,weapon(kind)) end
local function hbg_energy_value(energy)
    local value=energy:get_field("_CurrentEnergy")
    assert(type(value)=="number" and value==value and value~=math.huge and value~=-math.huge,"Unreadable HBG energy")
    return value
end
local timers={
    {"bow_charge","Bow charge speed",11,"updateCharge(System.Boolean)","_ChargeTimer","scale"},
    {"hammer_charge","Hammer charge speed",4,"updateChargeForce()","_ChargeTimer","scale"},
    {"hammer_super","Hammer super-charge speed",4,"doUpdate()","_SuperChargeTimer","scale"},
    {"gunlance_charge","Gunlance charged-shell speed",7,"chargeShotProcess()","_ChargeShotElapsedTimer","scale"},
    {"switch_axe","Pause Switch Axe axe enhancement",8,"doUpdate()","_AxeEnhancedTimer","freeze"},
    {"switch_sword","Pause Switch Axe sword awakening",8,"doUpdate()","_SwordAwakeTimer","freeze"},
    {"cb_axe","Pause Charge Blade axe enhancement",9,"doUpdate()","_AxeEnhancedTimer","freeze"},
    {"cb_sword","Pause Charge Blade sword enhancement",9,"doUpdate()","_SwordEnhancedTimer","freeze"},
    {"cb_shield","Pause Charge Blade shield enhancement",9,"doUpdate()","_ShieldEnhancedTimer","freeze"},
}
function M.init()
    for _,entry in ipairs(timers) do
        local key,_,kind,method,field,mode=table.unpack(entry)
        R.hook(key,string.format("app.cHunterWp%02dHandling",kind),method,function(args,data)
            if not active(key) then return end
            local obj=R.object(args)
            if local_weapon(obj,kind) then data.obj=obj;data.before=assert(obj:get_field(field),field) end
        end,function(retval,data)
            if not data.obj then return retval end
            local after=data.obj:get_field(field)
            if mode=="scale" and after>data.before then
                data.obj:set_field(field,data.before+(after-data.before)*R.bound(cfg[key.."_scale"],1,10,2))
            elseif mode=="freeze" and data.before>0 and after<data.before then data.obj:set_field(field,data.before) end
            return retval
        end)
    end
    R.hook("ls_spirit","app.cValueHolderF","sub(System.Single, System.Boolean)",function(args)
        if not active("ls_spirit") then return end
        local w=weapon(3);local gauge=w and w:get_field("<RenkiGauge>k__BackingField")
        if R.same(R.object(args),gauge) then args[3]=sdk.float_to_ptr(0) end
    end)
    -- CE 5.7.1 identifies the consumption methods. Keep restoration within the
    -- local Gatling call so other update-time changes and refills remain native.
    R.hook("hbg_energy","app.cHunterWp12Handling","shootShellGatling(via.vec3)",function(args,data)
        if not active("hbg_energy") or not local_weapon(R.object(args),12) then return end
        data.weapon=R.object(args)
        data.energy=data.weapon:get_field("_EnergyBulletInfo")
        if data.energy then data.before=hbg_energy_value(data.energy) end
    end,function(retval,data)
        if not data.energy or not active("hbg_energy") or not local_weapon(data.weapon,12)
            or not R.same(data.energy,data.weapon:get_field("_EnergyBulletInfo")) then return retval end
        if hbg_energy_value(data.energy)<data.before then data.energy:set_field("_CurrentEnergy",data.before) end
        return retval
    end)
    R.hook("hbg_snipe","app.Wp12Def.cSnipeAmmo","subAmmo(System.Int32)",function(args)
        if not active("hbg_snipe") then return end
        local w=weapon(12);local ammo=w and w:get_field("_SnipeAmmo")
        if not R.same(R.object(args),ammo) then return end
        -- Int32 arguments may be zero-extended. Preserve zero and negative
        -- adjustments, including reload/refill paths, while the method still runs.
        local amount=sdk.to_int64(args[3])&0xffffffff
        if amount>0 and amount<0x80000000 then args[3]=sdk.to_ptr(0) end
    end)
    R.hook("gun_ammo","app.cAmmo","subAmmo(System.Int32)",function(args)
        if not cfg.gun_ammo then return end
        local h=R.hunter();if not h then return end
        local kind=h:call("get_WeaponType");if kind~=12 and kind~=13 and kind~=7 then return end
        local s=support();local group=kind==7 and "gunlance" or kind==12 and "heavy_bowgun" or "light_bowgun"
        if s and s.option(group,"unlimited_ammo") then return end
        local w=h:call("get_WeaponHandling")
        local ammo=kind==7 and w:get_field("_Ammo") or w:call("getCurrentAmmo")
        if R.same(R.object(args),ammo) then args[3]=sdk.to_ptr(0) end
    end)
    R.hook("ig_gravity","app.HunterCharacter","get_ActionGravityScale()",function(args,data)
        data.active=cfg.ig_gravity and R.same(R.object(args),R.hunter()) and weapon(10)~=nil
    end,function(retval,data)
        if data.active then return sdk.float_to_ptr(sdk.to_float(retval)*R.bound(cfg.ig_gravity_scale,0.1,3,0.5)) end
        return retval
    end)
end
local function selector_width()
    -- REFramework exposes CalcItemWidth rather than GetContentRegionAvail.
    -- A negative width measures the current child, including its scrollbar.
    if type(imgui.push_item_width)~="function" or type(imgui.pop_item_width)~="function" or type(imgui.calc_item_width)~="function" then return nil end
    if not pcall(imgui.push_item_width,-1) then return nil end
    local ok,width=pcall(imgui.calc_item_width)
    local restored=pcall(imgui.pop_item_width)
    if ok and restored and type(width)=="number" and width>0 and width<math.huge then return width end
end
local selected=1
M.status={selected_weapon="Great Sword",parry_visible=false}
function M.draw(ui,menu)
    M.status.parry_visible=false
    local s=support()
    if not s then ui.muted("Weapon support is unavailable");return end
    -- Both menu themes use eight-pixel spacing. If measurement is unavailable,
    -- full-width single rows keep every choice reachable without changing layout.
    local available=selector_width()
    local gap=8
    local columns=available and math.max(1,math.floor((available+gap)/(112+gap))) or 1
    local width=available and (available-(columns-1)*gap)/columns or -1
    local shared_index=#s.weapons+1
    for i=1,shared_index do
        local label=i==shared_index and "Evade / Parry" or s.weapons[i][1]
        if (i-1)%columns~=0 then imgui.same_line() end
        local clicked
        if ui.tab_button then clicked=ui.tab_button(label.."##weapon"..i,selected==i,width)
        else clicked=ui.button(label.."##weapon"..i,width,28) end
        if clicked then selected=i end
    end
    if selected==shared_index then
        M.status.selected_weapon="Evade / Parry"
        M.status.parry_visible=true
        imgui.separator();ui.muted("Evade / Parry")
        if menu.parry then menu.parry.evade_parry()
        else ui.muted("Parry controls are unavailable; see GHLQOL-status.json") end
        return
    end
    local row=s.weapons[selected];local kind=row[4]
    M.status.selected_weapon=row[1]
    imgui.separator();ui.muted(row[1])
    ui.muted("Applies to your current weapon. Fixed-level or instant options take precedence over matching speed/timer controls.")
    if kind==0 then
        M.status.parry_visible=true
        if menu.parry then menu.parry.great_sword()
        else ui.muted("Parry controls are unavailable; see GHLQOL-status.json") end
    end
    local blocked=kind==0 and s.status.gs_native_priority
    if blocked then
        ui.muted("Great Sword enhancements above are active. Alternate charge overrides below are disabled; adjust the enhancements above to use them.")
        imgui.begin_disabled(true)
    end
    s.draw_group(ui,row[3])
    if blocked then imgui.end_disabled() end
    if kind==1 then ui.muted("Buffer has no Sword & Shield-specific overrides. General buffs and Parry timing controls remain available.") end
    for _,entry in ipairs(timers) do
        local key,label,weapon_kind,_,_,mode=table.unpack(entry)
        if kind==weapon_kind then
            O.toggle(ui,key,label,cfg,key)
            if mode=="scale" and cfg[key] then O.slider(ui,key.."_scale","Multiplier##"..key,cfg,1,10,2,"%.1fx") end
        end
    end
    for _,entry in ipairs({{"ls_spirit","Preserve Long Sword spirit gauge",3},{"hbg_energy","Preserve Heavy Bowgun energy",12},{"hbg_snipe","Preserve Heavy Bowgun snipe ammo",12}}) do
        if kind==entry[3] then O.toggle(ui,entry[1],entry[2],cfg,entry[1]) end
    end
    if kind==7 or kind==12 or kind==13 then O.toggle(ui,"gun_ammo","Do not consume loaded gun ammo",cfg,"gun_ammo") end
    if kind==10 then
        O.toggle(ui,"ig_gravity","Override Insect Glaive action gravity",cfg,"ig_gravity")
        if cfg.ig_gravity then O.slider(ui,"ig_gravity_scale","Gravity multiplier",cfg,0.1,3,0.5,"%.2fx") end
    end
end
return M
