local mod = get_mod("darktide-lua-gambits")

local priority_options = {
    { text = "Off", value = 0  },
    { text = "1",   value = 1  },
    { text = "2",   value = 2  },
    { text = "3",   value = 3  },
    { text = "4",   value = 4  },
    { text = "5",   value = 5  },
    { text = "6",   value = 6  },
    { text = "7",   value = 7  },
    { text = "8",   value = 8  },
    { text = "9",   value = 9  },
    { text = "10",  value = 10 },
    { text = "11",  value = 11 },
    { text = "12",  value = 12 },
    { text = "13",  value = 13 },
    { text = "14",  value = 14 },
    { text = "15",  value = 15 },
    { text = "16",  value = 16 },
    { text = "17",  value = 17 },
    { text = "18",  value = 18 },
    { text = "19",  value = 19 },
    { text = "20",  value = 20 },
}

local teammates_dead_mode_options = {
    { text = "TeammatesDeadModeOff",          value = "off"             },
    { text = "TeammatesDeadModeDisable",      value = "disable"         },
    { text = "TeammatesDeadModeChangeFov",    value = "change_fov"      },
    { text = "TeammatesDeadModeChangeFovSmooth", value = "change_fov_smooth" },
}

local function make_raycast_mode_options()
    return {
        { text = "RaycastModeOff",                value = "off"                      },
        { text = "RaycastModeOn",                 value = "on"                       },
        { text = "RaycastModeOnWithRecoil",       value = "on_with_recoil"           },
        { text = "RaycastModeOnWithSpread",       value = "on_with_spread"           },
        { text = "RaycastModeOnWithRecoilSpread", value = "on_with_recoil_and_spread"},
        { text = "RaycastModeOnWithTargeting",    value = "on_with_targeting"        },
    }
end

local profile_options = {
    { text = "AutoClass",         value = "auto"    },
    { text = "CustomClass",       value = "custom"  },
    { text = "VeteranClass",      value = "veteran" },
    { text = "ZealotClass",       value = "zealot"  },
    { text = "PsykerClass",       value = "psyker"  },
    { text = "OgrynClass",        value = "ogryn"   },
    { text = "ArbitratorClass",   value = "adamant" },
    { text = "BrokerClass",       value = "broker"  },
    { text = "SkitariiClass",     value = "cryptic" },
}

local function make_target_widgets(prefix, d)
    return {
        { setting_id = prefix.."triggerbot_use_raycast", type = "dropdown", options = make_raycast_mode_options(), default_value = d.use_raycast, localize = true },
        { setting_id = prefix.."triggerbot_weakspot_only",    type = "checkbox", default_value = d.weakspot_only    },
        { setting_id = prefix.."triggerbot_respect_priority", type = "checkbox", default_value = d.respect_priority },
        { setting_id = prefix.."wait_for_crits",              type = "checkbox", default_value = d.wait_for_crits          },
        { setting_id = prefix.."wait_for_opening_salvo",     type = "checkbox", default_value = d.wait_for_opening_salvo },
        { setting_id = prefix.."ranged_regular_targeted_only", type = "checkbox", default_value = d.ranged_regular_targeted_only },
        { setting_id = prefix.."ranged_regular_aim_angle",    type = "numeric",   default_value = d.ranged_regular_aim_angle, range = { 0, 90 } },
        { setting_id = prefix.."target_bosses",         type = "dropdown", options = priority_options, default_value = d.bosses         },
        { setting_id = prefix.."target_berzerkers",     type = "dropdown", options = priority_options, default_value = d.berzerkers     },
        { setting_id = prefix.."target_hounds",         type = "dropdown", options = priority_options, default_value = d.hounds         },
        { setting_id = prefix.."target_netgunners",     type = "dropdown", options = priority_options, default_value = d.netgunners     },
        { setting_id = prefix.."target_flamers",        type = "dropdown", options = priority_options, default_value = d.flamers        },
        { setting_id = prefix.."target_snipers",        type = "dropdown", options = priority_options, default_value = d.snipers        },
        { setting_id = prefix.."target_bombers",        type = "dropdown", options = priority_options, default_value = d.bombers        },
        { setting_id = prefix.."target_poxwalkers",     type = "dropdown", options = priority_options, default_value = d.poxwalkers     },
        { setting_id = prefix.."target_gunners",        type = "dropdown", options = priority_options, default_value = d.gunners        },
        { setting_id = prefix.."target_plasma_gunners", type = "dropdown", options = priority_options, default_value = d.plasma_gunners },
        { setting_id = prefix.."target_mutants",        type = "dropdown", options = priority_options, default_value = d.mutants        },
        { setting_id = prefix.."target_crushers",       type = "dropdown", options = priority_options, default_value = d.crushers       },
        { setting_id = prefix.."target_bulwarks",       type = "dropdown", options = priority_options, default_value = d.bulwarks       },
        { setting_id = prefix.."target_reapers",        type = "dropdown", options = priority_options, default_value = d.reapers        },
        { setting_id = prefix.."target_mauler",         type = "dropdown", options = priority_options, default_value = d.mauler         },
        { setting_id = prefix.."target_melee_regular",  type = "dropdown", options = priority_options, default_value = d.melee_regular  },
        { setting_id = prefix.."target_ranged_regular", type = "dropdown", options = priority_options, default_value = d.ranged_regular },
    }
end

-- Per-class default priorities and behavior flags.
-- Veteran: ranged specialist — punishes snipers/trappers/hounds hardest.
-- Zealot:  melee rusher — prioritises threats that pin or charge.
-- Psyker:  glass cannon — avoids being grabbed; snipers/trappers lethal.
-- Ogryn:   slow tank — specials exploit the lack of mobility; no weakspot/crit perk synergy.
local CLASS_DEFAULTS = {
    veteran = { use_raycast="on",  weakspot_only=true,  respect_priority=true, wait_for_crits=true,  wait_for_opening_salvo=false, ranged_regular_targeted_only=false, ranged_regular_aim_angle= 0, berzerkers = 9, bombers = 13, bosses = 3, bulwarks = 7, crushers = 4, flamers = 12, gunners = 10, hounds = 14, mauler = 6, melee_regular = 1, mutants = 8, netgunners = 15, plasma_gunners = 5, poxwalkers = 16, ranged_regular = 2, reapers = 11, snipers = 17 },
    zealot  = { use_raycast="on",  weakspot_only=true,  respect_priority=true, wait_for_crits=true,  wait_for_opening_salvo=false, ranged_regular_targeted_only=false, ranged_regular_aim_angle= 0, berzerkers = 9, bombers = 13, bosses = 3, bulwarks = 7, crushers = 4, flamers = 12, gunners = 10, hounds = 14, mauler = 6, melee_regular = 1, mutants = 8, netgunners = 15, plasma_gunners = 5, poxwalkers = 16, ranged_regular = 2, reapers = 11, snipers = 17 },
    psyker  = { use_raycast="on",  weakspot_only=true,  respect_priority=true, wait_for_crits=true,  wait_for_opening_salvo=false, ranged_regular_targeted_only=false, ranged_regular_aim_angle= 0, berzerkers = 9, bombers = 13, bosses = 3, bulwarks = 7, crushers = 4, flamers = 12, gunners = 10, hounds = 14, mauler = 6, melee_regular = 1, mutants = 8, netgunners = 15, plasma_gunners = 5, poxwalkers = 16, ranged_regular = 2, reapers = 11, snipers = 17 },
    ogryn   = { use_raycast="off", weakspot_only=false, respect_priority=true, wait_for_crits=false, wait_for_opening_salvo=false, ranged_regular_targeted_only=false, ranged_regular_aim_angle= 0, berzerkers = 9, bombers = 13, bosses = 3, bulwarks = 7, crushers = 4, flamers = 12, gunners = 10, hounds = 14, mauler = 6, melee_regular = 1, mutants = 8, netgunners = 15, plasma_gunners = 5, poxwalkers = 16, ranged_regular = 2, reapers = 11, snipers = 17 },
    broker  = { use_raycast="on",  weakspot_only=true,  respect_priority=true, wait_for_crits=true,  wait_for_opening_salvo=false, ranged_regular_targeted_only=true,  ranged_regular_aim_angle=45, berzerkers = 9, bombers = 13, bosses = 3, bulwarks = 7, crushers = 4, flamers = 12, gunners = 10, hounds = 14, mauler = 6, melee_regular = 1, mutants = 8, netgunners = 15, plasma_gunners = 5, poxwalkers = 16, ranged_regular = 2, reapers = 11, snipers = 17 },
    adamant = { use_raycast="on",  weakspot_only=true,  respect_priority=true, wait_for_crits=true,  wait_for_opening_salvo=false, ranged_regular_targeted_only=false, ranged_regular_aim_angle= 0, berzerkers = 9, bombers = 13, bosses = 3, bulwarks = 7, crushers = 4, flamers = 12, gunners = 10, hounds = 14, mauler = 6, melee_regular = 1, mutants = 8, netgunners = 15, plasma_gunners = 5, poxwalkers = 16, ranged_regular = 2, reapers = 11, snipers = 17 },
    cryptic = { use_raycast="on",  weakspot_only=true,  respect_priority=true, wait_for_crits=true,  wait_for_opening_salvo=false, ranged_regular_targeted_only=false, ranged_regular_aim_angle= 0, berzerkers = 9, bombers = 13, bosses = 3, bulwarks = 7, crushers = 4, flamers = 12, gunners = 10, hounds = 14, mauler = 6, melee_regular = 1, mutants = 8, netgunners = 15, plasma_gunners = 5, poxwalkers = 16, ranged_regular = 2, reapers = 11, snipers = 17 },
}

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    options = {
        widgets = {
            {
                setting_id = "general_settings",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "enable_fov_check",
                        type = "checkbox",
                        default_value = true
                    },
                    {
                        setting_id = "fov_angle",
                        type = "numeric",
                        default_value = 25,
                        range = { 1, 360 }
                    },
                    {
                        setting_id = "use_mouse2_fallback",
                        type = "checkbox",
                        default_value = true
                    },
                    {
                        setting_id = "use_custom_aim_key",
                        type = "keybind",
                        default_value = {},
                        keybind_global = true,
                        keybind_trigger = "held",
                        keybind_type = "function_call",
                        function_name = "toggle_aim"
                    },
                    {
                        setting_id = "disable_when_teammates_are_dead",
                        type = "dropdown",
                        options = teammates_dead_mode_options,
                        default_value = "change_fov",
                        localize = true
                    },
                    {
                        setting_id = "teammates_dead_fov_angle",
                        type = "numeric",
                        default_value = 0,
                        range = { 0, 360 }
                    },
                    {
                        setting_id = "teammates_dead_smooth",
                        type = "numeric",
                        default_value = 0,
                        range = { 0, 100 }
                    },
                    {
                        setting_id = "require_main_weapon",
                        type = "checkbox",
                        default_value = true,
                        localize = true
                    },
                    {
                        setting_id = "specials_only",
                        type = "checkbox",
                        default_value = true
                    },
                    {
                        setting_id = "enable_spread_compensation",
                        type = "checkbox",
                        default_value = true
                    },
                    {
                        setting_id = "priority_profile",
                        type = "dropdown",
                        options = profile_options,
                        default_value = "auto"
                    },
                    {
                        setting_id = "boss_lock_keybind",
                        type = "keybind",
                        default_value = {"left shift"},
                        keybind_global = true,
                        keybind_trigger = "held",
                        keybind_type = "function_call",
                        function_name = "toggle_boss_lock"
                    },
                }
            },
            {
                setting_id = "triggerbot_settings",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "enable_triggerbot",
                        type = "checkbox",
                        default_value = true
                    },
                    {
                        setting_id = "triggerbot_keybind",
                        type = "keybind",
                        default_value = {"extra_2"},
                        keybind_global = true,
                        keybind_trigger = "held",
                        keybind_type = "function_call",
                        function_name = "toggle_triggerbot"
                    }
                }
            },
            {
                setting_id = "auto_guard_settings",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "enable_auto_guard",
                        type = "checkbox",
                        default_value = false
                    },
                    {
                        setting_id = "auto_guard_range",
                        type = "numeric",
                        default_value = 4,
                        range = { 1, 10 }
                    },
                    {
                        setting_id = "auto_guard_heavy_only",
                        type = "checkbox",
                        default_value = true
                    },
                }
            },
            {
                -- "Custom" profile — the original per-enemy dropdowns.
                -- Only active when priority_profile == "custom" (or as
                -- the auto fallback when no archetype can be detected).
                setting_id = "priority_targets",
                type = "group",
                sub_widgets = make_target_widgets("", CLASS_DEFAULTS.veteran)
            },
            {
                setting_id = "veteran_profile_targets",
                type = "group",
                sub_widgets = make_target_widgets("veteran_", CLASS_DEFAULTS.veteran)
            },
            {
                setting_id = "zealot_profile_targets",
                type = "group",
                sub_widgets = make_target_widgets("zealot_", CLASS_DEFAULTS.zealot)
            },
            {
                setting_id = "psyker_profile_targets",
                type = "group",
                sub_widgets = make_target_widgets("psyker_", CLASS_DEFAULTS.psyker)
            },
            {
                setting_id = "ogryn_profile_targets",
                type = "group",
                sub_widgets = make_target_widgets("ogryn_", CLASS_DEFAULTS.ogryn)
            },
            {
                setting_id = "adamant_profile_targets",
                type = "group",
                sub_widgets = make_target_widgets("adamant_", CLASS_DEFAULTS.adamant)
            },
            {
                setting_id = "broker_profile_targets",
                type = "group",
                sub_widgets = make_target_widgets("broker_", CLASS_DEFAULTS.broker)
            },
            {
                setting_id = "cryptic_profile_targets",
                type = "group",
                sub_widgets = make_target_widgets("cryptic_", CLASS_DEFAULTS.cryptic)
            },
        }
    }
}