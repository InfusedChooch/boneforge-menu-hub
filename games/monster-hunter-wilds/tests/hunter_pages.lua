-- Run from games/monster-hunter-wilds with Lua 5.4.
package.path="source/reframework/autorun/?.lua;"..package.path
local function object(fields,address)
    return {get_field=function(_,k) return fields[k] end,get_address=function() return address or 1 end}
end
local function array(rows)
    return {get_size=function() return #rows end,get_element=function(_,i) return rows[i+1] end}
end
local function copy(t)
    if type(t)~="table" then return t end
    local out={};for k,v in pairs(t) do out[k]=copy(v) end;return out
end
local clock,clicked,input,choice=1,nil,nil,nil
os.clock=function() return clock end
local lines={}
local function clear() lines={};clock=clock+1 end
local function shown(s)
    for _,line in ipairs(lines) do if line:find(s,1,true) then return true end end
    return false
end
local function noop() end
local function button(label)
    if clicked==label then clicked=nil;return true end
    return false
end
local function text_input(_,previous)
    if input~=nil then local new=input;input=nil;return true,new end
    return false,previous
end
local ui={muted=function(s) lines[#lines+1]=s end,section=function(_,fn) fn() end,
    toggle=function() return false end,button=button,input_text=text_input,
    bind_combo=function(_,state,key) if choice then state[key]=choice;choice=nil;return true end end}
local menu={toast=function(_,s) lines[#lines+1]=s end}
local saved,fail_save=nil,false
json={load_file=function() return copy(saved) end,dump_file=function(_,t)
    if fail_save then return false end
    saved=copy(t);return true
end}
re={on_script_reset=noop}
local draw=setmetatable({},{__index=function() return noop end})
imgui={begin_disabled=noop,end_disabled=noop,input_text=text_input,
    combo=function(_,current) if choice then local c=choice;choice=nil;return true,c end;return false,current end,
    get_window_draw_list=function() return draw end,get_cursor_screen_pos=function() return {x=0,y=0} end,
    get_mouse=function() return {x=0,y=0} end,calc_text_size=function() return {x=35,y=12} end,
    calc_item_width=function() return 400 end,get_default_font_size=function() return 14 end,
    invisible_button=noop,is_item_hovered=noop,is_item_active=noop,is_mouse_down=noop,
    push_item_width=noop,pop_item_width=noop,same_line=noop}
local items={_Kairiki_Timer=62.1,_KijinDrink=object({_Timer=6})}
local status=object({_ItemBuff=object(items)})
local enum={["app.EnemyDef.ID_Fixed"]={{8,"Test"}},["app.EnemyDef.ID"]={{2,"Test"}},
    ["app.FieldDef.STAGE_Fixed"]={{10,"ST101"}}}
local runtime={enum=function(k) return assert(enum[k]) end,text=function(x) return x end,
    static=function() return "Test monster" end,local_status=function() return status end,
    hunter=function() return status end,ready=function() return true end}
package.loaded["GHLQOL.runtime"]=runtime
local buffs=require("GHLQOL.buffs")
buffs.draw(ui,menu)
assert(shown("Might Seed  1:03") and shown("Demondrug  0:06"))
items._Kairiki_Timer=0;clear();buffs.draw(ui,menu);assert(not shown("Might Seed  "))
status=nil;clear();buffs.draw(ui,menu);assert(shown("Load your hunter"))

local function slot(id,num) return object({ItemIdFixed=id,Num=num}) end
local data={_Item=object({_PouchItem=array({slot(4,2),slot(4,3)}),_BoxItem=array({slot(4,10),slot(6,9)})}),
    _EnemyReport=object({_Boss=array({object({FixedId=8,SlayingNum=4,CaptureNum=3})}),
        _Zako=array({object({FixedId=11,SlayingNum=9})})}),
    _HunterProfile=object({_AnimalCapturePerStage=array({object({StageFixedId=10,Num=6})}),
        _FishCapturePerStage=array({object({StageFixedId=10,Num=8})}),
        _QuestClearCounter=object({_ClearNumPerCategory=array({object({CategoryFixedId=2,
            MainWeaponUseNum=array({3}),SubWeaponUseNum=array({1})})})})})}
local save=object(data,77)
local catalog={call=function(_,_,id) return object({_RawName=id==4 and "Potion" or "Herb"}) end}
sdk={get_managed_singleton=function(name)
    if name=="app.SaveDataManager" then return {call=function() return save end} end
    if name=="app.VariousDataManager" then return object({_Setting=object({_ItemSetting=object({_ItemData=catalog})})}) end
end}
local inventory=require("GHLQOL.inventory")
clear();input="pOt";inventory.draw(ui)
assert(shown("Potion (#4)   Pouch 5   Box 10") and not shown("Herb"))
clear();input="6";inventory.draw(ui);assert(shown("Herb (#6)   Pouch 0   Box 9"))
clear();save=nil;inventory.draw(ui);assert(shown("Load a hunter") and not shown("Herb"))
clear();save=object(data,88)
local journal=require("GHLQOL.journal")
for i,expected in ipairs({"Test monster   Slain 4   Captured 3","Monster #11   Slain 9",
    "Windward Plains   Captured 6","Windward Plains   Captured 8","Great Sword   Main 3   Sub 1"}) do
    clear();choice=i;journal.draw(ui);assert(shown(expected),expected)
end
clear();save=object({},99);journal.draw(ui);assert(shown("journal unavailable") and not shown("Great Sword"))

local region="ST101"
local positions={status={},region=function() return region end,region_name=require("GHLQOL.records").region_name,
    snapshot=function() return {key="context",position={x=1,y=20,z=3},markers={}} end,
    request=function(_,_,_,target) assert(target.region==region and target.pos.y==20);lines[#lines+1]="requested" end}
package.loaded["GHLQOL.positions"]=positions
local map=require("GHLQOL.teleporter_map")
local function frame(click) clear();clicked=click;map.draw(ui,menu) end
input="Camp";frame("Save current location to favorites")
assert(saved.favorites.ST101[1].pos.y==20)
frame();assert(map.status.selected=="Camp")
region="ST102";frame();assert(map.status.selected==nil and shown("Visit this region"))
input="Test";fail_save=true;frame("Save current location to favorites");fail_save=false
assert(not require("GHLQOL.options").data.favorites.ST102)
package.loaded["GHLQOL.options"]=nil;package.loaded["GHLQOL.teleporter_map"]=nil
map=require("GHLQOL.teleporter_map")
region="ST101";frame("Camp##Favorite1")
frame("Go to selected location##MapMove");assert(shown("requested"))
frame("Remove selected favorite");assert(not saved.favorites.ST101)
print("Passed inventory, journal, timer and favorite page checks")
