-- SPDX-License-Identifier: GPL-3.0-or-later
-- Fresh preferences, separate from the user's captured Current setup profile.
local M = {}

function M.new()
    return {
        ["refshell_mhwilds.json"] = {
            open = false, auto_open = false, auto_open_vk = 0, toggle_vk = 0xC0,
            width = 748, height = 860, dock = "right", margin = 16,
            layout_rev = 4, native_layout_rev = 1, native_page = "Settings",
            god_mode = false, inf_stamina = false, inf_items = false,
            free_craft = false, free_smithy = false, always_sharp = false,
            unlock_armor = false, unlock_palico = false, unlock_weapons = false,
            more_damage = false, more_hr = false, move_fast = false,
            health_bars = false, health_bars_hp_text = false,
            health_bars_show_dist = false, health_bars_zako = false,
        },
        ["AutoGuardGS.json"] = {
            enabled = false, auto_tackle = false, auto_parry = false,
            infinite_charge = false, lock_health = false, debug_log = false,
            guard_type = 1, respect_armor = true, tackle_lead = 12, parry_lead = 28,
            -- No guard_angle: nil retains the game's own angle even when hit hooks run.
        },
        ["WpSeries_GreatSword_Config.json"] = {
            Chinese = false, AttackRangeMultiplier = 50,
            AttackEnhance = false, ExtendAttackRange = false, ExtendChargeTime = false,
            ExtendJustGuard = false, GuardDegree = false, GuardPower = false,
            KireajiAttackReduce = false, ParryTime = false,
            ReduceAttackRecovery = false, ReduceChargeTime = false,
        },
        ["GenSeries_ParryWindow_Config.json"] = {
            Chinese = false,
            AirInsectGlaive = false, AirInsectGlaiveTime = 0.3,
            ExtendJustGuard = false, ExtendJustGuardTime = 0.6,
            GreatSword = false, GreatSwordTime = 0.3,
            Hammer = false, HammerTime = 0.3,
            HuntingHorn = false, HuntingHornTime = 0.3,
            LandInsectGlaive = false, LandInsectGlaiveTime = 0.3,
            SwitchAxe = false, SwitchAxeTime = 0.3,
        },
        ["GHLQOL-gameplay.json"] = { meals = {}, buffs = {}, extras = {}, weapons = {}, smithy = {}, favorites = {} },
        -- Buffer's module defaults are off. Suppress import of legacy enabled options.
        ["GHLQOL-buffer.json"] = { _ghl_migrated = true },
    }
end

return M
