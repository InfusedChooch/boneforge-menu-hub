-- SPDX-License-Identifier: GPL-3.0-or-later
local D=require("GHLQOL.records")
local R=require("GHLQOL.runtime")
local M={}
local query,page="",1

local function inventory(save)
    local item=D.field(save,"_Item")
    local counts={}
    for _,source in ipairs({{"pouch","_PouchItem"},{"box","_BoxItem"}}) do
        D.each(D.field(item,source[2]),function(slot)
            local count=D.field(slot,"Num")
            if count<=0 then return end
            local id=D.field(slot,"ItemIdFixed")
            local row=counts[id] or {id=id,pouch=0,box=0}
            row[source[1]]=row[source[1]]+count
            counts[id]=row
        end)
    end
    local available,catalog=pcall(function()
        local data=sdk.get_managed_singleton("app.VariousDataManager")
        return D.field(D.field(D.field(data,"_Setting"),"_ItemSetting"),"_ItemData")
    end)
    local rows={}
    for id,row in pairs(counts) do
        row.name="Item "..id
        if available then
            local ok,name=pcall(function()
                local item_data=catalog:call("getDataByFixedId(System.Int32)",id)
                return R.text(D.field(item_data,"_RawName"))
            end)
            if ok and name and name~="" and name~="Unknown" and name~="nil" then row.name=name end
        end
        rows[#rows+1]=row
    end
    table.sort(rows,function(a,b)
        if a.name==b.name then return a.id<b.id end
        return a.name<b.name
    end)
    return rows
end

local snapshot=D.viewer("inventory",inventory)
function M.draw(ui)
    local rows=snapshot(ui)
    if not rows then return end
    local changed,value=imgui.input_text("Item name or ID",query)
    if changed then query=value;page=1 end
    local matches={}
    local needle=query:lower()
    for _,row in ipairs(rows) do
        if row.name:lower():find(needle,1,true) or tostring(row.id):find(needle,1,true) then
            matches[#matches+1]=row
        end
    end
    if #matches==0 then ui.muted("No matching items in the pouch or box.") end
    page=D.page(ui,matches,page,function(row)
        ui.muted(string.format("%s (#%d)   Pouch %d   Box %d",row.name,row.id,row.pouch,row.box))
    end)
end
return M
