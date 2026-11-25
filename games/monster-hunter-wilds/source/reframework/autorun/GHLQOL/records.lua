-- SPDX-License-Identifier: GPL-3.0-or-later
local R=require("GHLQOL.runtime")
local M={}

function M.field(obj,key)
    local value=obj:get_field(key)
    assert(value~=nil,"Record field unavailable: "..key)
    return value
end

function M.each(array,visit)
    local size=array:get_size()
    for i=0,size-1 do
        local row=array:get_element(i)
        if row~=nil then visit(row,i) end
    end
end

-- Keep only plain Lua rows between frames. Discard them on unload or slot change.
function M.viewer(label,read)
    local owner,rows,err
    return function(ui,section)
        local ok,save=pcall(function()
            local manager=sdk.get_managed_singleton("app.SaveDataManager")
            return manager and manager:call("getCurrentUserSaveData")
        end)
        if not ok or not save then
            owner,rows,err=nil,nil,nil
            ui.muted("Load a hunter to view "..label..".")
            return
        end
        local key=tostring(save:get_address())..":"..tostring(section)
        local refresh=ui.button("Refresh##"..label)
        if refresh or owner~=key then
            owner=key
            local success,result=pcall(read,save,section)
            rows,err=nil,nil
            if success then rows=result else err=tostring(result) end
        end
        if err then ui.muted(label.." unavailable: "..err) end
        return rows
    end
end

local enums={}
function M.enum(type_name)
    if not enums[type_name] then
        local names={}
        for _,row in ipairs(R.enum(type_name)) do names[row[1]]=row[2] end
        enums[type_name]=names
    end
    return enums[type_name]
end

local regions={ST101="Windward Plains",ST102="Scarlet Forest",ST103="Oilwell Basin",
    ST104="Iceshard Cliffs",ST105="Ruins of Wyveria"}
function M.region_name(key) return regions[key] or tostring(key) end

function M.page(ui,rows,page,render)
    local pages=math.max(1,math.ceil(#rows/15))
    page=math.max(1,math.min(page,pages))
    if pages>1 then
        if page>1 and ui.button("Previous page") then page=page-1 end
        if page<pages and ui.button("Next page") then page=page+1 end
        ui.muted(string.format("Page %d of %d",page,pages))
    end
    for i=(page-1)*15+1,math.min(page*15,#rows) do render(rows[i]) end
    return page
end
return M
