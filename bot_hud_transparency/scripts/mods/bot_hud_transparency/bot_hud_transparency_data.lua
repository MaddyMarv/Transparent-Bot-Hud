local mod = get_mod("bot_hud_transparency")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "bot_hud_transparency",
				type = "numeric",
				default_value = 50,
				range = { 0, 100 },
			},
			{
				setting_id = "bot_nametag_transparency",
				type = "numeric",
				default_value = 50,
				range = { 0, 100 },
			},
			{
				setting_id = "hide_dead_bot_hud",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "always_hide_bot_hud",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "mute_hogtied_bots",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "hide_bot_rescue_markers",
				type = "checkbox",
				default_value = true,
			}
		}
	}
}
