-- SPDX-License-Identifier: GPL-3.0-or-later
local R=require("GHLQOL.runtime")
local O=require("GHLQOL.options")
local M={pages={},status={capabilities=R.capabilities,errors=R.errors,settings=O.status}}
local modules={}
for _,entry in ipairs({{"Smithy","smithy"},{"Support","support"},{"Meals","meals"},{"Buffs","buffs"},{"Extras","extras"},{"Weapons","weapons"},{"Positions","positions"},{"Map","teleporter_map"},{"Inventory","inventory"},{"Hunter Journal","journal"}}) do
    local name,key=entry[1],entry[2]
    local ok,module=pcall(require,"GHLQOL."..key)
    if ok and module.init then
        local initialized,err=pcall(module.init)
        if not initialized then ok,module=false,err end
    end
    if ok then
        modules[#modules+1]=module;M.status[key]=module.status or {}
        M.pages[#M.pages+1]={name=name,draw=module.draw}
    else
        M.status[key]={error=tostring(module):sub(1,1000)}
        M.pages[#M.pages+1]={name=name,draw=function(ui)ui.muted(name.." unavailable; see GHLQOL-status.json")end}
    end
end
function M.tick()
    for _,module in ipairs(modules) do if module.tick then
        local ok,err=pcall(module.tick)
        if not ok then M.status.frame_error=tostring(err):sub(1,1000) end
    end end
end
return M
