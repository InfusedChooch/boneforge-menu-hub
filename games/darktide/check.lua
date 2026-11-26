-- Run from games/darktide with LuaJIT. Gameplay hooks require the game.
local function check(folder, expected_id)
    local paths
    local strings
    local env = setmetatable({
        fassert = assert,
        new_mod = function(id, scripts)
            assert(id == expected_id, folder .. ": unexpected registration ID")
            paths = scripts
        end,
        get_mod = function(id)
            assert(id == expected_id, folder .. ": unexpected settings ID")
            return { localize = function(_, key) return assert(strings[key].en, key) end }
        end,
    }, { __index = _G })
    env._G = env

    local function load_script(path)
        return setfenv(assert(loadfile(path)), env)
    end

    local manifest = load_script(folder .. "/" .. folder .. ".mod")()
    manifest.run()
    assert(paths, folder .. ": manifest did not register the mod")
    load_script(paths.mod_script .. ".lua")
    strings = load_script(paths.mod_localization .. ".lua")()
    local settings = load_script(paths.mod_data .. ".lua")()
    assert(settings.name == strings.mod_name.en and #settings.options.widgets > 0)
    print("PASS " .. folder .. " (" .. settings.name .. ")")
end

check("darktide-lua-esp", "espenis")
check("darktide-lua-gambits", "darktide-lua-gambits")
check("boneforge-observer", "boneforge-observer")
dofile("tests/observer_wallet.lua")
