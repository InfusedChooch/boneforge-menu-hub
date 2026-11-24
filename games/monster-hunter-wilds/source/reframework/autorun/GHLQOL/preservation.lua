-- Scope party-capable preservation to local native use calls and decrements.
local R=require("GHLQOL.runtime")
local E=require("GHLQOL.buffer_engine")
local M={}
function M.init(module)
    local consumable,slinger=false,false
    local function scope(args,data,key,extension)
        local previous
        if key=="item" then previous=consumable else previous=slinger end
        data.restore=function()
            if key=="item" then consumable=previous else slinger=previous end
        end
        local h=R.hunter()
        local owner=extension and h and h:get_field("<HunterExtend>k__BackingField") or h
        local enabled=E.status.modules.character==true and not E.external() and R.same(R.object(args),owner) and module.data[key=="item" and "unlimited_consumables" or "unlimited_slingers"]==true
        if key=="item" then consumable=enabled else slinger=enabled end
    end
    local function unchanged(retval)return retval end
    R.hook("preserve_item_scope","app.HunterCharacter.cHunterExtendBase","useItem",function(args,data)scope(args,data,"item",true)end,unchanged)
    for i,signature in ipairs({
        "shootSlinger(app.HunterDef.SLINGER_AMMO_TYPE, via.vec3, System.Nullable`1<via.vec2>)",
        "shootSlinger(app.HunterDef.SLINGER_AMMO_TYPE, via.vec3, via.vec3, System.Nullable`1<via.vec2>)",
        "useSlinger",
    }) do
        R.hook("preserve_slinger_scope"..i,"app.HunterCharacter",signature,function(args,data)scope(args,data,"slinger")end,unchanged)
    end
    R.hook("preserve_pouch","app.savedata.cItemParam","changeItemPouchNum(app.ItemDef.ID, System.Int16, app.savedata.cItemParam.POUCH_CHANGE_TYPE)",function(args)
        if not consumable and not slinger then return end
        local count=sdk.to_int64(args[4])&0xffff
        if count>=32768 then count=count-65536 end
        if count<0 then args[4]=sdk.to_ptr(0) end
    end)
    R.hook("preserve_slinger_ammo","app.cSlingerAmmo","useAmmo",function(args)
        local h=R.hunter()
        if E.status.modules.character==true and not E.external() and h and module.data.unlimited_slingers and R.same(R.object(args),h:get_field("_SlingerAmmo")) then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end)
    re.on_script_reset(function()consumable=false;slinger=false end)
end
return M
