-- SPDX-License-Identifier: GPL-3.0-or-later
-- Own only the typed numeric cells we change; preserve another writer's values.
local M={}
local function integer(value)
    return type(value)=="number" and value==value and value%1==0 and value>=-2147483648 and value<=4294967295
end
function M.new(cells)
    assert(type(cells)=="table" and #cells>0,"No patch cells")
    local self={cells={},original={},expected={}}
    for i,cell in ipairs(cells)do
        assert(cell.object and type(cell.field)=="string","Invalid patch cell")
        local value=cell.object:get_field(cell.field)
        assert(integer(value),"Non-integer baseline: "..cell.field)
        self.cells[i]=cell;self.original[i]=value;self.expected[i]=value
    end
    function self:apply(values)
        if type(values)~="table" or #values~=#self.cells then return false,"Patch size mismatch"end
        local checked,reason=pcall(function()
            for i,cell in ipairs(self.cells)do
                assert(integer(values[i]),"Invalid patch value")
                assert(cell.object:get_field(cell.field)==self.expected[i],"Another mod changed "..cell.field)
            end
        end)
        if not checked then return false,tostring(reason)end
        local previous,touched={},{}
        for i,value in ipairs(self.expected)do previous[i]=value end
        local applied,err=pcall(function()
            for i,cell in ipairs(self.cells)do if self.expected[i]~=values[i]then
                touched[#touched+1]=i;self.expected[i]=values[i]
                cell.object:set_field(cell.field,values[i])
                assert(cell.object:get_field(cell.field)==values[i],"Patch readback failed: "..cell.field)
            end end
        end)
        if applied then return true end
        local failures={}
        for j=#touched,1,-1 do
            local i=touched[j];local cell=self.cells[i]
            local restored,why=pcall(function()
                local current=cell.object:get_field(cell.field)
                if current==self.expected[i]then
                    cell.object:set_field(cell.field,previous[i])
                    assert(cell.object:get_field(cell.field)==previous[i],"Rollback readback failed")
                else assert(current==previous[i],"Concurrent change preserved during rollback")end
                self.expected[i]=previous[i]
            end)
            if not restored then failures[#failures+1]=tostring(why)end
        end
        return false,tostring(err)..(#failures>0 and "; rollback: "..table.concat(failures,"; ") or "")
    end
    function self:restore()
        local errors,foreign={},0
        for i,cell in ipairs(self.cells)do if self.expected[i]~=self.original[i]then
            local ok,err=pcall(function()
                local current=cell.object:get_field(cell.field)
                if current==self.expected[i]then
                    cell.object:set_field(cell.field,self.original[i])
                    assert(cell.object:get_field(cell.field)==self.original[i],"Restore readback failed")
                elseif current~=self.original[i]then foreign=foreign+1 end
                self.expected[i]=self.original[i]
            end)
            if not ok then errors[#errors+1]=tostring(err)end
        end end
        return #errors==0,#errors>0 and table.concat(errors,"; ") or nil,foreign
    end
    return self
end
return M
