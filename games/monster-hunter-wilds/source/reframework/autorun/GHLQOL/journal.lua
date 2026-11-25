-- SPDX-License-Identifier: GPL-3.0-or-later
local D=require("GHLQOL.records")
local R=require("GHLQOL.runtime")
local M={}
local sections={"Large monsters","Small monsters","Endemic captures","Aquatic captures","Weapon use"}
local section,page=1,1
local weapons={"Great Sword","Sword and Shield","Dual Blades","Long Sword","Hammer",
    "Hunting Horn","Lance","Gunlance","Switch Axe","Charge Blade","Insect Glaive",
    "Bow","Heavy Bowgun","Light Bowgun"}
local enemy_ids
local function monster_name(fixed)
    local symbol=D.enum("app.EnemyDef.ID_Fixed")[fixed]
    if not symbol then return "Monster #"..fixed end
    if not enemy_ids then
        enemy_ids={}
        for id,key in pairs(D.enum("app.EnemyDef.ID")) do enemy_ids[key]=id end
    end
    if enemy_ids[symbol] then
        local ok,name=pcall(function() return R.text(R.static("app.EnemyDef","EnemyName(app.EnemyDef.ID)",enemy_ids[symbol])) end)
        if ok and name~="Unknown" and name~="nil" and name~="" then return name end
    end
    return symbol
end

local function journal(save,which)
    local lines={}
    if which==1 or which==2 then
        local report=D.field(save,"_EnemyReport")
        D.each(D.field(report,which==1 and "_Boss" or "_Zako"),function(record)
            local slain=D.field(record,"SlayingNum")
            local captured=which==1 and D.field(record,"CaptureNum") or 0
            if slain>0 or captured>0 then
                local name=monster_name(D.field(record,"FixedId"))
                local line=string.format("%s   Slain %d",name,slain)
                if which==1 then line=line.."   Captured "..captured end
                lines[#lines+1]=line
            end
        end)
    else
        local profile=D.field(save,"_HunterProfile")
        if which==5 then
            local counter=D.field(profile,"_QuestClearCounter")
            D.each(D.field(counter,"_ClearNumPerCategory"),function(category)
                local totals={}
                for _,field in ipairs({"MainWeaponUseNum","SubWeaponUseNum"}) do
                    D.each(D.field(category,field),function(count,index)
                        if count>0 then
                            local row=totals[index] or {MainWeaponUseNum=0,SubWeaponUseNum=0}
                            row[field]=row[field]+count
                            totals[index]=row
                        end
                    end)
                end
                local category_id=D.field(category,"CategoryFixedId")
                for index,row in pairs(totals) do
                    lines[#lines+1]=string.format("%s   Main %d   Sub %d   Quest category %d",
                        weapons[index+1] or ("Weapon #"..index),row.MainWeaponUseNum,row.SubWeaponUseNum,category_id)
                end
            end)
        else
            local source=which==3 and "_AnimalCapturePerStage" or "_FishCapturePerStage"
            D.each(D.field(profile,source),function(record)
                local count=D.field(record,"Num")
                if count>0 then
                    local id=D.field(record,"StageFixedId")
                    local key=D.enum("app.FieldDef.STAGE_Fixed")[id] or ("Region #"..id)
                    lines[#lines+1]=D.region_name(key).."   Captured "..count
                end
            end)
        end
    end
    table.sort(lines)
    return lines
end

local snapshot=D.viewer("journal",journal)
function M.draw(ui)
    local changed,value=imgui.combo("Records",section,sections)
    if changed then section=value;page=1 end
    local rows=snapshot(ui,section)
    if not rows then return end
    if #rows==0 then ui.muted("No records in this category yet.") end
    page=D.page(ui,rows,page,ui.muted)
end
return M
