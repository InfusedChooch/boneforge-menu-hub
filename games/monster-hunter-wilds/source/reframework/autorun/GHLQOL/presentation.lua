-- Fit legacy engine widgets into the shared menu without changing their values.
local M={}
function M.draw(callback,width)
    local original={}
    local function replace(key,fn)
        if type(imgui[key])=="function" then original[key]=imgui[key];imgui[key]=fn end
    end
    local function available()
        local ok,win=pcall(imgui.get_window_size)
        local got,pos=pcall(imgui.get_cursor_pos)
        if ok and got and win and pos then return math.max(80,win.x-pos.x-18) end
        return math.max(80,(width or 400)-50)
    end
    local function measure(text)
        local ok,size=pcall(imgui.calc_text_size,text)
        return ok and size and (size.x or size[1]) or #text*7
    end
    local function lines(text,limit)
        local out={}
        for para in (tostring(text or "").."\n"):gmatch("(.-)\n") do
            local line=""
            for word in para:gmatch("%S+") do
                local next_line=line=="" and word or line.." "..word
                if line~="" and measure(next_line)>limit then out[#out+1]=line;line=word else line=next_line end
            end
            out[#out+1]=line
        end
        return out
    end
    local text,text_colored=imgui.text,imgui.text_colored
    replace("text",function(value)for _,line in ipairs(lines(value,available()))do text(line)end end)
    replace("text_colored",function(value,color)for _,line in ipairs(lines(value,available()))do text_colored(line,color)end end)
    -- Native inline sliders/buttons assume a wider original window.
    replace("same_line",function()end)
    for _,name in ipairs({"slider_int","slider_float","drag_int","drag_float","combo","input_int","input_float"}) do
        local native=imgui[name]
        replace(name,function(label,...)
            local shown=tostring(label):match("^(.-)##") or tostring(label)
            if shown~="" then imgui.text(shown) end
            imgui.push_item_width(-1)
            local result=table.pack(pcall(native,"##"..tostring(label),...))
            imgui.pop_item_width()
            if not result[1] then error(result[2],0) end
            return table.unpack(result,2,result.n)
        end)
    end
    local checkbox=imgui.checkbox
    replace("checkbox",function(label,value)
        local shown=tostring(label):match("^(.-)##") or tostring(label)
        if measure(shown)<=available()-28 then return checkbox(label,value) end
        local changed,new=checkbox("##"..tostring(label),value)
        original.same_line()
        for _,line in ipairs(lines(shown,available()))do text(line)end
        return changed,new
    end)
    local button=imgui.button
    replace("button",function(label) return button(label,{-1,28}) end)
    local ok,err=xpcall(callback,debug.traceback)
    for key,fn in pairs(original)do imgui[key]=fn end
    if not ok then error(err,0) end
end
return M
