local mod = get_mod("espenis")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "draw_box",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "draw_name",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "boss_color_mode",
				type = "dropdown",
				default_value = "purple_red",
				options = {
					{text = "color_green_red", value = "green_red"},
					{text = "color_orange_red", value = "orange_red"},
					{text = "color_purple_red", value = "purple_red"},
					{text = "color_cyan_red", value = "cyan_red"},
					{text = "color_yellow_red", value = "yellow_red"},
					{text = "color_blue_red", value = "blue_red"},
					{text = "color_white_red", value = "white_red"},
					{text = "color_pink_red", value = "pink_red"},
				}
			},
			{
				setting_id = "elite_color_mode",
				type = "dropdown",
				default_value = "green_red",
				options = {
					{text = "color_green_red", value = "green_red"},
					{text = "color_orange_red", value = "orange_red"},
					{text = "color_purple_red", value = "purple_red"},
					{text = "color_cyan_red", value = "cyan_red"},
					{text = "color_yellow_red", value = "yellow_red"},
					{text = "color_blue_red", value = "blue_red"},
					{text = "color_white_red", value = "white_red"},
					{text = "color_pink_red", value = "pink_red"},
				}
			},
			{
				setting_id = "special_color_mode",
				type = "dropdown",
				default_value = "cyan_red",
				options = {
					{text = "color_green_red", value = "green_red"},
					{text = "color_orange_red", value = "orange_red"},
					{text = "color_purple_red", value = "purple_red"},
					{text = "color_cyan_red", value = "cyan_red"},
					{text = "color_yellow_red", value = "yellow_red"},
					{text = "color_blue_red", value = "blue_red"},
					{text = "color_white_red", value = "white_red"},
					{text = "color_pink_red", value = "pink_red"},
				}
			},
		}
	}
}