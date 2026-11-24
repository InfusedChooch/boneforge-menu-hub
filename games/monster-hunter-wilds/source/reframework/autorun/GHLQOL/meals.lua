-- SPDX-License-Identifier: GPL-3.0-or-later
local R=require("GHLQOL.runtime")
local O=require("GHLQOL.options")
local M={status={applied=0}}
local cfg=O.data.meals
local pending
local requested
local cached,cache_until
local function dining()
    local mgr=assert(sdk.get_managed_singleton("app.VariousDataManager"),"Waiting for game data")
    return mgr:get_field("_Setting"):get_field("_FacilitySetting"):get_field("_FacilityDiningSetting")
end
local function values(key) return dining():get_field(key):get_field("_Values") end
local function row(key,index)
    local rows=values(key)
    assert(type(index)=="number" and index>=0 and index<rows:call("get_Count"),"Meal selection is no longer valid")
    return rows:call("get_Item",index)
end
function M.catalog()
    if cached and os.clock()<(cache_until or 0) then return cached end
    local result={bases={},main={{-1,"None"}},seasoning={{-1,"None"}},canteen={},skills={{-1,"None"}}}
    local bases=values("_MealData")
    for i=0,bases:call("get_Count")-1 do
        local v=bases:call("get_Item",i)
        result.bases[#result.bases+1]={i,string.format("Base %d: attack +%d, defence +%d, resistance +%d",i+1,v:call("get_Attack"),v:call("get_Defence"),v:call("get_AttrResist"))}
    end
    local foods=values("_FoodData")
    for i=0,foods:call("get_Count")-1 do
        local food=foods:call("get_Item",i);local id=food:call("get_ItemId")
        local list=food:call("get_IsMain") and result.main or result.seasoning
        list[#list+1]={id,R.item_name(id)}
    end
    local lobby=values("_MealDataLobby")
    for i=0,lobby:call("get_Count")-1 do
        local v=lobby:call("get_Item",i)
        result.canteen[#result.canteen+1]={i,R.text(v:call("get_Title"))}
    end
    local skills=values("_MealSkill")
    for i=0,skills:call("get_Count")-1 do
        local v=skills:call("get_Item",i);result.skills[#result.skills+1]={v:call("get_MealSkill"),R.text(v:call("get_Name"))}
    end
    cached,cache_until=result,os.clock()+5
    M.status.catalogue={bases=#result.bases,ingredients=#result.main+#result.seasoning-2,canteen=#result.canteen,skills=#result.skills-1}
    return result
end
function M.build(kind,selection)
    assert(R.hunter(),"Meal construction requires a loaded local hunter")
    local cfg=selection or cfg
    local effect=assert(sdk.create_instance("app.cMealEffect"),"Cannot create meal effect"):add_ref()
    effect:call(".ctor()")
    if kind=="canteen" then
        effect:call("copyFrom(app.user_data.MealDataLobby.cData, System.Boolean)",row("_MealDataLobby",cfg.canteen or 0),true)
    else
        effect:call("copyFrom(app.user_data.MealData.cData, System.Boolean)",row("_MealData",cfg.base or 0),true)
        for _,id in ipairs({cfg.main or -1,cfg.seasoning or -1}) do
            if id~=-1 then
                local food=assert(R.static("app.MealUtil","getFoodDataFromItemId(app.ItemDef.ID)",id),"Ingredient no longer exists")
                effect:call("addParam(app.user_data.FoodData.cData, System.Boolean)",food,true)
            end
        end
    end
    if cfg.custom_duration then effect:call("setDurationSec",R.bound(cfg.minutes,1,120,50)*60) end
    if cfg.custom_skills then
        local valid={};for _,entry in ipairs(M.catalog().skills) do valid[entry[1]]=true end
        effect:call("resetMealSkill")
        local used={}
        for _,key in ipairs({"skill1","skill2","skill3"}) do
            local id=cfg[key] or -1
            assert(valid[id],"Selected meal skill no longer exists")
            if id~=-1 and not used[id] then effect:call("addSkill",id);used[id]=true end
        end
    end
    return effect
end
function M.apply(kind)
    local s,h=R.local_status();assert(s and h,"Enter the field with your hunter first")
    assert(not requested,"A meal request is already pending")
    local selection={};for k,v in pairs(cfg) do selection[k]=v end
    requested={kind=kind,hunter=h:get_address(),expires=os.clock()+10,selection=selection}
    M.status.state="Meal queued for the game update"
    return M.status.state
end
local function process_request()
    if not requested then return end
    local request=requested;requested=nil
    local ok,err=pcall(function()
    local s,h=R.local_status();assert(s and h and h:get_address()==request.hunter,"Hunter changed; meal request cancelled")
    assert(os.clock()<request.expires,"Meal request expired")
    local current=s:get_field("_MealEffect");assert(current,"Meal status unavailable")
    local effect=M.build(request.kind,request.selection)
    current:call("setMealEffect(app.cMealEffect, System.Boolean)",effect,true)
    assert(current:call("get_IsEffectActive"),"Game did not activate the meal")
    M.status.applied=M.status.applied+1
    end)
    M.status.state=ok and "Meal applied without consuming vouchers or ingredients" or tostring(err):sub(1,500)
end
local function arm_ingredients(args)
    pending=nil
    if not cfg.free_ingredients or R.buffer("meals","no_ingredient_consumption") or not R.hunter() then return end
    local facility=R.object(args)
    local info=facility:call("get_MealInfo")
    local ids={}
    local base=sdk.find_type_definition("app.FacilityDining"):get_field("MEAL_ITEM"):get_data(nil)
    assert(type(base)=="number" and base>=0,"Portable-food item unavailable")
    ids[base]=1
    local foods=info and info:call("get_AddFoods")
    if foods then for i=0,foods:call("get_Count")-1 do local id=foods:call("get_Item",i);ids[id]=(ids[id] or 0)+1 end end
    pending={ids=ids,until_time=os.clock()+120}
end
function M.init()
    R.hook("meal_apply","app.GUIManager","update()",process_request)
    R.hook("meal_voucher","app.FacilityDining","executeLobbyCore(app.DiningDef.LOBBY_MENU_ID)",function(args)
        if cfg.free_vouchers and not R.buffer("meals","no_ticket_consumption") and R.hunter() then R.object(args):call("set_TicketItem",-1) end
    end)
    R.hook("meal_begin","app.FacilityDining","execute(app.cMealEffect, System.Int32)",arm_ingredients)
    R.hook("meal_cost","app.ItemUtil","changeItemNum(app.ItemDef.ID, System.Int16, app.ItemUtil.STOCK_TYPE)",function(args)
        if not pending then return end
        if not cfg.free_ingredients or os.clock()>pending.until_time or not R.hunter() then pending=nil;return end
        local id=sdk.to_int64(args[2]);local count=sdk.to_int64(args[3])&0xffff
        if count>=32768 then count=count-65536 end
        if count<0 and pending.ids[id] and pending.ids[id]>0 then
            local restored=math.min(-count,pending.ids[id]);pending.ids[id]=pending.ids[id]-restored
            args[3]=sdk.to_ptr(count+restored)
        end
    end)
    R.hook("meal_end","app.DemoMediator","endEndFsm(ace.DemoMediatorBase.cParamBase)",nil,function(retval)pending=nil;return retval end)
    R.hook("meal_timer","app.cHunterMealEffect","update(System.Single, app.HunterCharacter)",function(args,data)
        if cfg.freeze_timer and not R.buffer("meals","unlimited_timer") and R.same(R.object(args),R.local_field("_MealEffect")) then
            data.obj=R.object(args)
            if data.obj:get_field("_IsTimerActive") then data.timer=data.obj:get_field("_DurationTimer") end
        end
    end,function(retval,data)
        if data.timer then data.obj:set_field("_DurationTimer",data.timer) end
        return retval
    end)
    re.on_script_reset(function() pending=nil;requested=nil end)
end
function M.draw(ui,menu)
    local in_field=O.in_field()
    if not in_field then ui.muted("Load your hunter to apply a meal. You can prepare your selections here.")end
    ui.section("Meal costs and duration",function()
        O.toggle(ui,"free_vouchers","Do not consume meal vouchers",cfg,"meal_voucher")
        O.toggle(ui,"free_ingredients","Do not consume cooking ingredients",cfg,"meal_cost")
        O.toggle(ui,"freeze_timer","Pause the active meal timer",cfg,"meal_timer")
        ui.muted("These switches affect normal dining. Meals applied from this page always cost nothing.")
    end,true)
    local ok,catalog=pcall(M.catalog)
    if not ok then ui.muted("Meal catalogue unavailable: "..tostring(catalog));return end
    ui.section("Custom meal",function()
        cfg.base=cfg.base or 0;cfg.main=cfg.main or -1;cfg.seasoning=cfg.seasoning or -1
        O.combo(ui,"base","Base food",cfg,catalog.bases)
        O.combo(ui,"main","Additional ingredient",cfg,catalog.main)
        O.combo(ui,"seasoning","Finishing touch",cfg,catalog.seasoning)
        O.toggle(ui,"custom_duration","Override meal duration",cfg)
        if cfg.custom_duration then O.slider(ui,"minutes","Minutes",cfg,1,120,50,"%.0f") end
        O.toggle(ui,"custom_skills","Choose meal skills manually",cfg)
        if cfg.custom_skills then
            for i=1,3 do local key="skill"..i;cfg[key]=cfg[key] or -1;O.combo(ui,key,"Meal skill "..i,cfg,catalog.skills) end
        end
        ui.muted("Uses the current game's ingredient stats and meal skills. Applies only when you press the button.")
        if O.button(ui,"Apply custom meal",in_field) then O.action(menu,function()return M.apply("custom")end) end
    end,true)
    ui.section("Canteen voucher meals",function()
        cfg.canteen=cfg.canteen or 0
        O.combo(ui,"canteen","Meal",cfg,catalog.canteen)
        if O.button(ui,"Apply canteen meal for free",in_field) then O.action(menu,function()return M.apply("canteen")end) end
        ui.muted("Applies the selected meal's effects directly; no voucher or dining cutscene required.")
    end,true)
    local read,s=pcall(R.local_status)
    local active=read and s and s:get_field("_MealEffect")
    if active then ui.muted(string.format("Current meal: %.0f seconds remaining",active:call("get_DurationTimer"))) end
    if M.status.state then ui.muted(M.status.state) end
end
return M
