local mod = get_mod("boneforge-observer")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            { setting_id = "observe_wallet", type = "checkbox", default_value = true },
            { setting_id = "observe_talents", type = "checkbox", default_value = true },
            { setting_id = "observe_notifications", type = "checkbox", default_value = true },
        },
    },
}
