return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`bot_hud_transparency` encountered an error loading the Darktide Mod Framework.")

		new_mod("bot_hud_transparency", {
			mod_script       = "bot_hud_transparency/scripts/mods/bot_hud_transparency/bot_hud_transparency",
			mod_data         = "bot_hud_transparency/scripts/mods/bot_hud_transparency/bot_hud_transparency_data",
			mod_localization = "bot_hud_transparency/scripts/mods/bot_hud_transparency/bot_hud_transparency_localization",
		})
	end,
	packages = {},
}
