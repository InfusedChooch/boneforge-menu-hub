return {
    run = function()
        fassert(rawget(_G, "new_mod"), "Boneforge Observer requires Darktide Mod Framework.")
        local path = "boneforge-observer/scripts/mods/boneforge-observer/"
        new_mod("boneforge-observer", {
            mod_script = path .. "observer",
            mod_data = path .. "observer_data",
            mod_localization = path .. "observer_localization",
        })
    end,
    packages = {},
}
