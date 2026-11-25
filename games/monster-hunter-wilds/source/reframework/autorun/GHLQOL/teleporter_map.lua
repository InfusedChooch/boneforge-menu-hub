-- SPDX-License-Identifier: GPL-3.0-or-later
local Model=require("GHLQOL.teleporter_map_model")
local Positions=require("GHLQOL.positions")
local O=require("GHLQOL.options")
local M={status={available=false,samples=0}}
local view=Model.new()
local next_sample,last_frame=0,os.clock()
local snapshot,drag,selected_name
local pin_name=""
local browser={}
local function favorite_id(region,name) return "favorite:"..region..":"..name end
local function favorites(region)
    local list=O.data.favorites[region]
    return type(list)=="table" and list or {}
end
local function save_list(region,list)
    local before=O.data.favorites[region]
    O.data.favorites[region]=#list>0 and list or nil
    O.save()
    if O.status.save_error then
        O.data.favorites[region]=before
        error("Could not save favorites: "..O.status.save_error)
    end
end
local function add_favorite(menu,target)
    O.action(menu,function()
        local fresh=Positions.snapshot()
        local region=Positions.region()
        assert(fresh.key==view.key and region and region==snapshot.region,"Region changed; refresh the map")
        local name=(target and target.name or pin_name):match("^%s*(.-)%s*$")
        assert(name~="" and utf8.len(name) and utf8.len(name)<=64 and not name:find("[%c#]"),"Enter a name of 1 to 64 characters without # or control characters")
        local list={table.unpack(favorites(region))}
        assert(#list<100,"This region already has 100 favorites")
        for _,row in ipairs(list) do assert(row.name~=name,"That favorite name already exists in this region") end
        list[#list+1]={name=name,pos=target and target.pos or fresh.position}
        save_list(region,list)
        pin_name="";browser.region=region;view.selected=favorite_id(region,name);next_sample=0
        return "Favorite saved"
    end)
end
local function draw_favorites(ui,menu)
    local regions={}
    for key in pairs(O.data.favorites) do regions[#regions+1]=key end
    table.sort(regions)
    if #regions==0 then ui.muted("No saved favorites.");return end
    if not O.data.favorites[browser.region] then
        browser.region=O.data.favorites[snapshot.region] and snapshot.region or regions[1]
    end
    local choices={}
    for _,region in ipairs(regions) do choices[#choices+1]={region,Positions.region_name(region)} end
    ui.bind_combo("Region##MapFavorites",browser,"region",choices)
    local here=browser.region==snapshot.region
    if not here then ui.muted("Visit this region to select its favorites on the map.") end
    for index,row in ipairs(favorites(browser.region)) do
        if type(row)=="table" and type(row.name)=="string" then
            if O.button(ui,row.name.."##Favorite"..index,here) then
                view.selected=favorite_id(browser.region,row.name);view.group=nil;menu._confirm=nil
            end
        end
    end
end
local COLORS={background=0xff201a16,grid=0xff443b30,text=0xffded9cf,player=0xff62d6a9,
    pin=0xff75bce8,saved=0xff75bce8,previous=0xffbc8ec5,waypoint=0xffe1b987,monster=0xff7577e6,selected=0xffb8ecff}
local measures={}
local measure_count=0
local font_size
local function poll(menu,now)
    if now<next_sample then return end
    next_sample=now+0.1
    local ok,result=pcall(Positions.snapshot)
    local old_key=view.key
    local old_region=snapshot and snapshot.region
    if ok then
        local read,region=pcall(Positions.region)
        result.region=read and region or nil
        if result.region then
            for _,row in ipairs(favorites(result.region)) do
                if type(row)=="table" and type(row.name)=="string" then
                    result.markers[#result.markers+1]={id=favorite_id(region,row.name),name=row.name,
                        kind="favorite",pos=row.pos,region=region}
                end
            end
        end
        local updated,err=pcall(view.update,view,result)
        if updated then snapshot=result;M.status.sample_error=nil
        else ok=false;result=err end
    end
    if not ok then snapshot=nil;view:invalidate();M.status.sample_error=tostring(result):sub(1,500)end
    if old_key~=view.key or old_region~=(snapshot and snapshot.region) then
        menu._confirm=nil;drag=nil;measures={};measure_count=0
    end
    M.status.samples=M.status.samples+1;M.status.context_key=view.key
    M.status.sampled_utc=os.date("!%Y-%m-%dT%H:%M:%SZ")
    M.status.target_errors=snapshot and snapshot.errors or nil
    M.status.pins=#view.pins;M.status.markers=#view:markers()
    local target=view:destination();M.status.selected=target and target.name or nil
end
local function measure(name)
    local size=imgui.get_default_font_size()
    if size~=font_size or measure_count>=512 then measures={};measure_count=0;font_size=size end
    local cached=measures[name]
    if not cached then
        local s=imgui.calc_text_size(name);cached={s.x,s.y};measures[name]=cached;measure_count=measure_count+1
    end
    return cached[1],cached[2]
end
local function canvas_width()
    imgui.push_item_width(-1)
    local ok,value=pcall(imgui.calc_item_width)
    imgui.pop_item_width()
    assert(ok and type(value)=="number" and value==value,"Map width unavailable")
    return math.max(80,math.min(1600,value))
end
local function draw_canvas(menu,width,height,now)
    if view.needs_fit then view:fit(width,height)end
    view:animate(now-last_frame);last_frame=now
    local origin=imgui.get_cursor_screen_pos()
    imgui.invisible_button("##GHLTeleporterMapCanvas",{width,height},0)
    local hovered,active=imgui.is_item_hovered(),imgui.is_item_active()
    local mouse=imgui.get_mouse()
    local x,y=mouse.x-origin.x,mouse.y-origin.y
    if active and imgui.is_mouse_down(0) then
        if not drag then drag={x=x,y=y,start_x=x,start_y=y,moved=false}
        else
            if (x-drag.start_x)^2+(y-drag.start_y)^2>16 then drag.moved=true end
            if drag.moved then view:pan(x-drag.x,y-drag.y)end
            drag.x=x;drag.y=y
        end
    end
    local layout=view:layout(width,height,measure)
    if drag and not imgui.is_mouse_down(0) then
        if hovered and not drag.moved then view:select_at(x,y,layout);menu._confirm=nil end
        drag=nil
    end
    local list=imgui.get_window_draw_list()
    local function point(px,py)return {origin.x+px,origin.y+py}end
    list:push_clip_rect(point(0,0),point(width,height),true)
    local ok,err=xpcall(function()
        list:add_rect_filled(point(0,0),point(width,height),COLORS.background,3,0)
        local step=view:grid_step()
        local left=view:unproject(0,0,width,height)
        local right=view:unproject(width,height,width,height)
        local count=0
        for wx=math.ceil(left.x/step)*step,right.x,step do
            if count>=64 then break end;count=count+1
            local px=view:project({x=wx,z=view.cz},width,height)
            list:add_line(point(px,0),point(px,height),COLORS.grid,1)
        end
        count=0
        for wz=math.ceil(right.z/step)*step,left.z,step do
            if count>=64 then break end;count=count+1
            local _,py=view:project({x=view.cx,z=wz},width,height)
            list:add_line(point(0,py),point(width,py),COLORS.grid,1)
        end
        for i=2,#view.trail do
            local a,b=view.trail[i-1],view.trail[i]
            if not b.break_before then
                local ax,ay=view:project(a,width,height);local bx,by=view:project(b,width,height)
                list:add_line(point(ax,ay),point(bx,by),0x8062d6a9,1.5)
            end
        end
        for _,g in ipairs(layout.groups)do
            local selected=view.group==g.id
            for _,p in ipairs(g.members)do if p.id==view.selected then selected=true end end
            local color=selected and COLORS.selected or COLORS[g.members[1].kind] or COLORS.pin
            list:add_circle_filled(point(g.x,g.y),#g.members>1 and 7 or 5,color,16)
            if selected then list:add_circle(point(g.x,g.y),10,COLORS.selected,20,2)end
        end
        for _,label in ipairs(layout.labels)do list:add_text(point(label.x,label.y),COLORS.text,label.text)end
        if view.player then
            local px,py=view:project(view.player,width,height)
            list:add_triangle_filled(point(px,py-8),point(px-6,py+6),point(px+6,py+6),COLORS.player)
        end
        list:add_text(point(8,8),COLORS.text,string.format("+Z up   Grid %.0f units",step))
    end,debug.traceback)
    list:pop_clip_rect()
    if not ok then error(err,0)end
    return layout
end
function M.draw(ui,menu)
    for _,name in ipairs({"get_window_draw_list","get_cursor_screen_pos","invisible_button","get_mouse",
        "is_item_hovered","is_item_active","is_mouse_down","calc_text_size","get_default_font_size",
        "push_item_width","pop_item_width","calc_item_width"})do
        if type(imgui[name])~="function" then
            M.status.available=false;ui.muted("Map drawing is unavailable in this runtime.");return
        end
    end
    M.status.available=true
    local now=os.clock();poll(menu,now)
    ui.muted("Coordinate map: +X right, +Z up. Drag to pan; use + / - to zoom. Click a marker to select it.")
    ui.muted("Green: you. Gold: saved/pinned. Purple: return. Blue: waypoint. Red: near monster.")
    ui.muted("Pins last for this scene. Favorites keep their captured height across visits to the same region.")
    if not snapshot then ui.muted(M.status.sample_error or "Enter the field first");return end
    local width,height=canvas_width(),360
    if ui.button("Fit locations##MapFit")then view:fit(width,height)end
    imgui.same_line();if ui.button("+##MapZoomIn")then view:zoom(1.25)end
    imgui.same_line();if ui.button("-##MapZoomOut")then view:zoom(0.8)end
    local changed,value=ui.toggle("Follow player##MapFollow",view.follow)
    if changed then view.follow=value end
    changed,value=ui.toggle("Show labels##MapLabels",view.labels)
    if changed then view.labels=value end
    local ok,layout=pcall(draw_canvas,menu,width,height,now)
    if not ok then
        drag=nil;M.status.draw_error=tostring(layout):sub(1,1000);ui.muted("Map drawing failed: "..M.status.draw_error);return
    end
    M.status.draw_error=nil
    if ui.input_text then
        changed,value=ui.input_text("MapPinName",pin_name,{label="Pin name",placeholder="Name this location"})
    else changed,value=imgui.input_text("Pin name##MapPinName",pin_name)end
    if changed then pin_name=value end
    if O.button(ui,"Add current location##MapPin",#view.pins<Model.MAX_PINS)then
        O.action(menu,function()
            local fresh=Positions.snapshot()
            assert(fresh.key==view.key,"Scene changed; wait for the map to refresh")
            view.selected=view:add_pin(pin_name,fresh.position);view.group=nil;menu._confirm=nil
            pin_name="";return "Location pinned for this scene"
        end)
    end
    if view.group then
        local found
        for _,g in ipairs(layout.groups)do if g.id==view.group then
            found=true;ui.muted("Choose one location from this group:")
            for _,p in ipairs(g.members)do if ui.button(p.name.."##MapSelect"..p.id)then
                view.selected=p.id;view.group=nil;menu._confirm=nil
            end end
        end end
        if not found then view.group=nil end
    end
    local target=view:destination()
    if snapshot.region then
        ui.muted("Current region: "..Positions.region_name(snapshot.region))
        local pin=target and target.kind=="pin" and target or nil
        if O.button(ui,pin and "Save selected pin to favorites" or "Save current location to favorites",pin~=nil or pin_name:find("%S")~=nil) then
            add_favorite(menu,pin)
        end
    else ui.muted("Region unavailable; favorites cannot be saved here.") end
    ui.section("Favorites by region",function() draw_favorites(ui,menu) end,false)
    selected_name=target and target.name or nil
    if target then
        local p=target.pos
        ui.muted(string.format("%s: X %.1f   Height %.1f   Z %.1f",target.name,p.x,p.y,p.z))
    end
    if O.button(ui,"Go to selected location##MapMove",target~=nil and not snapshot.busy)then
        Positions.request(ui,menu,"Map: "..target.name,target)
    end
    if O.button(ui,"Remove selected pin##MapRemove",target~=nil and target.kind=="pin")then
        view:remove_selected_pin();menu._confirm=nil
    end
    if target and target.kind=="favorite" and ui.button("Remove selected favorite") then
        O.action(menu,function()
            local list={}
            for _,row in ipairs(favorites(target.region)) do
                if row.name~=target.name then list[#list+1]=row end
            end
            save_list(target.region,list);view.selected=nil;next_sample=0;menu._confirm=nil
            return "Favorite removed"
        end)
    end
    if Positions.status.verification then ui.muted("Last move: "..Positions.status.verification.outcome)end
    if Positions.status.last_outcome=="error" then ui.muted(Positions.status.last_error)end
    M.status.pins=#view.pins;M.status.markers=#view:markers();M.status.labels=#layout.labels
    M.status.selected=selected_name;M.status.scale=view.scale;M.status.trail=#view.trail
end
re.on_script_reset(function()
    view:invalidate();snapshot=nil;drag=nil;next_sample=0;measures={};measure_count=0
end)
return M
