-- SPDX-License-Identifier: GPL-3.0-or-later
local R=require("GHLQOL.runtime")
local O=require("GHLQOL.options")
local cfg=O.data.extras
local M={status={}}
local melding_rows={}
local function restore_melding()
    for _,entry in ipairs(melding_rows) do pcall(entry.obj.set_field,entry.obj,"_NeedPoint",entry.before) end
    melding_rows={}
end
local function apply_melding()
    if not cfg.melding then if #melding_rows>0 then restore_melding() end;return end
    if #melding_rows>0 then return end
    local mgr=sdk.get_managed_singleton("app.VariousDataManager")
    local setting=mgr:get_field("_Setting"):get_field("_FacilitySetting"):get_field("_MakaSetting")
    for _,f in ipairs(setting:get_type_definition():get_fields()) do
        local t=f:get_type():get_full_name()
        if t=="app.user_data.MakaData" or t=="app.user_data.MakaAccessoryData" then
            local source=f:get_data(setting);local list=source and source:get_field("_Values")
            if list then for i=0,list:call("get_Count")-1 do
                local obj=list:call("get_Item",i);local old=obj:get_field("_NeedPoint")
                if type(old)=="number" and old>1 then
                    melding_rows[#melding_rows+1]={obj=obj:add_ref(),before=old};obj:set_field("_NeedPoint",1)
                end
            end end
        end
    end
end
local function active(key) return cfg[key]==true and R.hunter()~=nil end
local function i32(value) local n=sdk.to_int64(value)&0xffffffff;return n>=0x80000000 and n-0x100000000 or n end
local function multiplier(key) return R.bound(cfg[key.."_scale"],1,10,2) end
function M.init()
    re.on_script_reset(restore_melding)
    R.hook("part_wound","app.cEnemyStockDamage","stockLocal(app.cEnemyStockDamage.cCalcDamage)",function(args,data)
        if not active("parts") and not active("wounds") then return end
        local calc=R.object(args,3)
        local originals={}
        for _,f in ipairs({"PhysicalParts","ElementParts","PhysicalScar","ElementScar"}) do originals[f]=assert(calc:get_field(f),f) end
        data.restore=function()for f,v in pairs(originals)do calc:set_field(f,v)end end
        for f,v in pairs(originals) do
            local key=f:find("Parts") and "parts" or "wounds"
            if cfg[key] then calc:set_field(f,v*multiplier(key)) end
        end
    end,function(retval)return retval end)
    R.hook("world_time","app.cGameCountData_Override","update(System.Single, app.EnvironmentManager.MULTIPLAY_TYPE)",function(args)
        if active("world_time") then args[3]=sdk.float_to_ptr(sdk.to_float(args[3])*R.bound(cfg.world_time_scale,0,10,1)) end
    end)
    R.hook("ai_pause","app.cEmAIUpdateBTable","update()",function()
        if active("ai_pause") then return sdk.PreHookResult.SKIP_ORIGINAL end
    end)
    R.hook("voucher","app.savedata.cBasicParam","addTicket(System.Int32)",function(args)
        if active("voucher") and i32(args[3])<0 then args[3]=sdk.to_ptr(0) end
    end)
    R.hook("skill_timers","app.cHunterSkillParamInfo","update(System.Single)",function(args)
        if active("skill_timers") and R.same(R.object(args):get_field("_HunterSkill"),R.local_field("_Skill")) then args[3]=sdk.float_to_ptr(0) end
    end)
    R.hook("faint_registration","app.cQuestDirector","applyQuestPlDie(System.Int32, System.Boolean)",function()
        if active("faint_registration") then return sdk.PreHookResult.SKIP_ORIGINAL end
    end)
    R.hook("investigation","app.cSaveDataHelper_QuestParam","decreaseRemainingNum(System.Int32, app.cSaveDataHelper_QuestParam.QUEST_SAVEDATA_TYPE)",function()
        if active("investigation") then return sdk.PreHookResult.SKIP_ORIGINAL end
    end)
    R.hook("reward_rolls","app.RewardUtilBase","getRewardLotCount(System.Collections.Generic.List`1<app.user_data.RewardLotProbabilityTable.cData>)",function(_,data)
        data.active=active("reward_rolls")
    end,function(retval,data)
        local n=sdk.to_int64(retval)
        if data.active and n>0 and n<100 then return sdk.to_ptr(math.min(100,math.floor(n*multiplier("reward_rolls")))) end
        return retval
    end)
    R.hook("free_artian","app.savedata.cEquipParam","removeArtianPartsBox(app.ArtianUtil.cPartsData, System.Int32)",function(args)
        if active("free_artian") then args[4]=sdk.to_ptr(0) end
    end)
    R.hook("artian_stock","app.ArtianUtil.cPartsData","get_Num()",function(_,data)data.active=active("artian_stock")end,function(retval,data)
        local n=sdk.to_int64(retval)
        if data.active and n>0 then return sdk.to_ptr(math.max(n,99)) end
        return retval
    end)
    R.hook("carve","app.cRewardContainer","pick()",function(args,data)
        if active("carve") then data.obj=R.object(args);data.before=data.obj:get_field("<PickedCount>k__BackingField") end
    end,function(retval,data)
        if data.obj then data.obj:set_field("<PickedCount>k__BackingField",data.before) end
        return retval
    end)
    R.hook("craft_recipes","app.ItemRecipeUtil","hasRecipe(app.ItemDef.ID)",function(_,data)data.active=active("craft_recipes")end,function(retval,data)
        return data.active and sdk.to_ptr(1) or retval
    end)
    for _,t in ipairs({"app.user_data.MakaData.cData","app.user_data.MakaAccessoryData.cData"}) do
        R.hook("melding_"..t,t,"get_NeedPoint()",function(_,data)data.active=active("melding")end,function(retval,data)
            return data.active and sdk.to_ptr(1) or retval
        end)
    end
    R.hook("fish","app.cEmModuleFishing","pickReward()",function(args,data)
        if not active("fish") then return end
        data.obj=R.object(args);data.size=data.obj:get_field("_Size");data.weight=data.obj:get_field("_Weight")
        data.obj:set_field("_Size",math.floor(data.size*multiplier("fish_size")))
        data.obj:set_field("_Weight",math.floor(data.weight*multiplier("fish_weight")))
        data.restore=function() data.obj:set_field("_Size",data.size);data.obj:set_field("_Weight",data.weight) end
    end,function(retval)return retval end)
    R.hook("palico_xp","app.savedata.cOtomoParam","calcExpResult()",function(args)
        if not active("palico_xp") then return end
        local obj=R.object(args);local stock=obj:get_field("StockExp");local n=stock:call("decode")
        if n>0 then stock:call("encode",math.min(10000000,math.floor(n*multiplier("palico_xp"))));obj:set_field("StockExp",stock) end
    end)
    R.hook("highlight","app.GUIAccessIconControl","isExistDetection(app.InteractController)",function(_,data)data.active=active("highlight")end,function(retval,data)
        return data.active and sdk.to_ptr(1) or retval
    end)
end
local next_time=0
function M.tick()
    if os.clock()<next_time then return end;next_time=os.clock()+0.25
    local ok,err=pcall(function()
        if not cfg.melding then restore_melding() end
        local s=R.local_status();if not s then return end
        apply_melding()
        if cfg.no_hunger then s:get_field("_Stamina"):set_field("_AutoMaxReduceTimer",0) end
        if cfg.no_poison or cfg.no_bleed or cfg.no_conditions then
            local cond=s:get_field("_BadConditions")
            local fields={"_Poison","_Bleed"}
            if cfg.no_conditions then fields={"_Poison","_Bleed","_Stench","_Blast","_DefDown","_Sleep","_Ex00","_Ex01","_Fire","_Elec","_Water","_Ice","_Dragon"} end
            for _,f in ipairs(fields) do
                if cfg.no_conditions or f=="_Poison" and cfg.no_poison or f=="_Bleed" and cfg.no_bleed then
                    local c=cond:get_field(f)
                    if c and c:call("get_IsActive") then c:call("forceDeactivate") end
                end
            end
        end
    end)
    M.status.error=not ok and tostring(err):sub(1,1000) or nil
end
function M.draw(ui)
    ui.section("Survival",function()
        O.toggle(ui,"no_hunger","Stop hunger decrease",cfg)
        O.toggle(ui,"no_poison","Prevent poison",cfg)
        O.toggle(ui,"no_bleed","Prevent bleeding",cfg)
        O.toggle(ui,"no_conditions","Clear blights and common adverse conditions",cfg)
        O.toggle(ui,"skill_timers","Pause active skill timers",cfg,"skill_timers")
    end,true)
    ui.section("Boss rush and exploration",function()
        for _,e in ipairs({{"parts","Part damage multiplier","part_wound"},{"wounds","Wound damage multiplier","part_wound"},{"reward_rolls","Reward roll multiplier","reward_rolls"},{"palico_xp","Palico XP multiplier","palico_xp"}}) do
            O.toggle(ui,e[1],e[2],cfg,e[3]);if cfg[e[1]] then O.slider(ui,e[1].."_scale","Multiplier##"..e[1],cfg,1,10,2,"%.1fx") end
        end
        O.toggle(ui,"ai_pause","Pause monster AI",cfg,"ai_pause")
        O.toggle(ui,"highlight","Highlight interactables",cfg,"highlight")
        O.toggle(ui,"world_time","Change world time speed",cfg,"world_time")
        if cfg.world_time then O.slider(ui,"world_time_scale","Time speed (0 pauses)",cfg,0,10,1,"%.2fx") end
        ui.muted("Shared-world changes depend on game host authority. Reward multipliers affect applicable rolls, beyond lucky-voucher bonuses.")
    end,true)
    ui.section("Crafting and quest resources",function()
        for _,e in ipairs({{"voucher","Preserve lucky vouchers","voucher"},{"investigation","Preserve investigation uses","investigation"},{"free_artian","Preserve Artian materials","free_artian"},{"artian_stock","Plentiful owned Artian parts","artian_stock"},{"carve","Repeat carcass rewards","carve"},{"craft_recipes","Show all crafting recipes","craft_recipes"}}) do O.toggle(ui,e[1],e[2],cfg,e[3]) end
        O.toggle(ui,"faint_registration","Skip quest faint registration (experimental)",cfg,"faint_registration")
        ui.muted("Faint registration skips the game's quest-faint handler. Trial separately with your party before relying on it for boss rushes.")
        O.toggle(ui,"melding","Melding costs one point",cfg,"melding_app.user_data.MakaData.cData")
    end,false)
    ui.section("Fishing",function()
        O.toggle(ui,"fish","Override fish size and weight",cfg,"fish")
        if cfg.fish then
            O.slider(ui,"fish_size_scale","Size multiplier",cfg,1,10,2,"%.1fx")
            O.slider(ui,"fish_weight_scale","Weight multiplier",cfg,1,10,2,"%.1fx")
        end
    end,false)
    if M.status.error then ui.muted(M.status.error) end
end
return M
