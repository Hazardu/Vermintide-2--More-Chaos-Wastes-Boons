return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`other-class-boons` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("other-class-boons", {
			mod_script       = "scripts/mods/other-class-boons/other-class-boons",
			mod_data         = "scripts/mods/other-class-boons/other-class-boons_data",
			mod_localization = "scripts/mods/other-class-boons/other-class-boons_localization",
		})
	end,
	packages = {
		"resource_packages/other-class-boons/other-class-boons",
	},
}
