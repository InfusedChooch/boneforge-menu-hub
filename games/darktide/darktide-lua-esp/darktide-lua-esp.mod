return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`darktide-lua-esp` encountered an error loading the Darktide Mod Framework.")

		new_mod("espenis", {
			mod_script       = "darktide-lua-esp/scripts/mods/gir489/espenis",
			mod_data         = "darktide-lua-esp/scripts/mods/gir489/espenis_data",
			mod_localization = "darktide-lua-esp/scripts/mods/gir489/espenis_localization",
		})
	end,
	packages = {},
}
