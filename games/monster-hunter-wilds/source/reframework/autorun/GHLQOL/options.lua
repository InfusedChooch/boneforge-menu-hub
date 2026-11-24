-- SPDX-License-Identifier: GPL-3.0-or-later
local R=require("GHLQOL.runtime")
local M={path="GHLQOL-gameplay.json",data={meals={},buffs={},extras={},weapons={},smithy={}},status={}}
local files=fs and fs.glob and fs.glob([[GHLQOL-gameplay\.json]])
local ok,saved=false,nil
if not files or #files>0 then ok,saved=pcall(json.load_file,M.path) end
if ok and type(saved)=="table" then
    for section in pairs(M.data) do if type(saved[section])=="table" then M.data[section]=saved[section] end end
end
function M.save()
    local read,value=pcall(json.dump_file,M.path,M.data,2)
    M.status.save_error=not(read and value==true) and tostring(value) or nil
end
function M.toggle(ui,key,label,tbl,hook)
    local unavailable=hook and not R.ready(hook)
    if unavailable then imgui.begin_disabled(true) end
    local changed,value=ui.toggle(label,tbl[key]==true)
    if changed then tbl[key]=value;M.save() end
    if unavailable then imgui.end_disabled();ui.muted("Unavailable: "..tostring(R.errors[hook])) end
    return changed,value
end
function M.slider(ui,key,label,tbl,lo,hi,default,fmt)
    tbl[key]=R.bound(tbl[key],lo,hi,default)
    ui.muted(label:match("^(.-)##") or label)
    local changed,value=ui.slider_float("##"..label,tbl[key],lo,hi,fmt or "%.1f")
    if changed then tbl[key]=R.bound(value,lo,hi,default);M.save() end
end
function M.combo(ui,key,label,tbl,items)
    if ui.bind_combo(label,tbl,key,items) then M.save() end
end
function M.action(menu,fn)
    local ok,value=pcall(fn)
    menu:toast(ok and (value or "Applied") or tostring(value):sub(1,250),ok and "success" or "warning",2500)
end
function M.in_field()
    local ok,hunter=pcall(R.hunter)
    return ok and hunter~=nil
end
function M.button(ui,label,enabled)
    imgui.begin_disabled(enabled==false)
    local ok,clicked=pcall(ui.button,label)
    imgui.end_disabled()
    if not ok then error(clicked,0)end
    return enabled~=false and clicked
end
return M
