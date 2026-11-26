local bridge = assert(_G[testId])
assert(bridge.version == testVersion and bridge.ready and bridge.current_area() == nil)
local render, click, toggle, stored, lines
local parses = 0
re = {on_draw_ui = function(cb) render = cb end}
fs = {read = function(path)
    assert(path == testId .. ".json")
    return stored and '{"controlHints":false}' or ""
end}
json = {
    load_string = function(contents)
        parses = parses + 1
        assert(contents == '{"controlHints":false}')
        return stored
    end,
    dump_file = function(path, value) assert(path == testId .. ".json"); stored = value; return true end
}
imgui = {
    tree_node = function() return true end, tree_pop = function() end, same_line = function() end,
    text = function(line) lines[line] = true end,
    button = function(label) return label == click end,
    checkbox = function(_, value) if toggle then return true, not value end return false, value end
}
local function frame(button, change)
    lines, click, toggle = {}, button, change
    render()
end
dofile(testScript)
frame()
assert(parses == 0 and lines["Use Settings to change control hints."])
assert(lines["Native bridge ready (" .. testVersion .. ")"] and lines["Game adapter unavailable"])
_G[testId] = nil
frame()
assert(lines["Native bridge unavailable. Load the matching plug-in DLL."])
_G[testId] = bridge
bridge.current_area = function() return "Test area" end
frame("Read current area")
assert(lines["Test area"])
frame("Settings", true)
assert(stored.controlHints == false)
dofile(testScript)
frame()
assert(not lines["Use Settings to change control hints."])
assert(parses == 1)
