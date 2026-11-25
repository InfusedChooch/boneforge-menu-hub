local mod = get_mod("darktide-lua-gambits")
local Health = mod:original_require("scripts/utilities/health")
local HitZone = mod:original_require("scripts/utilities/attack/hit_zone")
local Breed = mod:original_require("scripts/utilities/breed")
local WeaponTemplate = mod:original_require("scripts/utilities/weapon/weapon_template")
local Suppression = mod:original_require("scripts/utilities/attack/suppression")
local WeaponMovementState = mod:original_require("scripts/extension_systems/weapon/utilities/weapon_movement_state")
local CriticalStrike = mod:original_require("scripts/utilities/attack/critical_strike")
local Dodge = mod:original_require("scripts/extension_systems/character_state_machine/character_states/utilities/dodge")
local DamageProfile = mod:original_require("scripts/utilities/attack/damage_profile")
local DamageCalculation = mod:original_require("scripts/utilities/attack/damage_calculation")
local PowerLevel = mod:original_require("scripts/utilities/attack/power_level")
local PowerLevelSettings = mod:original_require("scripts/settings/damage/power_level_settings")
local PlayerUnitStatus = mod:original_require("scripts/utilities/attack/player_unit_status")
local BuffSettings = mod:original_require("scripts/settings/buff/buff_settings")
local Action = mod:original_require("scripts/utilities/action/action")
local AttackSettings = mod:original_require("scripts/settings/damage/attack_settings")
local DamageSettings = mod:original_require("scripts/settings/damage/damage_settings")
local ArmorSettings = mod:original_require("scripts/settings/damage/armor_settings")
local Armor = mod:original_require("scripts/utilities/attack/armor")
local TalentSettings = mod:original_require("scripts/settings/talent/talent_settings")
local SpecialRulesSettings = mod:original_require("scripts/settings/ability/special_rules_settings")
local BreedActions = mod:original_require("scripts/settings/breed/breed_actions")
local Block = mod:original_require("scripts/utilities/attack/block")
local melee_attack_strengths = AttackSettings.melee_attack_strength
local attack_types = AttackSettings.attack_types

local HALF_PI = math.pi / 2

local aim_button_pressed = false
local triggerbot_pressed = false
local boss_lock_pressed = false
local has_target = false
local last_semi_auto_fire_time = 0
-- Post-fire suppression for the Efficiency perk: blocks re-entry for
-- EFFICIENCY_FIRE_COOLDOWN seconds after each shot to cover server RTT before
-- the reduced_ammo_consumption keyword is removed.
local last_efficiency_fire_time = -math.huge
-- Zone-lock hysteresis: when the preferred zone is briefly occluded by a
-- physics reaction (e.g. BoN blob dipping on hit), hold the last confirmed
-- zone for up to ZONE_GRACE_FRAMES before allowing a zone switch.
local last_aim_unit = nil
local last_aim_zone = nil
local last_aim_zone_blocked_frames = 0
local ZONE_GRACE_FRAMES = 10

-- Debug flags and state. One table instead of N locals to stay under Lua's 200-local limit.
-- Set the boolean fields to true to enable each debug mode.
local debug_vars = {
    melee         = false,  -- log melee heavy/light decision diagnostics
    charge        = false,  -- log charge-weapon release decisions
    triggerbot    = false,  -- log triggerbot fire/suppress/resync decisions
    surgical      = false,  -- log Surgical crit-wait damage estimates and server-side actuals
    opening_salvo = false,  -- log Opening Salvo perk detection and num_shots state
    guard         = false,  -- log auto-guard block events
    focus_resolve = false,  -- log Focused Resolve perk detection and outline hits
    breed_aim_zones = false, -- log when weakspot_only blocks a BREED_AIM_ZONES breed
    -- State (non-nil defaults only):
    tbot_last_miss_log      = 0,    -- rate-limiter: fa_miss and fa_fire log spam
    os_last_num_shots       = -1,   -- last seen num_shots for change detection
    focus_resolve_last_log  = 0,    -- rate-limiter: focus_resolve log spam
    surgical_miss_timeout = 2.0,  -- seconds; clears unit if no hit arrives
    -- melee_last_unit, surgical_last_unit, surgical_last_stacks,
    -- surgical_fired_unit, surgical_fired_time  all start nil
}

local BREED_PRIORITY_MAP = {
    -- Hound
    chaos_hound = "target_hounds", --Pox Hound
    chaos_hound_mutator = "target_hounds", --Pox Hound
    chaos_armored_hound = "target_hounds", -- Armored Hound
    -- Boss Enemies
    chaos_beast_of_nurgle = "target_bosses", --Beast of Nurgle
    chaos_plague_ogryn = "target_bosses", --Plague Ogryn
    chaos_spawn = "target_bosses", --Chaos Spawn
    cultist_captain = "target_bosses", --Admontion Champion
    renegade_captain = "target_bosses", --Scab Captain
    renegade_twin_captain = "target_bosses", --Rodin Karnak
    renegade_twin_captain_two = "target_bosses", --Rinda Karnak
    chaos_daemonhost = "target_bosses", --Daemonhost (with special check below)
    chaos_mutator_daemonhost = "target_bosses", --Daemonhost (with special check below)
    chaos_ogryn_houndmaster = "target_bosses", --Houndmaster
    chaos_mutator_ritualist = "target_bosses", --Daemonhost Ritualist (mutator)
    cultist_ritualist = "target_bosses", --Daemonhost Ritualist
    -- Trappers
    renegade_netgunner = "target_netgunners", --Trapper
    -- Flamers
    cultist_flamer = "target_flamers", --Dreg Tox Flamer
    renegade_flamer = "target_flamers", --Scab Flamer
    renegade_flamer_mutator = "target_flamers", --Scab Flamer
    -- Sniper
    renegade_sniper = "target_snipers", --Sniper
    -- Poxbursters
    chaos_poxwalker_bomber = "target_poxwalkers", --Poxburster
    -- Bombers
    cultist_grenadier = "target_bombers", --Dreg Tox Bomber
    renegade_grenadier = "target_bombers", --Scab Bomber
    -- Gunners
    cultist_shocktrooper = "target_gunners", --Dreg Shotgunner
    cultist_gunner = "target_gunners", --Dreg Gunner
    renegade_gunner = "target_gunners", --Scab Gunner
    renegade_shocktrooper = "target_gunners", --Scab Shotgunner
    -- Scab Plasmer Gunner
    renegade_plasma_gunner = "target_plasma_gunners", --Scab Plasmer Gunner
    -- Ragers
    cultist_berzerker = "target_berzerkers", --Dreg Rager
    renegade_berzerker = "target_berzerkers", --Scab Rager
    -- Mauler
    renegade_executor = "target_mauler", --Scab Mauler
    -- Mutants
    cultist_mutant = "target_mutants", --Mutant
    cultist_mutant_mutator = "target_mutants", --Mutant
    -- Bulwark
    chaos_ogryn_bulwark = "target_bulwarks", --Bulwark
    --Crusher
    chaos_ogryn_executor = "target_crushers", --Crusher
    -- Reaper
    chaos_ogryn_gunner = "target_reapers", --Reaper

    -- Melee (regular)
    chaos_armored_infected = "target_melee_regular", -- Amoured Groaner
    chaos_lesser_mutated_poxwalker = "target_melee_regular", -- Mutated Poxwalker
    chaos_mutated_poxwalker = "target_melee_regular", --Tentacled Poxwalker
    chaos_newly_infected = "target_melee_regular", -- Groaner
    chaos_poxwalker = "target_melee_regular", -- Poxwalker
    cultist_melee = "target_melee_regular", -- Dreg Bruiser
    renegade_melee = "target_melee_regular", -- Scab Bruiser

    -- Ranged (regular)
    cultist_assault = "target_ranged_regular", -- Dreg Stalker
    renegade_assault = "target_ranged_regular", -- Scab Stalker
    renegade_radio_operator = "target_ranged_regular", -- Scab Radio Operator
    renegade_rifleman = "target_ranged_regular", -- Scab Shooter
    -- Vanguard (shield carriers, 1.12.0)
    cultist_vanguard  = "target_melee_regular", -- Dreg Vanguard
    renegade_vanguard = "target_melee_regular", -- Scab Vanguard
}

local POXBURSTER_BREEDS = {
    chaos_poxwalker_bomber = true,
}
-- Don't target a poxburster when any player is within this radius (metres).
-- Squared for cheap per-frame distance comparisons.
local POXBURSTER_SAFE_RADIUS    = 7   -- ~7 m: covers ~5 m explosion radius + margin
local POXBURSTER_SAFE_RADIUS_SQ = POXBURSTER_SAFE_RADIUS * POXBURSTER_SAFE_RADIUS

-- Focused Resolve (broker_ability_focus_sub_3): kills on outlined enemies give 0.5s/1s
-- cooldown. Boost their priority so the triggerbot prefers them during Focus Stance.
local FOCUS_OUTLINE_NAME           = "broker_proximity_target"
local FOCUS_RESOLVE_PRIORITY_BONUS = 3

local DAEMONHOST_BREEDS = {
    chaos_daemonhost = true,
    chaos_mutator_daemonhost = true,
}

local POXHOUNDS_BREEDS = {
    chaos_hound = true,
    chaos_hound_mutator = true,
	chaos_armored_hound = true,
}

-- Per-breed ordered aim zone list. Each zone is tried front-to-back; the first
-- one with a clear line-of-sight wins. "actor" zones use Actor.world_bounds()
-- to get the actual collision-shape center (not the actor origin/attachment);
-- "node" zones use Unit.world_position() on the named skeleton node.
local BREED_AIM_ZONES = {
    chaos_beast_of_nurgle = {
        { type = "actor", name = "c_weakspot",      top_bias = 0.5 }, -- blob on back (1.0x ranged mult)
        { type = "actor", name = "c_tonguespline03"               }, -- mid-tongue (visible when BoN faces player)
        { type = "node",  name = "j_head" },
    },
    renegade_executor = {
        ignore_weakspot = true,
        { type = "node", name = "j_spine1" },
    },
    renegade_plasma_gunner = {
        ignore_weakspot = true,
        { type = "node", name = "j_spine1" },
    },
	renegade_twin_captain = {
        ignore_weakspot = true,
        { type = "node", name = "j_spine1" },
    },
	renegade_twin_captain_two = {
        ignore_weakspot = true,
        { type = "node", name = "j_spine1" },
    },
	chaos_ogryn_houndmaster = {
        ignore_weakspot = true,
        { type = "node", name = "j_spine1" },
    },
	chaos_armored_hound = {
        ignore_weakspot = true,
        { type = "node", name = "j_lefthand" },
    },
}
local DEFAULT_AIM_ZONES = { { type = "node", name = "j_head" } }

-- Maps each priority_profile value to the setting-key prefix used in gambits_data.lua.
-- "custom" uses no prefix (the base priority_targets group).
local PROFILE_PREFIXES = {
    custom  = "",
    veteran = "veteran_",
    zealot  = "zealot_",
    psyker  = "psyker_",
    ogryn   = "ogryn_",
    adamant = "adamant_",
    broker  = "broker_",
    cryptic = "cryptic_",
}

local function get_player_archetype()
    local player = Managers.player:local_player(1)
    if not player then return nil end
    local profile = player:profile()
    return profile and profile.archetype and profile.archetype.name
end

local cached_settings  -- forward declaration; initialized below at refresh_settings()

local function get_active_class()
    local profile = cached_settings.priority_profile or "auto"
    if profile == "auto" then
        return get_player_archetype() or "custom"
    end
    return profile
end

local math_rad = math.rad
local math_cos = math.cos
local math_atan2 = math.atan2
local math_asin = math.asin
local math_sin = math.sin
local math_abs = math.abs
local math_min = math.min
local Vector3_normalize = Vector3.normalize
local Vector3_dot = Vector3.dot
local Vector3_length = Vector3.length
local ScriptUnit_has_extension = ScriptUnit.has_extension
local ScriptUnit_extension = ScriptUnit.extension
local Unit_node = Unit.node
local Unit_world_position = Unit.world_position
local Actor_unit = Actor.unit
local Actor_world_bounds = Actor.world_bounds
local PhysicsWorld_raycast = PhysicsWorld.raycast
local World_physics_world = World.physics_world
local Application_main_world = Application.main_world
local Quaternion_forward = Quaternion.forward
local table_sort = table.sort
local pairs = pairs
local next = next

-- Pre-allocated reusable table and comparator to reduce GC pressure
local reusable_enemies = {}
local function priority_comparator(a, b)
    if a.priority ~= b.priority then
        return a.priority > b.priority
    end
    return a.distance_sq < b.distance_sq
end

-- Cached settings, refreshed on change (forward-declared above get_active_class)
cached_settings = {}
local function refresh_settings()
    cached_settings.enable_triggerbot = mod:get("enable_triggerbot")
    cached_settings.triggerbot_keybind = mod:get("triggerbot_keybind")
    cached_settings.boss_lock_keybind = mod:get("boss_lock_keybind")
    cached_settings.require_main_weapon = mod:get("require_main_weapon")
    cached_settings.use_mouse2_fallback = mod:get("use_mouse2_fallback")
    cached_settings.enable_fov_check = mod:get("enable_fov_check")
    cached_settings.fov_angle = mod:get("fov_angle")
    cached_settings.disable_when_teammates_are_dead = mod:get("disable_when_teammates_are_dead")
    cached_settings.teammates_dead_fov_angle = mod:get("teammates_dead_fov_angle")
    cached_settings.teammates_dead_smooth = mod:get("teammates_dead_smooth")
    cached_settings.priority_profile = mod:get("priority_profile")
    cached_settings.enable_spread_compensation = mod:get("enable_spread_compensation")
    cached_settings.enable_auto_guard = mod:get("enable_auto_guard")
    cached_settings.auto_guard_range = mod:get("auto_guard_range")
    cached_settings.auto_guard_heavy_only = mod:get("auto_guard_heavy_only")
    cached_settings.specials_only = mod:get("specials_only")

    -- Build a [class][breed_name] -> priority lookup table for get_breed_priority.
    local pt = cached_settings.priority_target or {}
    local pb = cached_settings.profile_behaviors or {}
    for class, prefix in pairs(PROFILE_PREFIXES) do
        local class_tbl = pt[class] or {}
        for breed_name, base_key in pairs(BREED_PRIORITY_MAP) do
            class_tbl[breed_name] = mod:get(prefix .. base_key) or 0
        end
        pt[class] = class_tbl

        pb[class] = {
            triggerbot_use_raycast        = mod:get(prefix .. "triggerbot_use_raycast"),
            triggerbot_weakspot_only      = mod:get(prefix .. "triggerbot_weakspot_only"),
            triggerbot_respect_priority   = mod:get(prefix .. "triggerbot_respect_priority"),
            wait_for_crits                = mod:get(prefix .. "wait_for_crits"),
            wait_for_opening_salvo        = mod:get(prefix .. "wait_for_opening_salvo"),
            ranged_regular_targeted_only  = mod:get(prefix .. "ranged_regular_targeted_only"),
            ranged_regular_aim_angle      = mod:get(prefix .. "ranged_regular_aim_angle"),
        }
    end
    cached_settings.priority_target = pt
    cached_settings.profile_behaviors = pb
end
refresh_settings()

mod.on_setting_changed = function(setting_id)
    refresh_settings()
end

local function get_daemonhost_priority(breed_name, unit, priority)
    if breed_name == "chaos_mutator_daemonhost" then
        -- Block during the chanting ritual (stages 1-5); allow only at stage 6 (aggroed).
        -- The passive action writes stage=6 via the game object field when it leaves.
        local go_id = Managers.state.unit_spawner and Managers.state.unit_spawner:game_object_id(unit)
        if not go_id then return 0 end
        local gs = Managers.state.game_session and Managers.state.game_session:game_session()
        if not gs then return 0 end
        local stage = GameSession.game_object_field(gs, go_id, "stage")
        if stage ~= 6 then return 0 end
    else
        -- For chaos_daemonhost: a sleeping one (stage=1, passive) must not be targeted,
        -- but a Mortis-spawned one (also stage=1, already aggroed) must be. The stage
        -- field can't distinguish them — both start at 1. Use boss_encounter_started
        -- instead: the server sends rpc_start_boss_encounter when aggro() fires, which
        -- sets this flag on the client husk. Sleeping daemonhost = false; aggroed = true.
        local boss_ext = ScriptUnit_has_extension(unit, "boss_system")
        if not boss_ext or not boss_ext._boss_encounter_started then return 0 end
    end
    return priority
end

local function is_poxburster_safe_to_target(unit)
    local pox_pos = POSITION_LOOKUP[unit]
    if not pox_pos then
        return false
    end

    local human_players = Managers.player:human_players()
    for _, player in pairs(human_players) do
        if player.player_unit and player:unit_is_alive() then
            local player_pos = POSITION_LOOKUP[player.player_unit]
            if player_pos then
                local diff = pox_pos - player_pos
                if Vector3_dot(diff, diff) <= POXBURSTER_SAFE_RADIUS_SQ then
                    return false
                end
            end
        end
    end

    return true
end

local function get_active_profile_behaviors()
    local class = get_active_class()
    local pb = cached_settings.profile_behaviors
    return (pb and pb[class]) or (pb and pb["custom"]) or {}
end

local function get_breed_priority(breed_name, unit, active_class)
    local tbl = cached_settings.priority_target[active_class or get_active_class()]
    local priority = (tbl and tbl[breed_name]) or 0
    if priority > 0 and DAEMONHOST_BREEDS[breed_name] then
        return get_daemonhost_priority(breed_name, unit, priority)
    end
    return priority
end

-- Per-frame cache: `_current_frame` is set once at the top of fixed_update so all
-- three callers (guard scan, melee range check, aimbot) share the same table.
local _current_frame          = 0
local _minion_entities_frame  = -1
local _minion_entities_cache  = nil

local function get_minion_entities()
    if _current_frame == _minion_entities_frame then
        return _minion_entities_cache
    end
    local extension_manager = Managers.state and Managers.state.extension
    if not extension_manager then
        _minion_entities_cache = nil
        _minion_entities_frame = _current_frame
        return nil
    end
    local entities = extension_manager:get_entities("MinionHuskLocomotionExtension")
    if not next(entities) then
        entities = extension_manager:get_entities("MinionLocomotionExtension")
        if not next(entities) then
            _minion_entities_cache = nil
            _minion_entities_frame = _current_frame
            return nil
        end
    end
    _minion_entities_cache = entities
    _minion_entities_frame = _current_frame
    return entities
end

local function is_valid_enemy_unit(unit, breed)
    local is_ritualist = breed.tags and breed.tags.ritualist
    if boss_lock_pressed and not breed.is_boss and not is_ritualist then
        return false
    end
    if not boss_lock_pressed and is_ritualist then
        return false
    end
    local breed_name = breed.name
    if DAEMONHOST_BREEDS[breed_name] and get_daemonhost_priority(breed_name, unit, 1) == 0 then
        return false
    end
    if POXBURSTER_BREEDS[breed_name] and not is_poxburster_safe_to_target(unit) then
        return false
    end
    return true
end

local function is_focus_resolve_active(player_unit)
    local talent_ext = ScriptUnit_has_extension(player_unit, "talent_system")
    if not talent_ext then
        if debug_vars.focus_resolve then
            mod:info("[focus_resolve] no talent_system extension on player_unit")
        end
        return false
    end
    local has_rule = talent_ext:has_special_rule("broker_focus_cooldown_regain")
    if not has_rule then
        if debug_vars.focus_resolve then
            mod:info("[focus_resolve] special rule broker_focus_cooldown_regain NOT found")
        end
        return false
    end
    local buff_ext = ScriptUnit_has_extension(player_unit, "buff_system")
    if not buff_ext then
        if debug_vars.focus_resolve then
            mod:info("[focus_resolve] no buff_system extension on player_unit")
        end
        return false
    end
    local improved = buff_ext:has_buff_using_buff_template("broker_focus_stance_improved")
    local base     = buff_ext:has_buff_using_buff_template("broker_focus_stance")
    if debug_vars.focus_resolve then
        mod:info("[focus_resolve] rule=true improved_stance=%s base_stance=%s", tostring(improved), tostring(base))
    end
    return improved or base
end

local function get_all_enemies()
    local entities = get_minion_entities()
    if not entities then
        return reusable_enemies, 0
    end

    local player = Managers.player:local_player(1)
    local player_unit = player and player.player_unit
    local player_pos = player_unit and POSITION_LOOKUP[player_unit]

    local active_class = get_active_class()
    local behaviors = get_active_profile_behaviors()
    local ranged_targeted_only = behaviors.ranged_regular_targeted_only
    local _aim_angle = ranged_targeted_only and (behaviors.ranged_regular_aim_angle or 0) or 0
    local ranged_aim_min_dot = _aim_angle > 0 and math_cos(math_rad(_aim_angle)) or nil
    local specials_only = cached_settings.specials_only
    local need_go_lookup = specials_only or ranged_targeted_only
    local game_session = need_go_lookup and Managers.state.game_session and Managers.state.game_session:game_session()
    local unit_spawner = need_go_lookup and Managers.state.unit_spawner
    local player_go_id = ranged_targeted_only and player_unit and unit_spawner and unit_spawner:game_object_id(player_unit)

    local focus_resolve = player_unit and is_focus_resolve_active(player_unit)
    local ext_mgr = focus_resolve and Managers.state.extension
    local has_os = ext_mgr and ext_mgr:has_system("outline_system")
    local outline_system = has_os and ext_mgr:system("outline_system")

    if debug_vars.focus_resolve then
        local _now = Managers.time:time("main") or 0
        if _now - debug_vars.focus_resolve_last_log >= 1.0 then
            debug_vars.focus_resolve_last_log = _now
            mod:info("[focus_resolve] active=%s has_outline_system=%s", tostring(focus_resolve ~= nil and focus_resolve ~= false), tostring(has_os ~= nil and has_os ~= false))
        end
    end

    local n = 0
    local n_outlined = 0

    for unit, _ in pairs(entities) do
        local health_extension = ScriptUnit_has_extension(unit, "health_system")
        if health_extension and health_extension:is_alive() then
            local unit_data_ext = ScriptUnit_extension(unit, "unit_data_system")
            local breed = unit_data_ext:breed()
            if not breed or breed.breed_type == "player" or (breed.name and breed.name:find("hazard")) then
                goto next_unit
            end

            if not is_valid_enemy_unit(unit, breed) then
                goto next_unit
            end

            if specials_only and not (breed.tags and breed.tags.special and not POXHOUNDS_BREEDS[breed.name]) and not (breed.tags and breed.tags.ritualist) then
                local go_id = unit_spawner and unit_spawner:game_object_id(unit)
                local target_unit_id = go_id and game_session and GameSession.game_object_field(game_session, go_id, "target_unit_id")
                if not target_unit_id or target_unit_id == NetworkConstants.invalid_game_object_id then
                    goto next_unit
                end
            end

            local breed_name = breed.name
            local priority = get_breed_priority(breed_name, unit, active_class)

            if ranged_targeted_only and priority > 0 and BREED_PRIORITY_MAP[breed_name] == "target_ranged_regular" then
                if not player_go_id then goto next_unit end
                local go_id = unit_spawner and unit_spawner:game_object_id(unit)
                local target_id = go_id and game_session and GameSession.game_object_field(game_session, go_id, "target_unit_id")
                if target_id ~= player_go_id then goto next_unit end
                if ranged_aim_min_dot and player_pos then
                    local enemy_pos = POSITION_LOOKUP[unit]
                    if enemy_pos then
                        local aim_dir = GameSession.game_object_field(game_session, go_id, "aim_direction")
                        if not aim_dir then goto next_unit end
                        if Vector3_dot(aim_dir, Vector3_normalize(player_pos - enemy_pos)) < ranged_aim_min_dot then
                            goto next_unit
                        end
                    end
                end
            end

            local pos = POSITION_LOOKUP[unit]
            local dist_sq = 0
            if player_pos and pos then
                local diff = pos - player_pos
                dist_sq = Vector3_dot(diff, diff)
            end
            if outline_system and outline_system:has_outline(unit, FOCUS_OUTLINE_NAME) then
                priority = priority + FOCUS_RESOLVE_PRIORITY_BONUS
                n_outlined = n_outlined + 1
            end
            if priority > 0 then
                n = n + 1
                local entry = reusable_enemies[n]
                if entry then
                    entry.unit = unit
                    entry.position = pos
                    entry.priority = priority
                    entry.breed_name = breed_name
                    entry.distance_sq = dist_sq
                else
                    reusable_enemies[n] = {
                        unit = unit,
                        position = pos,
                        breed_name = breed_name,
                        priority = priority,
                        distance_sq = dist_sq,
                    }
                end
            end

            ::next_unit::
        end
    end

    -- Clear stale trailing entries
    for i = n + 1, #reusable_enemies do
        reusable_enemies[i] = nil
    end

    if debug_vars.focus_resolve and outline_system then
        local _now = Managers.time:time("main") or 0
        if _now - debug_vars.focus_resolve_last_log >= 1.0 then
            debug_vars.focus_resolve_last_log = _now
            mod:info("[focus_resolve] enemies_in_pool=%d outlined_boosted=%d", n, n_outlined)
        end
    end

    if n > 1 then
        table_sort(reusable_enemies, priority_comparator)
    end

    return reusable_enemies, n
end

local function is_in_fov(enemy_unit, camera_pos, camera_forward, min_dot)
    local head_node = Unit_node(enemy_unit, "j_head")
    if not head_node then
        return false
    end
    local head_pos = Unit_world_position(enemy_unit, head_node)
    return Vector3_dot(camera_forward, Vector3_normalize(head_pos - camera_pos)) >= min_dot
end

local PI_2 = math.pi * 2
local SPREAD_DEFAULT_MIN_RATIO = 0.25
local SPREAD_DEFAULT_RANDOM_RATIO = 0.75
local SPREAD_DEFAULT_FIRST_SHOT_MIN_RATIO = 0.25
local SPREAD_DEFAULT_FIRST_SHOT_RANDOM_RATIO = 0.4
local SPREAD_DEFAULT_MAX_YAW_DELTA = 2
local SPREAD_DEFAULT_MAX_PITCH_DELTA = 3

-- Deterministically predict the spread offset that randomized_spread will apply
-- on the next shot.  Reads component data directly via read_component to avoid
-- accessing write-handle fields outside the spread system's update phase.
-- Returns the offset quaternion (pitch_rot * yaw_rot), or nil when no spread
-- template is active.
local function predict_spread_offset(player_unit)
    local weapon_ext = ScriptUnit_has_extension(player_unit, "weapon_system")
    if not weapon_ext then
        return nil
    end

    local spread_template = weapon_ext:spread_template()
    if not spread_template then
        return nil
    end

    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    local movement_state = unit_data_ext:read_component("movement_state")
    local locomotion = unit_data_ext:read_component("locomotion")
    local inair_state = unit_data_ext:read_component("inair_state")
    local weapon_movement_state = WeaponMovementState.translate_movement_state_component(movement_state, locomotion, inair_state)
    local spread_settings = spread_template[weapon_movement_state]

    if not spread_settings then
        return nil
    end

    local rs = spread_settings.randomized_spread or {}
    local spread_control = unit_data_ext:read_component("spread_control")
    local spread = unit_data_ext:read_component("spread")
    local shooting_status = unit_data_ext:read_component("shooting_status")
    local suppression = unit_data_ext:read_component("suppression")

    local buff_ext = ScriptUnit_extension(player_unit, "buff_system")
    local spread_modifier = buff_ext:stat_buffs().spread_modifier or 1
    local current_pitch = spread.pitch * spread_modifier
    local current_yaw = spread.yaw * spread_modifier

    current_pitch, current_yaw = Suppression.apply_suppression_offsets_to_spread(suppression, current_pitch, current_yaw)

    local first_shot = shooting_status.num_shots == 0
    local min_ratio = first_shot and (rs.first_shot_min_ratio or SPREAD_DEFAULT_FIRST_SHOT_MIN_RATIO) or (rs.min_ratio or SPREAD_DEFAULT_MIN_RATIO)
    local random_ratio = first_shot and (rs.first_shot_random_ratio or SPREAD_DEFAULT_FIRST_SHOT_RANDOM_RATIO) or (rs.random_ratio or SPREAD_DEFAULT_RANDOM_RATIO)

    local seed = spread_control.seed
    local previous_yaw = spread_control.previous_yaw_offset
    local previous_pitch = spread_control.previous_pitch_offset

    local random_value
    seed, random_value = math.next_random(seed)
    local multiplier = min_ratio + random_ratio * random_value

    seed, random_value = math.next_random(seed)
    local roll = random_value * PI_2
    local yaw_offset = math_sin(roll) * current_yaw * multiplier
    local pitch_offset = math_cos(roll) * current_pitch * multiplier

    if first_shot then
        previous_yaw = yaw_offset
        previous_pitch = pitch_offset
    end

    -- Replicate _rotation_from_offset for yaw
    local yaw_diff = math_abs(previous_yaw - yaw_offset)
    local max_yaw_delta = rs.max_yaw_delta or SPREAD_DEFAULT_MAX_YAW_DELTA
    local yaw_t = yaw_diff <= 0.00001 and 1 or math_min(max_yaw_delta / yaw_diff, 1)
    local lerped_yaw = math.lerp(previous_yaw, yaw_offset, yaw_t)
    local yaw_rot = Quaternion(Vector3.up(), math.degrees_to_radians(lerped_yaw))

    -- Replicate _rotation_from_offset for pitch
    local pitch_diff = math_abs(previous_pitch - pitch_offset)
    local max_pitch_delta = rs.max_pitch_delta or SPREAD_DEFAULT_MAX_PITCH_DELTA
    local pitch_t = pitch_diff <= 0.00001 and 1 or math_min(max_pitch_delta / pitch_diff, 1)
    local lerped_pitch = math.lerp(previous_pitch, pitch_offset, pitch_t)
    local pitch_rot = Quaternion(Vector3.right(), math.degrees_to_radians(lerped_pitch))

    -- final = input * pitch * yaw  =>  offset = pitch * yaw
    return Quaternion.multiply(pitch_rot, yaw_rot)
end

-- Fallback constants for Surgical (chance_based_on_aim_time) prediction.
-- Real values are read from the buff template at runtime; see predict_crit_wait.
local SURGICAL_MAX_STACKS_FALLBACK = 10
local SURGICAL_CHANCE_PER_STEP_FALLBACK = 0.05

-- Delegates to CriticalStrike.is_critical_strike, which lazy-requires
-- PseudoRandomDistribution at runtime (when NetworkConstants is available).
-- On the first call we probe with pcall; if it succeeds we replace ourselves
-- with a zero-overhead direct call; if it fails we fall back to always-false
-- (safe: predict_crit_wait will fire immediately rather than waiting).
--
-- prd_flip returns all three values (result, new_state, new_seed) so callers
-- can chain multiple PRD checks (e.g. Leadbelcher lucky-strike then crit).
local prd_would_crit
local prd_flip          -- like prd_would_crit but returns (result, new_state, new_seed)
local _prd_available = false

local function _prd_direct(chance, state, seed)
    return (CriticalStrike.is_critical_strike(chance, state, seed))
end
local function _prd_flip_direct(chance, state, seed)
    return CriticalStrike.is_critical_strike(chance, state, seed)
end
local function _prd_fallback()
    return false
end
local function _prd_flip_fallback(chance, state, seed)
    return false, state, seed
end
local function _prd_probe(chance, state, seed)
    local ok, result = pcall(CriticalStrike.is_critical_strike, chance, state, seed)
    if ok then
        prd_would_crit = _prd_direct
        prd_flip       = _prd_flip_direct
        _prd_available = true
        return result
    end
    prd_would_crit = _prd_fallback
    prd_flip       = _prd_flip_fallback
    return false
end
local function _prd_flip_probe(chance, state, seed)
    local ok, r, ns, nse = pcall(CriticalStrike.is_critical_strike, chance, state, seed)
    if ok then
        prd_would_crit = _prd_direct
        prd_flip       = _prd_flip_direct
        _prd_available = true
        return r, ns, nse
    end
    prd_would_crit = _prd_fallback
    prd_flip       = _prd_flip_fallback
    return false, state, seed
end
prd_would_crit = _prd_probe
prd_flip       = _prd_flip_probe


-- Maps armor_type string to the corresponding attacker stat_buff key used by
-- _apply_armor_type_buffs_to_damage in the engine damage path.
local _ARMOR_STAT_BUFF_KEY = {
    unarmored                 = "unarmored_damage",
    armored                   = "armored_damage",
    resistant                 = "resistant_damage",
    berserker                 = "berserker_damage",
    super_armor               = "super_armor_damage",
    disgustingly_resilient    = "disgustingly_resilient_damage",
}

local function _estimate_shot_damage(player_unit, target_unit, hit_zone_name_or_bool, charge_level)
    if not Unit.alive(target_unit) then return nil end

    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    if not unit_data_ext then return nil end

    local weapon_action_comp = unit_data_ext:read_component("weapon_action")
    if not weapon_action_comp then return nil end

    local weapon_template = WeaponTemplate.current_weapon_template(weapon_action_comp)
    if not weapon_template or not weapon_template.actions then return nil end

    -- Prefer zoomed then hip, including charge-weapon variants (e.g. Helborne Lasgun).
    local actions = weapon_template.actions
    local shoot_action = actions.action_shoot_zoomed
        or actions.action_zoom_shoot_charged
        or actions.action_shoot_hip
        or actions.action_shoot_hip_charged
    if not shoot_action then return nil end

    local fire_config = shoot_action.fire_configuration
    if not fire_config then return nil end

    local hst = fire_config.hit_scan_template
    local damage_profile = hst and hst.damage and hst.damage.impact
                           and hst.damage.impact.damage_profile
    if not damage_profile or not damage_profile.targets then return nil end

    local power_level = (hst and hst.power_level) or PowerLevelSettings.default_power_level

    local breed = Breed.unit_breed_or_nil(target_unit)
    -- Resolve zone name: accept a HitZone string directly, or treat boolean true as "head"
    -- (legacy callers that don't have a zone name from a raycast).
    local zone_name = type(hit_zone_name_or_bool) == "string" and hit_zone_name_or_bool
        or (hit_zone_name_or_bool == true and HitZone.hit_zone_names.head)
        or nil
    local hit_weakspot = zone_name == HitZone.hit_zone_names.head
        or zone_name == HitZone.hit_zone_names.weakspot
    -- Armor.armor_type handles the full resolution chain: buff keyword overrides
    -- (super_armor_override, infested_head_armor_override), active toughness, per-zone
    -- hitzone_armor_override, and finally breed.armor_type as fallback.
    local armor_type = Armor.armor_type(target_unit, breed, zone_name, attack_types.ranged)
        or "unarmored"

    local target_settings = damage_profile.targets[1] or damage_profile.targets.default_target
    if not target_settings then return nil end

    -- Get quality-based lerp values for the SHOOT action, not the running action.
    -- DamageProfile.lerp_values uses the currently-running action; during ADS-hold
    -- (action_zoom) that action has no damage lerp entries, so quality-based values
    -- (power_distribution, ADM, etc.) fall back to DEFALT_FALLBACK_LERP_VALUE=0.5.
    -- We bypass this by reading the shoot action's slot directly from the weapon table.
    local shoot_action_name = actions.action_shoot_zoomed and "action_shoot_zoomed"
        or actions.action_zoom_shoot_charged and "action_zoom_shoot_charged"
        or actions.action_shoot_hip and "action_shoot_hip"
        or "action_shoot_hip_charged"
    local lerp_values
    do
        local w_ext = ScriptUnit_has_extension(player_unit, "weapon_system")
        if w_ext then
            local ok, raw = pcall(function()
                local w = w_ext:_wielded_weapon(w_ext._inventory_component, w_ext._weapons)
                if not w or not w.damage_profile_lerp_values then return nil end
                local al = w.damage_profile_lerp_values[shoot_action_name]
                if not al then return nil end
                return damage_profile.name and al[damage_profile.name] or al
            end)
            if ok and raw then
                raw.current_target_settings_lerp_values = raw.current_target_settings_lerp_values or {}
                lerp_values = raw
            end
        end
        if not lerp_values then
            lerp_values = DamageProfile.lerp_values(damage_profile, player_unit)
        end
    end

    -- Pull the player's active stat buffs first — needed for correct power-level scaling.
    local buff_ext   = ScriptUnit_extension(player_unit, "buff_system")
    local stat_buffs = buff_ext and buff_ext:stat_buffs() or {}

    -- Pull target stat buffs for weakspot_damage_taken.
    local target_buff_ext   = ScriptUnit_extension(target_unit, "buff_system")
    local target_stat_buffs = target_buff_ext and target_buff_ext:stat_buffs() or {}

    -- Distance for dropoff and damage-near/far buffs.
    local player_pos = Unit_world_position(player_unit, 1)
    local target_pos = Unit_world_position(target_unit, 1)
    local distance   = Vector3_length(target_pos - player_pos)

    -- Compute base damage using the weapon's power_distribution_ranged (near/far).
    -- DamageProfile.dropoff_scalar uses damage_profile.ranges (not DamageSettings thresholds).
    local dropoff_scalar = DamageProfile.dropoff_scalar(distance, damage_profile, lerp_values)
    local scaled_pl   = PowerLevel.scale_by_charge_level(power_level, charge_level, damage_profile.charge_level_scaler)
    -- DamageCalculation.calculate multiplies power_level by target_settings.power_level_multiplier
    -- before calling _power_level_scaled_damage (lines 51-56 in damage_calculation.lua).
    local pl_mult = 1
    if target_settings.power_level_multiplier then
        local pl_lerp_value = DamageProfile.lerp_value_from_path(lerp_values, "targets", 1, "power_level_multiplier")
        pl_mult = DamageProfile.lerp_damage_profile_entry(target_settings.power_level_multiplier, pl_lerp_value)
        scaled_pl = scaled_pl * pl_mult
    end
    local attack_pl   = DamageProfile.power_distribution_from_power_level(
        scaled_pl, "attack", damage_profile, target_settings, false, dropoff_scalar, armor_type, lerp_values,
        stat_buffs, attack_types.ranged, hit_weakspot, player_unit, target_unit)
    local dmg_table   = PowerLevelSettings.damage_output[armor_type] or PowerLevelSettings.damage_output.unarmored
    local base_dmg    = dmg_table.min + (dmg_table.max - dmg_table.min) * PowerLevel.power_level_percentage(attack_pl)
    if not base_dmg or base_dmg <= 0 then return nil end

    -- ── damage_stat_buffs (mirrors _calculate_damage_buff, additive) ──────────
    local dmg_mult = stat_buffs.damage or 1

    dmg_mult = dmg_mult + (stat_buffs.ranged_damage or 1) - 1

    -- Per-breed specific buff ("damage_vs_chaos_ogryn_executor" etc.).
    if breed then
        local bkey = "damage_vs_" .. breed.name
        dmg_mult = dmg_mult + (stat_buffs[bkey] or 1) - 1
    end

    -- Breed-tag-based buffs.
    local tags = breed and breed.tags or {}
    if tags.ogryn   then dmg_mult = dmg_mult + (stat_buffs.damage_vs_ogryn               or 1) - 1 end
    if tags.ogryn or tags.monster then
                         dmg_mult = dmg_mult + (stat_buffs.damage_vs_ogryn_and_monsters   or 1) - 1 end
    if tags.monster then dmg_mult = dmg_mult + (stat_buffs.damage_vs_monsters             or 1) - 1 end
    if tags.elite   then dmg_mult = dmg_mult + (stat_buffs.damage_vs_elites               or 1) - 1 end
    if tags.special then dmg_mult = dmg_mult + (stat_buffs.damage_vs_specials             or 1) - 1 end
    if tags.horde   then dmg_mult = dmg_mult + (stat_buffs.damage_vs_horde                or 1) - 1 end

    -- Distance-based damage_near/far buffs use DamageSettings thresholds.
    local close_range = DamageSettings.ranged_close
    local far_range   = DamageSettings.ranged_far
    local close_buff  = stat_buffs.damage_near or 1
    local far_buff    = stat_buffs.damage_far  or 1
    local rfar_buff   = stat_buffs.ranged_damage_far or 1
    local dist_scalar = math.clamp((distance - close_range) / (far_range - close_range), 0, 1)
    dmg_mult = dmg_mult + math.lerp(close_buff, far_buff + rfar_buff - 1, math.sqrt(dist_scalar)) - 1

    -- ── Armor-type multiplier (applied after ADM+finesse+zone) ───────────────
    local armor_key  = _ARMOR_STAT_BUFF_KEY[armor_type]
    local armor_mult = armor_key and (stat_buffs[armor_key] or 1) or 1

    -- ── ADM + rending ─────────────────────────────────────────────────────────
    -- Raw ADM from the damage profile (before rending).
    -- Pass charge_level so the game's lerp between armor_damage_modifier_ranged
    -- (uncharged) and armor_damage_modifier_ranged_charged (full charge) is applied.
    local adm_normal = DamageProfile.armor_damage_modifier(
        "attack", damage_profile, target_settings, lerp_values,
        armor_type, false, nil, false, charge_level)
    local adm_crit = DamageProfile.armor_damage_modifier(
        "attack", damage_profile, target_settings, lerp_values,
        armor_type, true, nil, false, charge_level)

    -- Rending pushes the effective ADM up before finesse is applied.
    -- _rending_multiplier sums 17 components (all default 1) and subtracts 17;
    -- for a plain ranged shot only attacker/target rending and ranged_rending are non-unity.
    local base_rending = (stat_buffs.rending_multiplier         or 1)
                       + (target_stat_buffs.rending_multiplier  or 1)
                       + (stat_buffs.ranged_rending_multiplier  or 1)
                       - 3
    base_rending = math.min(base_rending, 1)
    local rending_armor_mult = ArmorSettings.rending_armor_type_multiplier[armor_type] or 0
    local rending            = base_rending * rending_armor_mult
    local overdmg_mult       = ArmorSettings.overdamage_rending_multiplier[armor_type] or 0

    local function _rend(raw_adm)
        local adm_lost = math.max(1 - raw_adm, 0)
        if raw_adm >= 1 then
            return raw_adm + rending * overdmg_mult
        elseif adm_lost < rending then
            return 1 + (rending - adm_lost) * overdmg_mult
        else
            return raw_adm + rending
        end
    end

    local rended_adm_normal = _rend(adm_normal)
    local rended_adm_crit   = _rend(adm_crit)

    -- ── Finesse (mirrors _finesse_boost_damage in damage_calculation.lua) ────
    -- ui_finesse_multiplier returns (1 + raw_boost) where raw_boost =
    -- boost_curve_frac * default_boost_curve_multiplier.  The actual damage
    -- multiplies raw_boost by finesse_buff_damage_multiplier assembled below.
    local boost_normal = (DamageCalculation.ui_finesse_multiplier(
        damage_profile, target_settings, armor_type, hit_weakspot, false, lerp_values) or 1) - 1
    local boost_crit = (DamageCalculation.ui_finesse_multiplier(
        damage_profile, target_settings, armor_type, hit_weakspot, true, lerp_values) or 1) - 1

    -- weakspot_damage_stat_buff (only when hit_weakspot).
    local weakspot_stat = 1
    if hit_weakspot then
        weakspot_stat = (target_stat_buffs.weakspot_damage_taken or 1)
            + (stat_buffs.weakspot_damage        or 1) - 1
            + (stat_buffs.ranged_weakspot_damage or 1) - 1
    end

    -- critical_damage_stat_buff: csd + rcsd + melee - 2 (melee defaults to 1 for ranged).
    local crit_dmg_stat = (stat_buffs.critical_strike_damage       or 1)
                        + (stat_buffs.ranged_critical_strike_damage or 1)
                        + 1 - 2

    -- crit_weakspot only applies when crit AND hit_weakspot.
    local crit_ws_stat = hit_weakspot and (stat_buffs.critical_strike_weakspot_damage or 1) or 1

    -- Optional bonuses (default 1 → zero net contribution each).
    local finesse_mod_bonus  = stat_buffs.finesse_modifier_bonus         or 1
    local ranged_fb_bonus    = stat_buffs.ranged_finesse_modifier_bonus  or 1
    -- close_range finesse bonus (uses DamageSettings threshold, same as the source).
    local close_fb = 1
    if distance < DamageSettings.ranged_close then
        close_fb = stat_buffs.finesse_close_range_modifier or 1
    end

    -- Assemble finesse_buff_damage_multiplier from source lines 758-761:
    --   fbm = ws + (crit_dmg + crit_ws + finesse_mod - 3) + (melee_fb(1) + ranged_fb + close_fb - 3)
    -- With all defaults = 1: fbm_normal = ws; fbm_crit = ws + crit_dmg + crit_ws - 2
    local fbm_normal = weakspot_stat
        + 1 + 1 + finesse_mod_bonus - 3          -- non-crit: crit_dmg=1, crit_ws=1
        + 1 + ranged_fb_bonus + close_fb - 3     -- melee_fb=1 (ranged)
    local fbm_crit   = weakspot_stat
        + crit_dmg_stat + crit_ws_stat + finesse_mod_bonus - 3
        + 1 + ranged_fb_bonus + close_fb - 3

    local finesse_normal = 1 + boost_normal * fbm_normal
    local finesse_crit   = 1 + boost_crit   * fbm_crit

    local normal_dmg = base_dmg * rended_adm_normal * dmg_mult * armor_mult * finesse_normal
    local crit_dmg   = base_dmg * rended_adm_crit   * dmg_mult * armor_mult * finesse_crit


    return normal_dmg, crit_dmg
end

-- Predicts whether the next shot will crit, and if not, whether waiting for
-- additional Surgical stacks (aim-time crit chance) can produce one.
--
-- Reads the critical_strike component's seed and prd_state, then simulates
-- the PRD flip_coin at increasing chance values (one per hypothetical
-- additional Surgical stack).
-- Returns true if the Efficiency perk (first_shot_ammo_cost_reduction) is ready
-- to fire (off cooldown), or if the player doesn't have the perk at all.
-- The game uses off_cooldown_keywords to add "reduced_ammo_consumption" to the
-- buff extension whenever the perk is not cooling down, so a keyword check is
-- all that's needed once we've confirmed the perk is equipped.
local EFFICIENCY_BUFF_NAME    = "weapon_trait_bespoke_lasgun_p1_first_shot_ammo_cost_reduction"
local EFFICIENCY_KEYWORD      = "reduced_ammo_consumption"
-- Conservative RTT cover: suppress re-fire for this many seconds after each
-- Efficiency shot so the server has time to remove the keyword before we look again.
local EFFICIENCY_FIRE_COOLDOWN = 0.25
local function is_efficiency_ready(player_unit)
    local buff_ext = ScriptUnit_extension(player_unit, "buff_system")
    if not buff_ext then return true end
    if not buff_ext:has_buff_using_buff_template(EFFICIENCY_BUFF_NAME) then return true end
    return buff_ext:has_keyword(EFFICIENCY_KEYWORD)
end

-- Opening Salvo perk: power_bonus_on_first_shot activates only when num_shots == 0
-- (first shot from a fresh magazine).  Hold fire until the magazine resets.
local OPENING_SALVO_BUFF_PATTERN = "power_bonus_on_first_shot"
local function is_opening_salvo_ready(player_unit)
    local buff_ext = ScriptUnit_extension(player_unit, "buff_system")
    if not buff_ext then return true end
    local buffs = buff_ext:buffs()
    local has_perk = false
    local perk_name = nil
    for i = 1, #buffs do
        local name = buffs[i]:template().name
        if name and name:find(OPENING_SALVO_BUFF_PATTERN, 1, true) then
            has_perk = true
            perk_name = name
            break
        end
    end
    if not has_perk then
        if debug_vars.opening_salvo and debug_vars.os_last_num_shots ~= -2 then
            debug_vars.os_last_num_shots = -2
            mod:info("[os_dbg] no power_bonus_on_first_shot buff found on player")
        end
        return true
    end
    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    if not unit_data_ext then return true end
    local shooting_status = unit_data_ext:read_component("shooting_status")
    local num_shots = shooting_status and shooting_status.num_shots
    local ready = num_shots == 0
    if debug_vars.opening_salvo and num_shots ~= debug_vars.os_last_num_shots then
        debug_vars.os_last_num_shots = num_shots
        local clip = 0
        local inv = unit_data_ext:read_component("inventory")
        if inv and inv.wielded_slot then
            local slot_comp = unit_data_ext:read_component(inv.wielded_slot)
            clip = slot_comp and slot_comp.current_ammunition_clip and slot_comp.current_ammunition_clip[1] or 0
        end
        mod:info("[os_dbg] num_shots=%s  clip_remaining=%s  ready=%s  perk=%s", tostring(num_shots), tostring(clip), tostring(ready), tostring(perk_name))
    end
    return ready
end


--
-- Returns:
--   "fire"          -- current chance already crits, or no Surgical / not
--                      aiming / waiting won't help; fire to advance the seed
--   "wait"          -- hold fire until the next Surgical stack produces a crit
local function predict_crit_wait(player_unit)
    local player = Managers.player:local_player(1)
    if not player or not player.player_unit then
        return "fire"
    end

    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    local buff_ext = ScriptUnit_extension(player_unit, "buff_system")

    -- Early-out: guaranteed or prevented crits
    if buff_ext:has_keyword("guaranteed_critical_strike") or
       buff_ext:has_keyword("guaranteed_ranged_critical_strike") then
        return "fire"
    end
    if buff_ext:has_keyword("prevent_critical_strike") then
        return "fire"
    end

    local critical_strike_comp = unit_data_ext:read_component("critical_strike")
    local seed = critical_strike_comp.seed
    local prd_state = critical_strike_comp.prd_state

    local weapon_ext = ScriptUnit_has_extension(player_unit, "weapon_system")
    if not weapon_ext then
        return "fire"
    end
    local weapon_handling_template = weapon_ext:weapon_handling_template() or {}

    -- Current crit chance (all active buffs including current Surgical stacks)
    local current_chance = CriticalStrike.chance(player, weapon_handling_template, true, false, false)
    local rounded = math.round_with_precision(current_chance, 2)

    -- action_shoot.lua calls _check_for_lucky_strike BEFORE _check_for_critical_strike.
    -- Lucky strike always advances component.seed, so the actual crit check sees a seed
    -- 1-2 steps ahead of what we just read.  Simulate the same advance(s) here.
    local talent_ext = ScriptUnit_has_extension(player_unit, "talent_system")
    if talent_ext and _prd_available then
        local sr = SpecialRulesSettings.special_rules
        local has_lb     = talent_ext:has_special_rule(sr.ogryn_leadbelcher)
        local has_lb_imp = talent_ext:has_special_rule(sr.ogryn_leadbelcher_improved)
        if has_lb or has_lb_imp then
            local lb_base = has_lb
                and TalentSettings.ogryn_1.passive_1.free_ammo_proc_chance
                or  TalentSettings.ogryn_1.spec_passive_2.increased_passive_proc_chance
            local sb_lb     = buff_ext:stat_buffs()
            local lb_chance = lb_base + (sb_lb.leadbelcher_chance_bonus or 0)
            if buff_ext:has_keyword("guaranteed_leadbelcher") then lb_chance = 1 end
            local lb_rounded = math.round_with_precision(lb_chance, 2)
            -- For a fresh auto-fire action start(), the game runs LB twice before
            -- the crit check (once in start(), once in _check_for_auto_critical_strike).
            -- For semi-auto or a continuing auto action only 1 LB precedes the crit check.
            local fire_rate  = weapon_handling_template.fire_rate_settings or {}
            local is_auto    = fire_rate.auto_fire_time ~= nil and (fire_rate.max_shots == nil or fire_rate.max_shots == math.huge)
            local action_comp = unit_data_ext:read_component("weapon_action")
            local action_running = action_comp and action_comp.current_action_name == "action_one_hold"
            local lb_advances = (is_auto and not action_running) and 2 or 1
            local last_is_lucky = false
            for _ = 1, lb_advances do
                local is_lucky, lb_new_state, lb_new_seed = prd_flip(lb_rounded, prd_state, seed)
                seed = lb_new_seed
                if is_lucky then prd_state = lb_new_state end
                last_is_lucky = is_lucky
            end
            -- If the next shot will be a Lucky Bullet and the player has the
            -- auto-crit perk (ogryn_leadbelcher_auto_crit), it guarantees a crit —
            -- no need to hold for Surgical stacks.
            if last_is_lucky and talent_ext:has_special_rule(sr.ogryn_leadbelcher_auto_crit) then
                return "fire"
            end
        end
    end

    -- Check if the next shot already crits at current chance
    local crits_now = prd_would_crit(rounded, prd_state, seed)
    if crits_now then
        return "fire"
    end

    -- Must be aiming to gain stacks
    local alternate_fire = unit_data_ext:read_component("alternate_fire")
    if not alternate_fire or not alternate_fire.is_active then
        return "fire"
    end

    -- Read current Surgical stack count and per-step constants from the buff.
    -- No buff found means the perk isn't equipped — fire immediately.
    local current_stacks = nil
    local max_steps = SURGICAL_MAX_STACKS_FALLBACK
    local chance_per_step = SURGICAL_CHANCE_PER_STEP_FALLBACK
    local buffs = buff_ext:buffs()
    for i = 1, #buffs do
        local buff = buffs[i]
        local name = buff:template().name
        if name and name:find("crit_chance_based_on_aim_time", 1, true) then
            current_stacks = buff:visual_stack_count()
            local tmpl = buff:template()
            -- Per-step crit chance: check template_override_data first (set per
            -- weapon tier/level), then fall back to the base template value.
            local crit_key = BuffSettings.stat_buffs.critical_strike_chance
            local ctx_override = buff._template_context and buff._template_context.template_override_data
            chance_per_step = (ctx_override and ctx_override.conditional_stat_buffs and ctx_override.conditional_stat_buffs[crit_key])
                           or (ctx_override and ctx_override.stat_buffs and ctx_override.stat_buffs[crit_key])
                           or (tmpl.conditional_stat_buffs and tmpl.conditional_stat_buffs[crit_key])
                           or SURGICAL_CHANCE_PER_STEP_FALLBACK
            -- Max visual steps: call min_max_step_func if present.
            if tmpl.min_max_step_func then
                local ok, _, m = pcall(tmpl.min_max_step_func, buff._template_data, buff._template_context)
                if ok and m then max_steps = m end
            end
            break
        end
    end

    if current_stacks == nil then
        return "fire"
    end

    -- Simulate each additional stack to see if any produces a crit
    for extra = 1, max_steps - current_stacks do
        local test_chance = math.clamp(current_chance + extra * chance_per_step, 0, 1)
        local rounded_test = math.round_with_precision(test_chance, 2)
        local would_crit = prd_would_crit(rounded_test, prd_state, seed)
        if would_crit then
            -- Need extra more stacks; check if waiting is damage-efficient
            if last_aim_unit then
                local health_ext = ScriptUnit_has_extension(last_aim_unit, "health_system")
                if health_ext and health_ext:is_alive() then
                    local hp = health_ext:current_health()
                    local n_dmg, c_dmg = _estimate_shot_damage(player_unit, last_aim_unit, true)
                    if n_dmg and n_dmg > 0 then
                        local breed = Breed.unit_breed_or_nil(last_aim_unit)
                        local armor_type = breed and breed.armor_type
                        if debug_vars.surgical then
                            if last_aim_unit ~= debug_vars.surgical_last_unit or current_stacks ~= debug_vars.surgical_last_stacks then
                                debug_vars.surgical_last_unit   = last_aim_unit
                                debug_vars.surgical_last_stacks = current_stacks
                                local buff_ext2 = ScriptUnit_extension(player_unit, "buff_system")
                                local sb        = buff_ext2 and buff_ext2:stat_buffs() or {}
                                local armor_key2 = _ARMOR_STAT_BUFF_KEY[armor_type]
                                local ppos = Unit_world_position(player_unit, 1)
                                local tpos = Unit_world_position(last_aim_unit, 1)
                                local dist2 = Vector3_length(tpos - ppos)
                                mod:info("[surgical_dbg] target=%s armor=%s  base=%.3f  crit=%.3f  hp=%.1f  stacks=%d/%d  cur_chance=%.3f  extra_needed=%d  dist=%.1f",
                                    breed and breed.name or "nil", tostring(armor_type),
                                    n_dmg, c_dmg or 0, hp, current_stacks, max_steps, current_chance, extra, dist2)
                                local parts = {}
                                for k, v in pairs(sb) do
                                    local vn = tonumber(v)
                                    if vn and vn ~= 1 and vn ~= 0 then
                                        parts[#parts + 1] = k .. "=" .. string.format("%.4f", vn)
                                    end
                                end
                                table.sort(parts)
                                mod:info("[surgical_dbg] buffs(%d): %s", #parts, table.concat(parts, "  "))
                            end
                        end
                        -- For carapace (super_armor, base ADM=0→crit floors at 0.25) and flak
                        -- (armored, base ADM=0.5, crit adds finesse ~1.5x), crits are valuable
                        -- enough that we only skip the wait if a single normal shot already kills.
                        local bypass_shots = (armor_type == "super_armor" or armor_type == "armored") and 1 or 2
                        if math.ceil(hp / n_dmg) <= bypass_shots then
                            return "fire"
                        end
                    end
                end
            end

            return "wait"
        end
    end

    -- No reachable stack count produces a crit; fire to advance the seed
    return "fire"
end

-- Returns the world-space aim position for a zone descriptor, or nil if the
-- actor/node doesn't exist on this unit. Actor zones with a top_bias field
-- offset upward by (top_bias * z_half_extent) from the AABB center, placing
-- the aim point in the visible upper portion of the collision volume.
local function get_aim_position(unit, zone)
    if zone.type == "actor" then
        local actor = Unit.actor(unit, zone.name)
        if not actor then return nil end
        if zone.top_bias and Actor.is_dynamic(actor) then
            local center, half = Actor_world_bounds(actor)
            if half.z > 0 then
                return Vector3(center.x, center.y, center.z + half.z * zone.top_bias)
            end
            -- AABB not yet computed; fall through to center_of_mass below
        end
        return Actor.is_dynamic(actor) and Actor.center_of_mass(actor) or Actor.position(actor)
    else
        local node = Unit_node(unit, zone.name)
        if not node then return nil end
        return Unit_world_position(unit, node)
    end
end

-- Classifies a single raycast hit actor for LOS / enemy-detection purposes.
-- Handles the universal pre-checks shared by can_see_aim_target and
-- is_reticle_on_enemy so neither caller duplicates the logic.
--   enemy_unit   � if non-nil, only a hit on this unit counts as "hit"; any
--                  other solid unit returns "blocked".
--   target_actor � only meaningful when enemy_unit is non-nil; when set the
--                  hit actor must also match exactly to return "hit".
-- Returns "skip", "blocked", or "hit".
local function classify_los_hit(actor, player_unit, enemy_unit, target_actor)
    if not actor then return "skip" end

    local hit_unit = Actor_unit(actor)
    if not hit_unit then
        return "blocked"
    end
    local zone_name = HitZone.get_name(hit_unit, actor)

    if zone_name == HitZone.hit_zone_names.afro then
        return "skip"
    end
    if zone_name == HitZone.hit_zone_names.shield or
       zone_name == HitZone.hit_zone_names.captain_void_shield then
        return "blocked"
    end
    if hit_unit == player_unit then
        return "skip"
    end
    if Health.is_ragdolled(hit_unit) then
        return "skip"
    end

    if enemy_unit then
        if hit_unit ~= enemy_unit then
            return "blocked"
        end
        if target_actor and actor ~= target_actor then
            return "blocked"
        end
    end

    return "hit"
end

-- Iterates the ordered zones list and returns (true, zone) for the first zone
-- with an unobstructed line of sight from shooting_pos, or (false, nil).
local function can_see_aim_target(enemy_unit, player, shooting_pos, zones)
    local physics_world = World_physics_world(Application_main_world())
    for _, zone in ipairs(zones) do
        local aim_pos = get_aim_position(enemy_unit, zone)
        if not aim_pos then
            goto next_zone
        end

        -- For actor zones pre-fetch the exact actor so we can confirm LOS by
        -- actor identity. This avoids relying on hit_zone_names enums which may
        -- not contain breed-specific zone names (e.g. BoN "tongue").
        local target_actor = zone.type == "actor" and Unit.actor(enemy_unit, zone.name) or nil

        do
            local dir = aim_pos - shooting_pos
            local dist = Vector3_length(dir)
            dir = Vector3_normalize(dir)

            local hits = PhysicsWorld_raycast(physics_world, shooting_pos, dir, dist, "all", "collision_filter", "filter_player_character_shooting_raycast")

            if not hits then
                return true, zone
            end

            local blocked = false
            for i = 1, #hits do
                local result = classify_los_hit(hits[i][4], player.player_unit, enemy_unit, target_actor)
                if result == "hit" then
                    return true, zone
                elseif result == "blocked" then
                    blocked = true
                    break
                end
            end

            if not blocked then
                return true, zone
            end
        end

        ::next_zone::
    end
    return false, nil
end

local function look_at_aim_target(enemy_unit, zone, player, shooting_pos, player_unit, smooth_alpha)
    local aim_pos = get_aim_position(enemy_unit, zone)
    if not aim_pos then return end

    local dir = Vector3_normalize(aim_pos - shooting_pos)
    local base_pitch = math_asin(dir.z)
    local base_yaw = math_atan2(dir.y, dir.x) - HALF_PI

    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    local recoil_component = unit_data_ext:read_component("recoil")
    local sway_component = unit_data_ext:read_component("sway")

    if cached_settings.enable_spread_compensation then
        local spread_offset = predict_spread_offset(player_unit)
        if spread_offset then
            local desired_rot = Quaternion.look(dir, Vector3.up())
            local compensated_rot = Quaternion.multiply(desired_rot, Quaternion.inverse(spread_offset))
            local comp_fwd = Quaternion_forward(compensated_rot)
            base_pitch = math_asin(comp_fwd.z)
            base_yaw = math_atan2(comp_fwd.y, comp_fwd.x) - HALF_PI
        end
    end

    local target_yaw   = base_yaw   - recoil_component.yaw_offset   - sway_component.offset_x
    local target_pitch = base_pitch - recoil_component.pitch_offset  - sway_component.offset_y

    if smooth_alpha and smooth_alpha < 1.0 then
        local fp_component = unit_data_ext:read_component("first_person")
        local cur_fwd = Quaternion_forward(fp_component.rotation)
        local cur_pitch = math_asin(cur_fwd.z)
        local cur_yaw   = math_atan2(cur_fwd.y, cur_fwd.x) - HALF_PI
        -- Shortest-path wrap for yaw
        local dyaw = target_yaw - cur_yaw
        if dyaw >  math.pi then dyaw = dyaw - math.pi * 2 end
        if dyaw < -math.pi then dyaw = dyaw + math.pi * 2 end
        target_yaw   = cur_yaw   + dyaw   * smooth_alpha
        target_pitch = cur_pitch + (target_pitch - cur_pitch) * smooth_alpha
    end

    player:set_orientation(target_yaw, target_pitch, 0)
end

local function get_fire_interval()
    local current_time = Managers.time:time("main") or 0

    -- Rate limiting only matters when we're a client sending RPCs to a remote server.
    -- In solo play or as listen-server host, host() returns our own peer ID,
    -- Network.ping returns 0, and there is no round-trip latency to account for.
    if not Managers.connection or not Managers.connection:is_client() then
        return 0, current_time
    end

    -- Managers.connection:host() returns the dedicated server's peer ID — the same
    -- peer the game itself pings in AdaptiveClockHandlerClient.  Network.ping returns
    -- RTT in seconds; multiplying by 2 gives a conservative one-shot window.
    local host_peer = Managers.connection:host()
    if not host_peer then
        return 0.25, current_time
    end

    local rtt = Network.ping(host_peer)
    if not rtt or rtt == 0 then
        return 0.25, current_time
    end

    return rtt * 2, current_time
end

local function are_teammates_dead()
    local local_player = Managers.player:local_player(1)
    if not local_player or not local_player.player_unit then
        return false
    end

    local human_players = Managers.player:human_players()
    local game_session_manager = Managers.state.game_session
    for _, player in pairs(human_players) do
        if player ~= local_player then
            local peer_id = player:peer_id()
            if game_session_manager:connected_to_client(peer_id) and not player:unit_is_alive() then
                return true
            end
            if player.player_unit and ScriptUnit_has_extension(player.player_unit, "unit_data_system") then
                local unit_data_extension = ScriptUnit_extension(player.player_unit, "unit_data_system")
                local character_state_component = unit_data_extension:read_component("character_state")
                if character_state_component and PlayerUnitStatus.is_hogtied(character_state_component) then
                    return true
                end
            end
        end
    end

    return false
end

local function auto_aim_priority_targets(player_unit)
    local player = Managers.player:local_player(1)
    if not player or not player.player_unit then
        has_target = false
        return
    end

    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    local first_person_component = unit_data_ext:read_component("first_person")
    local shooting_pos = first_person_component.position

    local dead_setting = cached_settings.disable_when_teammates_are_dead
    -- Migrate legacy boolean values from the old checkbox (true → "change_fov", false → "off").
    if dead_setting == true  then dead_setting = "change_fov" end
    if dead_setting == false then dead_setting = "off" end
    local dead_mode = dead_setting ~= "off" and are_teammates_dead()
    if dead_mode then
        if dead_setting == "disable" then
            has_target = false
            return
        end

        -- change_fov or change_fov_smooth
        local dead_fov_angle = cached_settings.teammates_dead_fov_angle or 0
        if dead_fov_angle == 0 then
            has_target = false
            return
        end

        local smooth_alpha = nil
        if dead_setting == "change_fov_smooth" then
            local smooth = cached_settings.teammates_dead_smooth or 0
            smooth_alpha = 0.05 ^ (smooth / 100)  -- exponential: 0→1.0 (snap), 100→0.05 (~14 frames at 60fps)
        end

        local camera_forward = Quaternion_forward(first_person_component.rotation)
        local dead_min_dot = math_cos(math_rad(dead_fov_angle * 0.5))

        -- Search for the first visible target within the narrowed FoV.
        local enemies, enemy_count = get_all_enemies()
        for i = 1, enemy_count do
            local enemy = enemies[i]
            if is_in_fov(enemy.unit, shooting_pos, camera_forward, dead_min_dot) then
                local zones = (enemy.breed_name and BREED_AIM_ZONES[enemy.breed_name]) or DEFAULT_AIM_ZONES
                local visible, resolved_zone = can_see_aim_target(enemy.unit, player, shooting_pos, zones)
                if visible then
                    has_target = true
                    look_at_aim_target(enemy.unit, resolved_zone, player, shooting_pos, player_unit, smooth_alpha)
                    return
                end
            end
        end

        has_target = false
        return
    end

    local camera_forward, min_dot
    local fov_check_enabled = cached_settings.enable_fov_check
    if fov_check_enabled then
        camera_forward = Quaternion_forward(first_person_component.rotation)
        min_dot = math_cos(math_rad(cached_settings.fov_angle * 0.5))
    end

    local enemies, enemy_count = get_all_enemies()
    for i = 1, enemy_count do
        local enemy = enemies[i]
        if not fov_check_enabled or is_in_fov(enemy.unit, shooting_pos, camera_forward, min_dot) then
            local zones = (enemy.breed_name and BREED_AIM_ZONES[enemy.breed_name]) or DEFAULT_AIM_ZONES

            local visible, resolved_zone = can_see_aim_target(enemy.unit, player, shooting_pos, zones)
            local has_lock = last_aim_unit == enemy.unit and last_aim_zone ~= nil

            if visible then
                -- Determine priority indices (lower index = higher priority in zones list).
                local new_idx = #zones + 1
                for k = 1, #zones do
                    if zones[k] == resolved_zone then new_idx = k; break end
                end
                local lock_idx = #zones + 1
                if has_lock then
                    for k = 1, #zones do
                        if zones[k] == last_aim_zone then lock_idx = k; break end
                    end
                end

                if has_lock and new_idx > lock_idx and last_aim_zone_blocked_frames < ZONE_GRACE_FRAMES then
                    -- Only a lower-priority fallback is visible; hold the locked zone
                    -- to avoid downgrading due to transient occlusion (e.g. blob dip).
                    last_aim_zone_blocked_frames = last_aim_zone_blocked_frames + 1
                    has_target = true
                    look_at_aim_target(enemy.unit, last_aim_zone, player, shooting_pos, player_unit)
                    return
                end
                -- Accept resolved_zone: same/higher-priority zone, grace expired, or no lock.
                last_aim_unit = enemy.unit
                last_aim_zone = resolved_zone
                last_aim_zone_blocked_frames = 0
                has_target = true
                look_at_aim_target(enemy.unit, resolved_zone, player, shooting_pos, player_unit)
                return
            elseif has_lock and last_aim_zone_blocked_frames < ZONE_GRACE_FRAMES then
                -- Nothing visible at all; hold locked zone during grace.
                last_aim_zone_blocked_frames = last_aim_zone_blocked_frames + 1
                has_target = true
                look_at_aim_target(enemy.unit, last_aim_zone, player, shooting_pos, player_unit)
                return
            end
        end
    end

    last_aim_unit = nil
    last_aim_zone = nil
    last_aim_zone_blocked_frames = 0
    has_target = false
end

local function get_weapon_fire_mode(weapon_template, is_ads)
    if not weapon_template or not weapon_template.actions then
        return "full_auto"
    end

    local shoot_action
    if is_ads then
        shoot_action = weapon_template.actions.action_shoot_zoomed or
                       weapon_template.actions.action_zoom_shoot_charged or
                       weapon_template.actions.action_shoot_zoomed_start
    else
        shoot_action = weapon_template.actions.action_shoot_hip or
                       weapon_template.actions.action_shoot_hip_charged or
                       weapon_template.actions.action_shoot_hip_start
    end

    if not shoot_action then
        return "full_auto"
    end

    if shoot_action.kind == "charge_ammo" then
        return "charge"
    end

    local action_inputs = weapon_template.action_inputs
    if action_inputs then
        local input_check = is_ads and action_inputs.zoom_shoot or action_inputs.shoot_pressed
        if input_check and input_check.input_sequence then
            for _, input_seq in ipairs(input_check.input_sequence) do
                if input_seq.input and (input_seq.input == "action_one_pressed" or input_seq.input:find("_pressed")) then
                    return "semi_auto"
                end
            end
        end
    end

    return "full_auto"
end

local function get_current_weapon_info()
    local player = Managers.player:local_player_safe(1)
    if not player or not player.player_unit then
        return nil, "full_auto", false
    end

    local unit_data_ext = ScriptUnit_extension(player.player_unit, "unit_data_system")
    if not unit_data_ext then
        return nil, "full_auto", false
    end

    local weapon_action_component = unit_data_ext:read_component("weapon_action")
    if not weapon_action_component then
        return nil, "full_auto", false
    end

    local alternate_fire_component = unit_data_ext:read_component("alternate_fire")
    local is_ads = alternate_fire_component and alternate_fire_component.is_active or false

    local weapon_template = WeaponTemplate.current_weapon_template(weapon_action_component)

    if not weapon_template then
        return nil, "full_auto", is_ads
    end

    return weapon_template, get_weapon_fire_mode(weapon_template, is_ads), is_ads
end

-- slot_secondary is the main weapon (ranged), slot_primary is the melee weapon.
-- _cached_wielded_slot is reset to `false` (sentinel) at the top of each fixed_update
-- so the first call in a frame (typically from _get) re-fetches and caches the result.
-- All subsequent calls within the same frame return immediately.
local _cached_wielded_slot = false  -- false = needs refresh; nil or string = cached value

local function get_wielded_slot()
    if _cached_wielded_slot ~= false then return _cached_wielded_slot end
    local player = Managers.player:local_player_safe(1)
    if not player or not player.player_unit then
        _cached_wielded_slot = nil
        return nil
    end
    local unit_data_ext = ScriptUnit_extension(player.player_unit, "unit_data_system")
    if not unit_data_ext then
        _cached_wielded_slot = nil
        return nil
    end
    local inventory_component = unit_data_ext:read_component("inventory")
    _cached_wielded_slot = inventory_component and inventory_component.wielded_slot
    return _cached_wielded_slot
end

local function is_main_weapon_equipped()
    return get_wielded_slot() == "slot_secondary"
end

local function is_melee_weapon_equipped()
    return get_wielded_slot() == "slot_primary"
end

local function is_reticle_on_enemy()
    local player = Managers.player:local_player(1)
    if not player or not player.player_unit then
        return false
    end

    local use_raycast = get_active_profile_behaviors().triggerbot_use_raycast

    local player_unit = player.player_unit
    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    local first_person_component = unit_data_ext:read_component("first_person")
    local shooting_pos = first_person_component.position

    local max_distance = 150
    local action_component = unit_data_ext:read_component("weapon_action")
    if action_component then
        local weapon_template = WeaponTemplate.current_weapon_template(action_component)
        if weapon_template and weapon_template.hit_scan_template then
            max_distance = weapon_template.hit_scan_template.range or max_distance
        end
    end

    -- fp_component.rotation = raw_orientation + camera_recoil (built by player_unit_first_person_extension).
    -- For most weapons camera_recoil_pct = 1 so weapon_recoil = 0, giving:
    --   bullet direction = fp_component.rotation + sway  (action_shoot.lua line 435-436)
    --   visual crosshair = fp_component.rotation + sway  (same)
    -- Raycasting from fp_component.rotation + sway is therefore the correct source of truth.
    -- Stripping camera_recoil first was wrong: during smooth aimbot transitions the pre-recoil
    -- raw orientation can point near the enemy even while the visual crosshair is way above it.
    local fp_fwd = Quaternion_forward(first_person_component.rotation)
    local yaw   = math_atan2(fp_fwd.y, fp_fwd.x) - HALF_PI
    local pitch = math_asin(fp_fwd.z)

    local compensate_spread = use_raycast == "on_with_spread" or use_raycast == "on_with_recoil_and_spread"

    -- Sway is always applied on top of fp_component.rotation before the bullet is cast.
    local sway = unit_data_ext:read_component("sway")
    yaw   = yaw   + sway.offset_x
    pitch = pitch + sway.offset_y

    local cos_p = math_cos(pitch)
    local direction = Vector3(-cos_p * math_sin(yaw), cos_p * math_cos(yaw), math_sin(pitch))

    if compensate_spread then
        local spread_offset = predict_spread_offset(player_unit)
        if spread_offset then
            local ray_rot = Quaternion.look(direction, Vector3.up())
            direction = Quaternion_forward(Quaternion.multiply(ray_rot, spread_offset))
        end
    end

    local physics_world = World_physics_world(Application_main_world())
    local hits = PhysicsWorld_raycast(physics_world, shooting_pos, direction, max_distance,
        "all", "collision_filter", "filter_player_character_shooting_raycast")
    if not hits or #hits == 0 then
        return false
    end

    local weakspot_only = get_active_profile_behaviors().triggerbot_weakspot_only

    -- If the player has a buff that makes every hit count as a weakspot, the
    -- weakspot_only gate is moot — fire at any valid enemy zone.
    local guaranteed_weakspot = false
    if weakspot_only then
        local buff_ext = ScriptUnit_has_extension(player_unit, "buff_system")
        local gw_kw = BuffSettings.keywords.guaranteed_weakspot_on_hit
        if buff_ext and gw_kw then
            guaranteed_weakspot = buff_ext:has_keyword(gw_kw)
        end
    end

    for i = 1, #hits do
        local hit = hits[i]
        local actor = hit and hit[4]
        local result = classify_los_hit(actor, player.player_unit, nil, nil)

        if result == "blocked" then
            return false
        elseif result == "hit" then
            local hit_unit = Actor_unit(actor)

            if not ScriptUnit_has_extension(hit_unit, "health_system") then
                return false
            end
            local health_ext = ScriptUnit_extension(hit_unit, "health_system")
            if not health_ext:is_alive() then
                return false
            end

            local breed = Breed.unit_breed_or_nil(hit_unit)
            if not breed or Breed.is_player(breed) then
                return false
            end
            if not is_valid_enemy_unit(hit_unit, breed) then
                return false
            end

            local zone_name = HitZone.get_name(hit_unit, actor)

            if debug_vars.breed_aim_zones then
                local wt2 = breed.hit_zone_weakspot_types
                local ws_type2 = wt2 and wt2[zone_name]
                local has_custom_zones = BREED_AIM_ZONES[breed.name] ~= nil
                mod:info("[breed_aim_zones] hit: breed=%s zone=%s ws_type=%s weakspot_only=%s guaranteed_ws=%s has_breed_aim_zones=%s",
                    tostring(breed.name), tostring(zone_name), tostring(ws_type2),
                    tostring(weakspot_only), tostring(guaranteed_weakspot), tostring(has_custom_zones))
            end

            local aim_zones = BREED_AIM_ZONES[breed.name]
            if weakspot_only and not guaranteed_weakspot and not (aim_zones and aim_zones.ignore_weakspot) then
                -- Use the breed's own weakspot table (same logic as Weakspot.hit_weakspot).
                -- "shield" type doesn't count. Missing entry = not a weakspot.
                -- Breeds whose BREED_AIM_ZONES entry has ignore_weakspot=true skip this gate.
                local wt = breed.hit_zone_weakspot_types
                local ws_type = wt and wt[zone_name]
                if ws_type and ws_type ~= "shield" then
                    return true, hit_unit, zone_name
                end
                -- Non-weakspot zone on a valid enemy (e.g. body actor arrived before head
                -- actor in the sorted hit list). Continue iterating — the head/weakspot
                -- actor for this same unit may appear at the next index.
            else
                return true, hit_unit, zone_name
            end

        end
    end

    return false
end

mod.toggle_aim = function(is_pressed)
    aim_button_pressed = is_pressed
end

mod.toggle_triggerbot = function(is_pressed)
    triggerbot_pressed = is_pressed
end

mod.toggle_boss_lock = function(is_pressed)
    boss_lock_pressed = is_pressed
end


-- Auto guard state: true when a nearby enemy is executing a power attack
local auto_guard_blocking = false
-- Tracks whether the previous frame's weapon action was a windup so the
-- immediately-following sweep (heavy swing) is also guard-suppressed.
local _prev_action_was_windup = false
-- True when an enemy is within the player's weapon reach
local melee_enemy_in_range = false
-- Melee auto-attack pulse: simulate press→release so the game sees a rising edge each cycle
local melee_press_last_t = 0
-- Equip-delay: suppress attacks briefly after drawing melee to avoid misfiring during wield anim.
local melee_last_equip_t    = -math.huge
local _last_melee_equipped  = false
local MELEE_EQUIP_DELAY     = 0.55  -- matches ogryn_pickaxe action_wield total_time
-- Cached each frame: true when the wielded melee weapon is an Ogryn pickaxe.
local melee_is_pickaxe      = false
local MELEE_PRESS_CYCLE    = 0.35  -- seconds between press pulses
local MELEE_PRESS_DURATION = 0.05  -- seconds to hold the press true

local DEFAULT_MELEE_REACH = 2.5  -- matches bot DEFAULT_MAXIMAL_MELEE_RANGE
local DEFAULT_ENEMY_RADIUS = 0.5 -- matches bot DEFAULT_ENEMY_HITBOX_RADIUS_APPROXIMATION
local VOID_SHIELD_REACH_BONUS = 1.5
-- Enemies must be within this dot-product of the camera forward to count as
-- "in range" for auto-attack.  0.0 = front hemisphere (180° total cone).
local MELEE_FOV_DOT = 0.0

-- Heavy attack timing constants.
-- HEAVY_SWING_BUFFER: safety fallback for phase-1 (held too long without entering
--   a windup) and phase-2 (swing animation not yet reported by start_t change).
local HEAVY_SWING_BUFFER    = 0.6   -- seconds

-- Breeds whose boss void-shield determines the melee attack type: light when the
-- shield is up (chip away at it), heavy when the shield is down (punish the opening).
local VOID_SHIELD_BREEDS = {
    cultist_captain           = true, -- Admonition Champion
    renegade_captain          = true, -- Scab Captain
    renegade_twin_captain     = true, -- Rodin Karnak
    renegade_twin_captain_two = true, -- Rinda Karnak
}

-- Heavy attack state machine: 0 = idle, 1 = charging (holding), 2 = recovering (released)
local melee_heavy_phase       = 0
local melee_heavy_start_t     = 0
local melee_windup_detected_t = 0  -- wall-clock time when we first saw kind=="windup" in phase 1
-- Set by check_enemy_in_melee_range to the closest valid target in range.
local melee_target_unit        = nil
local melee_target_needs_heavy = false  -- true when target is boss/elite/special
local melee_target_needs_thrust = false -- true when target warrants waiting for full thrust stacks + activation


-- Returns true when the equipped melee weapon has a power-activation weapon special
-- (e.g. thunder hammer, power sword) that must fire before a heavy attack.
-- Checks both that the weapon has a weapon_extra_action input binding AND that one of
-- its actions has an activation kind; this avoids false-positives on push/utility specials.
local function weapon_has_power_special(weapon_template)
    if not weapon_template or not weapon_template.actions then return false end
    for _, action in pairs(weapon_template.actions) do
        local k = action.kind
        if k == "activate_weapon" or k == "activatable_weapon_push" or k == "activate_special" then
            return true
        end
    end
    return false
end

-- Returns the raw InputService input name used to trigger the activation action
-- (e.g. "weapon_extra_pressed").  Resolves through two layers:
--   1. Find the action_inputs table key for the activate action (e.g. "weapon_extra_action").
--   2. Read action_inputs[key].input_sequence[1].input for the raw input name that
--      InputService._get is actually called with.
local function get_power_special_input_key(weapon_template)
    if not weapon_template or not weapon_template.actions then return "weapon_extra_pressed" end

    -- Layer 1: find the action_inputs key for the activation action.
    local action_input_key = nil
    for _, action in pairs(weapon_template.actions) do
        local k = action.kind
        if k == "activate_weapon" or k == "activatable_weapon_push" or k == "activate_special" then
            if action.input_entry then action_input_key = action.input_entry end
            break
        end
    end
    if not action_input_key and weapon_template.action_inputs then
        if weapon_template.action_inputs.weapon_extra_action then
            action_input_key = "weapon_extra_action"
        else
            for key in pairs(weapon_template.action_inputs) do
                if key:find("extra", 1, true) or key:find("activate", 1, true) then
                    action_input_key = key
                    break
                end
            end
        end
    end

    -- Layer 2: resolve the action_inputs entry to the raw input name.
    if action_input_key and weapon_template.action_inputs then
        local ai = weapon_template.action_inputs[action_input_key]
        local seq = ai and ai.input_sequence
        if seq and seq[1] and seq[1].input then
            return seq[1].input
        end
    end

    return "weapon_extra_pressed"
end

-- Returns true when the wielded weapon's special_active flag is set, meaning the
-- thunder hammer (or power sword) is currently powered up and ready to deliver
-- an energised strike.  Reads the inventory slot component directly so the
-- check is always in sync with what the game engine reports.
local function _is_weapon_special_active(player_unit)
    local unit_data_ext = ScriptUnit_has_extension(player_unit, "unit_data_system")
    if not unit_data_ext then return false end
    local inventory_comp = unit_data_ext:read_component("inventory")
    if not inventory_comp then return false end
    local wielded_slot = inventory_comp.wielded_slot
    if not wielded_slot or wielded_slot == "" then return false end
    local slot_comp = unit_data_ext:read_component(wielded_slot)
    return slot_comp ~= nil and slot_comp.special_active == true
end

-- Activation phase: true while waiting for the weapon-special animation to complete.
local melee_activating         = false
local melee_activate_start_t   = 0
local melee_activate_input_key = "weapon_extra_action"

local function get_melee_reach(player_unit)
    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    if not unit_data_ext then return DEFAULT_MELEE_REACH end
    local weapon_action_component = unit_data_ext:read_component("weapon_action")
    if not weapon_action_component then return DEFAULT_MELEE_REACH end
    local weapon_template = WeaponTemplate.current_weapon_template(weapon_action_component)
    if not weapon_template then return DEFAULT_MELEE_REACH end
    -- weapon_box[3] is the OBB z-half-extent used for sweep collision geometry, not
    -- the reach from player to target. The bot reads attack_meta_data.max_range instead
    -- (bt_bot_melee_action.lua:_calculate_melee_range). Player melee weapons never define
    -- attack_meta_data, so they always fall through to DEFAULT_MELEE_REACH (2.5 m),
    -- matching DEFAULT_MAXIMAL_MELEE_RANGE in bt_bot_melee_action.lua.
    local attack_meta_data = weapon_template.attack_meta_data
    if attack_meta_data then
        local light = attack_meta_data.light_attack
        if light and light.max_range then
            return light.max_range
        end
    end
    return DEFAULT_MELEE_REACH
end

-- Returns the commit_time
-- before the game registers a heavy_attack input (action_input_parser.lua evaluates
-- element.duration as the required hold time; when elapsed while holding,
-- element_completed = true and the sequence advances to the release step).

-- Returns true when the captain-class void shield is active on unit.
-- The void shield is implemented as the captain's toughness (toughness_armor_type
-- = void_shield), which is what the HUD shield bar reads.  Shield is up as long
-- as toughness_percent > 0; at 0 it has been destroyed.
local function is_void_shield_active(unit)
    local toughness_ext = ScriptUnit_has_extension(unit, "toughness_system")
    return toughness_ext ~= nil and toughness_ext:current_toughness_percent() > 0
end

-- Estimates damage per swing for light (want_heavy=false) or heavy (want_heavy=true)
-- attacks against target_unit using the current melee weapon's damage profile and
-- the target's armor type. Returns nil when the required data is unavailable.
local function _estimate_melee_damage(player_unit, target_unit, want_heavy)
    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    if not unit_data_ext then return nil end
    local weapon_action_comp = unit_data_ext:read_component("weapon_action")
    if not weapon_action_comp then return nil end
    local weapon_template = WeaponTemplate.current_weapon_template(weapon_action_comp)
    if not weapon_template or not weapon_template.actions then return nil end

    local target_strength = want_heavy and melee_attack_strengths.heavy or melee_attack_strengths.light
    local damage_profile = nil
    local action_power_level = nil

    for _, action in pairs(weapon_template.actions) do
        if action.kind == "sweep" then
            local dp = action.damage_profile
            if dp and dp.melee_attack_strength == target_strength then
                damage_profile = dp
                action_power_level = action.power_level
                break
            end
        end
    end

    if not damage_profile or not damage_profile.targets then return nil end

    local power_level = action_power_level or PowerLevelSettings.default_power_level
    local breed = Breed.unit_breed_or_nil(target_unit)
    local armor_type = (breed and breed.armor_type) or "unarmored"
    local target_settings = damage_profile.targets[1] or damage_profile.targets.default_target
    if not target_settings then return nil end

    local lerp_values = DamageProfile.lerp_values(damage_profile, player_unit)
    local base_dmg = DamageCalculation.base_ui_damage(
        damage_profile, target_settings, power_level, nil, nil, lerp_values)
    if not base_dmg or base_dmg <= 0 then return nil end

    local adm = DamageProfile.armor_damage_modifier(
        "attack", damage_profile, target_settings, lerp_values,
        armor_type, false, nil, false, 0)
    local result = base_dmg * adm
    return result > 0 and result or nil
end

-- Returns the current visual stack count of the Thrust (windup_increases_power)
-- perk child buff, or nil if the perk is not equipped on this weapon. Parent buff
-- presence is required so an absent child (0 stacks) is distinguished from the perk
-- being entirely missing. At 3 stacks the power modifier is maxed; the charge is
-- held until this point before releasing.
local function _get_windup_power_stacks(player_unit)
    local buff_ext = ScriptUnit_has_extension(player_unit, "buff_system")
    if not buff_ext then return nil end
    local buffs = buff_ext:buffs()
    local has_parent = false
    local stack_count = 0
    for i = 1, #buffs do
        local buff = buffs[i]
        local tmpl = buff:template()
        local name = tmpl and tmpl.name
        if name then
            if name:find("windup_increases_power_parent", 1, true) then
                has_parent = true
            elseif name:find("windup_increases_power_child", 1, true) then
                stack_count = buff:visual_stack_count()
            end
        end
    end
    return has_parent and stack_count or nil
end

local function is_priority_breed(breed)
    return breed and (
        VOID_SHIELD_BREEDS[breed.name] or
        breed.is_boss == true or
        (breed.tags ~= nil and (breed.tags.elite == true or breed.tags.special == true))
    )
end

local function check_enemy_in_melee_range(player_unit)
    melee_target_unit = nil
    local player_pos = POSITION_LOOKUP[player_unit]
    if not player_pos then return false, false end

    local reach = get_melee_reach(player_unit)
    -- Captains with an active void shield are fought at slightly longer range
    -- since the player needs to close distance to start stripping the shield.
    local void_shield_reach = reach + VOID_SHIELD_REACH_BONUS

    -- Get camera forward once for the FOV check below.
    local unit_data_ext = ScriptUnit_extension(player_unit, "unit_data_system")
    local forward = unit_data_ext and
        Quaternion_forward(unit_data_ext:read_component("first_person").rotation)

    local entities = get_minion_entities()
    if not entities then return false, false end

    -- Track the closest valid enemy and count regular (non-priority) enemies in range.
    -- Priority = boss / elite / special / void-shield captain.
    local best_unit       = nil
    local best_dist_sq    = math.huge
    local best_breed      = nil
    local regular_in_range = 0  -- count of non-priority enemies in melee range

    for unit, _ in pairs(entities) do
        local health_ext = ScriptUnit_has_extension(unit, "health_system")
        if not (health_ext and health_ext:is_alive()) then goto continue_range end

        local enemy_pos = POSITION_LOOKUP[unit]
        if not enemy_pos then goto continue_range end

        local enemy_data_ext = ScriptUnit_has_extension(unit, "unit_data_system")
        local enemy_radius = DEFAULT_ENEMY_RADIUS
        local breed = enemy_data_ext and enemy_data_ext:breed()
        if breed then
            enemy_radius = breed.bot_hitbox_radius_approximation or DEFAULT_ENEMY_RADIUS
        end

        local diff = enemy_pos - player_pos
        local dist_sq = Vector3_dot(diff, diff)
        local effective_reach = (breed and VOID_SHIELD_BREEDS[breed.name]) and void_shield_reach or reach
        local range_threshold = effective_reach + enemy_radius
        if dist_sq <= range_threshold * range_threshold then
            -- Reject enemies outside the front hemisphere so we don't swing at
            -- things directly behind the player.
            if forward and Vector3_dot(forward, Vector3_normalize(diff)) >= MELEE_FOV_DOT then
                if not is_priority_breed(breed) then
                    regular_in_range = regular_in_range + 1
                end
                if dist_sq < best_dist_sq then
                    best_dist_sq = dist_sq
                    best_unit    = unit
                    best_breed   = breed
                end
            end
        end

        ::continue_range::
    end

    if best_unit then
        melee_target_unit = best_unit
        local needs_heavy  = false
        local needs_thrust = false
        if best_breed then
            if VOID_SHIELD_BREEDS[best_breed.name] then
                -- Light while shield is up (faster DPS in practice despite lower per-hit modifier).
                -- Switch to heavy + activation + thrust once the shield breaks.
                local shield_up = is_void_shield_active(best_unit)
                needs_heavy  = not shield_up
                needs_thrust = not shield_up
            elseif is_priority_breed(best_breed) then
                -- Priority target: full heavy + activation + thrust stacks.
                needs_heavy  = true
                needs_thrust = true
            end
            -- Regular enemies: light by default; basic heavy cleave if 3+ are in range,
            -- but only if a single light attack can't already kill the target (a one-shot
            -- light is faster than any windup, so never charge-up just to kill a fodder
            -- enemy that would die to a light hit anyway).
            -- No thrust wait and no activation in either case.
            if not needs_heavy and regular_in_range >= 3 then
                local hp_ext2 = ScriptUnit_has_extension(best_unit, "health_system")
                local hp2 = hp_ext2 and hp_ext2:current_health()
                if hp2 and hp2 > 0 then
                    local light2 = _estimate_melee_damage(player_unit, best_unit, false)
                    if light2 and light2 < hp2 then
                        needs_heavy = true
                    end
                    -- If estimation failed (nil) or light can 1-shot, stay with light.
                else
                    needs_heavy = true
                end
                -- needs_thrust stays false: release as soon as commit time elapses
            end
        end
        melee_target_needs_thrust = needs_thrust
        local tag_needs_heavy = needs_heavy
        -- Damage-based refinement: only for priority targets (boss/elite/special).
        -- Regular enemies always get light (or horde cleave), never upgraded by math.
        local dbg_hp, dbg_light, dbg_heavy
        if is_priority_breed(best_breed) and not VOID_SHIELD_BREEDS[best_breed.name] then
            local hp_ext = ScriptUnit_has_extension(best_unit, "health_system")
            local hp = hp_ext and hp_ext:current_health()
            dbg_hp = hp
            if hp and hp > 0 then
                local light_dmg = _estimate_melee_damage(player_unit, best_unit, false)
                dbg_light = light_dmg
                if light_dmg and light_dmg >= hp then
                    -- Light can 1-shot the target; no charge needed regardless of tags.
                    needs_heavy  = false
                    needs_thrust = false
                    melee_target_needs_thrust = false
                elseif not tag_needs_heavy and light_dmg and light_dmg > 0 then
                    -- Multi-shot comparison only for non-priority targets (e.g. horde cleave check).
                    -- Priority targets (elite/boss) always get heavy once they survive a light one-shot.
                    local heavy_dmg = _estimate_melee_damage(player_unit, best_unit, true)
                    dbg_heavy = heavy_dmg
                    if heavy_dmg and heavy_dmg > 0 then
                        local light_shots = math.ceil(hp / light_dmg)
                        local heavy_shots = math.ceil(hp / heavy_dmg)
                        if heavy_shots < light_shots then
                            needs_heavy = true
                        elseif heavy_shots > light_shots then
                            needs_heavy  = false
                            needs_thrust = false
                            melee_target_needs_thrust = false
                        end
                    end
                end
            end
        end
        if debug_vars.melee and best_unit ~= debug_vars.melee_last_unit then
            debug_vars.melee_last_unit = best_unit
            local bn  = best_breed and best_breed.name or "nil"
            local tgs = best_breed and best_breed.tags
            mod:info("[melee_dbg] target=%s is_boss=%s elite=%s special=%s tag_heavy=%s final_heavy=%s",
                bn, tostring(best_breed and best_breed.is_boss),
                tostring(tgs and tgs.elite), tostring(tgs and tgs.special),
                tostring(tag_needs_heavy), tostring(needs_heavy))
            mod:info("[melee_dbg] hp=%s light_dmg=%s heavy_dmg=%s",
                tostring(dbg_hp), tostring(dbg_light), tostring(dbg_heavy))
            -- Dump every weapon action: kind + damage_profile.melee_attack_strength
            local wac2 = unit_data_ext:read_component("weapon_action")
            local wt2  = wac2 and WeaponTemplate.current_weapon_template(wac2)
            if wt2 and wt2.actions then
                mod:info("[melee_dbg] enum: heavy=%s light=%s",
                    tostring(melee_attack_strengths.heavy), tostring(melee_attack_strengths.light))
                for aname, action in pairs(wt2.actions) do
                    if action.kind then
                        local dp = action.damage_profile
                        mod:info("[melee_dbg]   [%s] kind=%s dp_strength=%s input_entry=%s",
                            tostring(aname), tostring(action.kind),
                            dp and tostring(dp.melee_attack_strength) or "nil",
                            tostring(action.input_entry))
                    end
                end
                    mod:info("[melee_dbg] has_power_special=%s raw_input_key=%s",
                        tostring(weapon_has_power_special(wt2)),
                        tostring(get_power_special_input_key(wt2)))
                else
                    mod:info("[melee_dbg] no weapon template found")
                end
            end
        return true, needs_heavy
    end
    debug_vars.melee_last_unit = nil
    return false, false
end

-- Per-unit animation attack window tracking.
local unit_attack_end_times   = {}  -- unit -> expiry time (main clock seconds)
local unit_attack_is_heavy    = {}  -- unit -> true when event was a moving/running swing
local unit_attack_start_times = {}  -- unit -> time the anim event first fired
-- Per-unit Layer A trail: wall-clock time when the damage window closes for this unit.
-- Set once when tth first crosses 0; now + GUARD_TRAIL_TIME + time_to_hit is constant
-- because now and anim_t advance at the same rate.  Lets the guard hold after the
-- animation exits the attack state but before the server damage packet arrives.
local unit_layer_a_trail = {}
-- Fallback guard window for breeds/events not found in BreedActions timing tables.
local ATTACK_ANIM_WINDOW = 3.0
-- Guard window around the hit frame: raise this many seconds before the hit,
-- drop this many seconds after (Layer A stale threshold).
local GUARD_EARLY_START = 0.10
local GUARD_TRAIL_TIME  = 0.10
-- How long (wall-clock seconds) to hold the guard via Layer T after the animation
-- hit frame has passed.  Separate from GUARD_TRAIL_TIME because animation speed
-- can differ from 1× (e.g. running attacks play at ~1.5×), so anim-time tth is
-- not directly comparable to wall-clock now.  Set from hit frame wall-clock time.
local LAYER_T_DURATION = 0.35

-- unit -> breed name; breed name -> {event_index -> event_name}
local _unit_breed_name        = {}
local _breed_attack_idx_cache = {}

-- Per-breed attack-state signatures: maps state node index → true.
-- Pre-seeded for known breeds; new indices learned at runtime via _on_attack_anim_event.
local _breed_attack_state_sigs = {}

-- Charge-state indices for chaos_newly_infected; states 103/108 excluded (fire during
-- locomotion transitions → false positives).  attack_run_01 learned at runtime.
_breed_attack_state_sigs["chaos_newly_infected"] = { [93]=true, [94]=true, [98]=true }

-- breed_name -> event_name -> seconds from anim_event fire to first hit frame.
-- Derived at startup from BreedActions tables; covers every breed and every attack event.
-- attack_anim_damage_timings: value is a scalar or {t1, t2, ...} (multi-hit); take [1].
-- attack_sweep_damage_timings: value is {{start,stop,...}, ...}; start = [1][1].
--   Simple sweep format {start, stop} is also handled: [1] is already a scalar there.
local _breed_event_hit_times = {}

-- breed_name -> state_index -> { hit_dt, is_heavy }
-- Populated at runtime when sigs are learned in _on_attack_anim_event.
-- Used by Layer A to reject re-arms when anim_t has already passed the hit frame.
local _breed_state_info = {}
do
    for breed_name, actions in pairs(BreedActions) do
        local hit_times = {}
        for _, action in pairs(actions) do
            if type(action) ~= "table" then goto next_action end
            local dt = action.attack_anim_damage_timings
            if dt then
                for ev, v in pairs(dt) do
                    hit_times[ev] = type(v) == "table" and v[1] or v
                end
            end
            local st = action.attack_sweep_damage_timings
            if st then
                for ev, v in pairs(st) do
                    local first = v[1]
                    hit_times[ev] = type(first) == "table" and first[1] or first
                end
            end
            ::next_action::
        end
        if next(hit_times) then
            _breed_event_hit_times[breed_name] = hit_times
        end
    end
end

-- Pre-allocated scratch tables for GC-efficient per-frame state / time polling.
local _anim_state_scratch = {}
local _anim_time_scratch  = {}
-- Populated by check_power_attack_incoming each time it returns true; read by
-- fixed_update to enrich the GUARD UP log line.
local _guard_trigger_info = { breed = nil, state = nil, anim_t = 0, time_to_hit = nil, layer = "?" }

-- Parry-pulse state.
-- _guard_active_unit : the enemy unit whose window triggered the current guard cycle.
-- _guard_pulse_end_t : wall-clock time at which the release phase ends and the guard
--   re-raises.  While now < _guard_pulse_end_t, action_two_hold is forced false.
-- _guard_pulsed      : true once the pulse has fired for this guard cycle; prevents
--   strobing the input on every fixed_update frame while the window is held.
-- GUARD_PULSE_DURATION : how long (seconds) to release the block between parries.
--   2 frames at 60 Hz = 0.033 s.  Must be shorter than the remaining tth at pulse time.
local _guard_active_unit   = nil
local _guard_pulse_end_t   = 0
local _guard_pulsed        = false
local GUARD_PULSE_DURATION = 0.033

-- tth value at the moment the last GUARD UP was logged; carried into BLOCK_SUCCESS
-- so we can correlate tth with perfect/normal block outcome (Idea 4).
local _last_guard_up_tth = nil

local function check_power_attack_incoming(player_unit)
    local player_pos = POSITION_LOOKUP[player_unit]
    if not player_pos then return false end

    -- When the player is dodging, Dodge.is_dodging() returns true for melee attacks
    -- and the game's reach/cone shrinkage causes the incoming attack to miss.
    -- Raising the guard is unnecessary and suppresses the counter-swing pulse.
    if Dodge.is_dodging(player_unit, "melee") then
        return false
    end

    local range = cached_settings.auto_guard_range or 4
    local range_sq = range * range
    local heavy_only = cached_settings.auto_guard_heavy_only
    local now = Managers.time:time("main") or 0

    local entities = get_minion_entities()
    if not entities then return false end

    for unit, _ in pairs(entities) do
        local health_ext = ScriptUnit_has_extension(unit, "health_system")
        if not (health_ext and health_ext:is_alive()) then goto continue_guard end

        local enemy_pos = POSITION_LOOKUP[unit]
        if not enemy_pos then goto continue_guard end

        local diff = enemy_pos - player_pos
        if Vector3_dot(diff, diff) > range_sq then goto continue_guard end

        -- Expire stale event-based windows.
        local end_t = unit_attack_end_times[unit]
        if end_t and now >= end_t then
            if debug_vars.guard then
                mod:info("[guard_dbg] EXPIRE layerB: breed=%s age=%.3f",
                    tostring(_unit_breed_name[unit]),
                    now - (unit_attack_start_times[unit] or now))
            end
            unit_attack_end_times[unit]   = nil
            unit_attack_is_heavy[unit]    = nil
            unit_attack_start_times[unit] = nil
            unit_layer_a_trail[unit]      = nil
            end_t = nil
        end

        local breed = _unit_breed_name[unit]

        -- Layer A: live state-machine polling.
        -- Active for as long as the unit is in a known attack-charge state.
        -- Self-terminating: returns false as soon as the unit leaves the state,
        -- so the guard drops naturally without relying on a timeout.
        local sigs = breed and _breed_attack_state_sigs[breed]
        if sigs then
            local s_tbl, s_n = Unit.animation_get_state(unit, _anim_state_scratch)
            if s_n and s_n > 0 and sigs[s_tbl[1]] then
                local t_tbl, t_n = Unit.animation_get_time(unit, _anim_time_scratch)
                local anim_t = (t_n and t_n > 0) and t_tbl[1] or 0
                local bsi = breed and _breed_state_info[breed]
                local state_info = bsi and bsi[s_tbl[1]]
                if state_info then
                    local time_to_hit = state_info.hit_dt - anim_t
                    if time_to_hit > GUARD_EARLY_START then
                        -- Hit is not yet imminent; leave the window open for attacking.
                        goto continue_guard
                    end
                    if time_to_hit < -GUARD_TRAIL_TIME then
                        if debug_vars.guard then
                            mod:info("[guard_dbg] SKIP stale layerA: breed=%s state=%d anim_t=%.3f hit_dt=%.3f",
                                tostring(breed), s_tbl[1], anim_t, state_info.hit_dt)
                        end
                        -- Unit is stale in Layer A but may still have an active trail
                        -- (unit stayed in sig state past the hit frame).  Check before
                        -- skipping so the goto doesn't bypass the Layer T block below.
                        local trail_end_stale = unit_layer_a_trail[unit]
                        if trail_end_stale then
                            if now < trail_end_stale then
                                if not heavy_only or unit_attack_is_heavy[unit] then
                                    if debug_vars.guard then
                                        _guard_trigger_info.breed       = breed
                                        _guard_trigger_info.state       = 0
                                        _guard_trigger_info.anim_t      = 0
                                        _guard_trigger_info.time_to_hit = trail_end_stale - now
                                        _guard_trigger_info.layer       = "T"
                                    end
                                    return true, unit
                                end
                            else
                                unit_layer_a_trail[unit] = nil
                            end
                        end
                        goto continue_guard
                    end
                end
                if not end_t then
                    unit_attack_start_times[unit] = now
                    unit_attack_end_times[unit]   = now + ATTACK_ANIM_WINDOW
                    unit_attack_is_heavy[unit]    = state_info and state_info.is_heavy or true
                    end_t = unit_attack_end_times[unit]
                    if debug_vars.guard then
                        mod:info("[guard_dbg] DETECT layerA: breed=%s state=%d anim_t=%.3f heavy=%s",
                            tostring(breed), s_tbl[1], anim_t, tostring(unit_attack_is_heavy[unit]))
                    end
                end
                if heavy_only and not unit_attack_is_heavy[unit] then
                    goto continue_guard
                end
                -- Record wall-clock expiry for Layer T.  Use now + LAYER_T_DURATION
                -- (not now + LAYER_T_DURATION + tth) because tth is in animation time
                -- and animation can play faster than 1× (e.g. running attacks ~1.5×),
                -- making the mixed-unit formula expire too early.
                if state_info and not unit_layer_a_trail[unit] then
                    if state_info.hit_dt - anim_t <= 0 then
                        unit_layer_a_trail[unit] = now + LAYER_T_DURATION
                    end
                end
                if debug_vars.guard then
                    _guard_trigger_info.breed      = breed
                    _guard_trigger_info.state      = s_tbl[1]
                    _guard_trigger_info.anim_t     = anim_t
                    _guard_trigger_info.time_to_hit = state_info and (state_info.hit_dt - anim_t) or nil
                    _guard_trigger_info.layer      = "A"
                end
                return true, unit
            end
        end

        -- Layer A trail: unit has left the attack state but its damage window has not
        -- yet elapsed.  Covers the ~25ms gap between animation-state exit and the
        -- server damage packet arriving.
        local trail_end = unit_layer_a_trail[unit]
        if trail_end then
            if now >= trail_end then
                unit_layer_a_trail[unit] = nil
            elseif not heavy_only or unit_attack_is_heavy[unit] then
                if debug_vars.guard then
                    _guard_trigger_info.breed       = breed
                    _guard_trigger_info.state       = 0
                    _guard_trigger_info.anim_t      = 0
                    _guard_trigger_info.time_to_hit = trail_end - now
                    _guard_trigger_info.layer       = "T"
                end
                return true, unit
            end
        end

        -- Layer B: event-timestamp fallback for breeds without state sigs.
        -- Holds guard for the full ATTACK_ANIM_WINDOW after the attack event fires,
        -- covering the entire damage window without relying on per-breed timing constants.
        if end_t and not sigs then
            if not heavy_only or unit_attack_is_heavy[unit] then
                if debug_vars.guard then
                    _guard_trigger_info.breed      = breed
                    _guard_trigger_info.state      = nil
                    _guard_trigger_info.anim_t     = 0
                    _guard_trigger_info.time_to_hit = nil
                    _guard_trigger_info.layer      = "B"
                end
                return true, unit
            end
        end

        ::continue_guard::
    end

    return false
end

-- Reentrance guard: set to true while _get_simulate is delegating to the original
-- _get_simulate (which internally calls self:_get). Without this guard the hooked
-- _get runs fire-gate logic twice per frame — once from the direct _get call and
-- once from the _get_simulate → original _get_simulate → hooked _get chain.
local _in_get_simulate_passthrough = false

local _get = function(func, self, action_name)
    if self.type ~= "Ingame" or _in_get_simulate_passthrough then
        return func(self, action_name)
    end

    local melee_equipped = is_melee_weapon_equipped()

    -- Standalone auto-guard (always-on, independent of keybind).
    -- Injects action_two_hold (the raw InputService input that the action_input_parser
    -- maps to the "block" action input via the weapon template's action_inputs table).
    -- Only applies when a melee weapon is equipped; ranged weapons use action_two_hold
    -- for ADS and must not have it forced true.
    -- During a parry pulse the input is forced false for GUARD_PULSE_DURATION so the
    -- game sees a fresh press on the next attacker and grants a perfect block.
    if cached_settings.enable_auto_guard and melee_equipped then
        if action_name == "action_two_hold" then
            local now_g = Managers.time:time("main") or 0
            if _guard_pulse_end_t > 0 and now_g < _guard_pulse_end_t then
                return false   -- release phase of parry pulse
            end
            if auto_guard_blocking then
                return true
            end
        end
    end

    if not cached_settings.enable_triggerbot then
        return func(self, action_name)
    end

    local keybind = cached_settings.triggerbot_keybind
    local keybind_active = not next(keybind) or triggerbot_pressed

    -- Melee auto-fight: keybind held + melee weapon equipped
    if keybind_active and melee_equipped then
        if auto_guard_blocking then
            -- Power attack incoming: inject action_two_hold (the raw input the
            -- action_input_parser maps to the "block" weapon action).
            -- Release during parry pulse so the game sees a fresh press per attacker.
            if action_name == "action_two_hold" then
                local now_g = Managers.time:time("main") or 0
                if _guard_pulse_end_t > 0 and now_g < _guard_pulse_end_t then
                    return false   -- release phase of parry pulse
                end
                return true
            end
        else
            -- Power-weapon activation: pulse weapon_extra_action for one press duration,
            -- then hold action_one_hold false until the animation window elapses.
            if melee_activating then
                if action_name == melee_activate_input_key then
                    -- Re-pulse the activation key every MELEE_PRESS_CYCLE until the
                    -- update loop observes special_active == true and clears melee_activating.
                    local elapsed = (Managers.time:time("main") or 0) - melee_activate_start_t
                    local cycle_pos = elapsed % MELEE_PRESS_CYCLE
                    return cycle_pos < MELEE_PRESS_DURATION
                end
                if action_name == "action_one_hold" then
                    return false
                end
            end
            if action_name == "action_one_hold" then
                if not melee_enemy_in_range and melee_heavy_phase == 0 then
                    return false
                end
                local now = Managers.time:time("main")
                -- Suppress all attacks during the wield animation to prevent the heavy
                -- windup from firing and looking like an unintended alt attack.
                if (now - melee_last_equip_t) < MELEE_EQUIP_DELAY then
                    return false
                end
                -- Once committed to a heavy charge, see it through even if the target
                -- briefly steps out of range (flinch/knockback during charge-up).
                if melee_heavy_phase == 1 then
                    return true
                elseif melee_heavy_phase == 2 then
                    return false
                end
                if melee_target_needs_heavy then
                    -- For power weapons: if not yet charged, start activation instead of heavy.
                    -- This is a safety net for when the input hook runs before the update loop
                    -- has a chance to set melee_activating (e.g. after phase 2 completes).
                    local _pu = Managers.player:local_player(1)
                    _pu = _pu and _pu.player_unit
                    if _pu then
                        local _udata2 = ScriptUnit_extension(_pu, "unit_data_system")
                        local _wac2   = _udata2 and _udata2:read_component("weapon_action")
                        local _wt2    = _wac2 and WeaponTemplate.current_weapon_template(_wac2)
                        if weapon_has_power_special(_wt2) and not _is_weapon_special_active(_pu) then
                            melee_activating         = true
                            melee_activate_start_t   = now
                            melee_activate_input_key = get_power_special_input_key(_wt2)
                            return false
                        end
                    end
                    -- Phase 0: start a new heavy charge.
                    melee_heavy_phase   = 1
                    melee_heavy_start_t = now
                    return true
                else
                    -- Light attack: pulse briefly.
                    local elapsed = now - melee_press_last_t
                    local inject
                    if elapsed >= MELEE_PRESS_CYCLE then
                        melee_press_last_t = now
                        inject = true
                        if debug_vars.melee then
                            local bn = melee_target_unit and Breed and Breed.unit_breed_or_nil(melee_target_unit)
                            bn = bn and bn.name or "nil"
                            local _pu_dbg = Managers.player:local_player(1)
                            _pu_dbg = _pu_dbg and _pu_dbg.player_unit
                            local _charged_dbg = _pu_dbg and _is_weapon_special_active(_pu_dbg)
                            mod:info("[melee_dbg] LIGHT fired: target=%s in_range=%s needs_heavy=%s needs_thrust=%s phase=%s activating=%s charged=%s",
                                bn,
                                tostring(melee_enemy_in_range),
                                tostring(melee_target_needs_heavy),
                                tostring(melee_target_needs_thrust),
                                tostring(melee_heavy_phase),
                                tostring(melee_activating),
                                tostring(_charged_dbg))
                        end
                    else
                        inject = elapsed < MELEE_PRESS_DURATION
                    end
                    return inject
                end
            end
        end
        return func(self, action_name)
    end

    -- Ranged triggerbot path: only intercept attack inputs
    if action_name ~= "action_one_hold" and action_name ~= "action_one_pressed" then
        return func(self, action_name)
    end

    if not keybind_active then
        return func(self, action_name)
    end

    if cached_settings.require_main_weapon and not is_main_weapon_equipped() then
        return func(self, action_name)
    end

    local active_behaviors = get_active_profile_behaviors()
    local reticle_unit, reticle_zone
    local can_fire
    if active_behaviors.triggerbot_use_raycast ~= "off" then
        local hit_ok
        hit_ok, reticle_unit, reticle_zone = is_reticle_on_enemy()
        can_fire = hit_ok
    else
        can_fire = has_target
    end
    if not can_fire then
        if debug_vars.triggerbot and has_target and action_name == "action_one_hold" then
            local _now = Managers.time:time("main") or 0
            if _now - debug_vars.tbot_last_miss_log >= 0.25 then
                debug_vars.tbot_last_miss_log = _now
                local _use_rc = active_behaviors.triggerbot_use_raycast
                mod:info("[tbot_dbg] fa_miss: has_target=true raycast=%s reticle_unit=%s",
                    tostring(_use_rc or "off"), tostring(reticle_unit ~= nil))
            end
        end
        return func(self, action_name)
    end

    -- Surgical crit-wait: suppress fire if waiting for more stacks will crit
    if active_behaviors.wait_for_crits then
        local player_unit = Managers.player:local_player(1)
        player_unit = player_unit and player_unit.player_unit
        if player_unit then
            local crit_action = predict_crit_wait(player_unit)
            if crit_action == "wait" then
                return false
            end
        end
    end

    -- Opening Salvo wait: suppress fire until magazine is fresh (num_shots == 0)
    if active_behaviors.wait_for_opening_salvo then
        local player_unit_os = Managers.player:local_player(1)
        player_unit_os = player_unit_os and player_unit_os.player_unit
        if player_unit_os then
            if not is_opening_salvo_ready(player_unit_os) then
                return false
            end
        end
    end

    -- Efficiency perk: suppress while cooldown is active OR within EFFICIENCY_FIRE_COOLDOWN
    -- seconds of the last shot.  The post-fire window covers server RTT so the keyword
    -- update (which is server-authoritative) arrives before we look again.
    local player_unit_eff = Managers.player:local_player(1)
    player_unit_eff = player_unit_eff and player_unit_eff.player_unit
    local efficiency_equipped = false
    if player_unit_eff then
        local buff_ext_eff = ScriptUnit_extension(player_unit_eff, "buff_system")
        if buff_ext_eff and buff_ext_eff:has_buff_using_buff_template(EFFICIENCY_BUFF_NAME) then
            efficiency_equipped = true
            local eff_interval, now_eff = get_fire_interval()
            local eff_cooldown = math.max(EFFICIENCY_FIRE_COOLDOWN, eff_interval)
            if (now_eff - last_efficiency_fire_time) < eff_cooldown then
                return false
            end
            if not buff_ext_eff:has_keyword(EFFICIENCY_KEYWORD) then
                return false
            end
        end
    end

    local weapon_template, fire_mode, is_ads = get_current_weapon_info()
    if action_name == "action_one_hold" and (fire_mode == "charge" or fire_mode == "full_auto") then
        -- Charge weapons (e.g. Helborne Lasgun) accumulate charge_level up to max_charge, then
        -- require a button release to fire.  ActionChargeAmmo.running_action_state only signals
        -- "fully_charged" after charge_extra_hold_time (2.5 s) past completion, so both hip-fire
        -- and ADS paths suffer a 2.5 s dead zone if we just hold action_one_hold.  Instead read
        -- the networked charge level directly and release for one frame the moment it peaks.
        -- The release edge causes the action_input_parser to generate shoot_release_charged (hip)
        -- or zoom_shoot_release_charged (ADS), firing immediately without waiting for the timeout.
        -- NOTE: get_weapon_fire_mode resolves action_shoot_hip_charged / action_zoom_shoot_charged
        -- (kind=shoot_hit_scan) before the charge_ammo start actions, so fire_mode here is
        -- "full_auto" not "charge"; guard on the start action's kind directly instead.
        if player_unit_eff then
            local start_key = is_ads and "action_shoot_zoomed_start" or "action_shoot_hip_start"
            local start_action = weapon_template and weapon_template.actions and weapon_template.actions[start_key]
            if start_action and start_action.kind == "charge_ammo" then
                local ud = ScriptUnit_extension(player_unit_eff, "unit_data_system")
                local charge_comp = ud and ud:read_component("action_module_charge")
                if charge_comp then
                    local max_c = charge_comp.max_charge
                    local clvl  = charge_comp.charge_level
                    -- Early-fire: release as soon as estimated damage at current charge
                    -- level would kill the target, rather than always charging to max.
                    local should_release = max_c > 0 and clvl >= max_c
                    local early_dmg_dbg = -1
                    if not should_release and clvl > 0 and last_aim_unit then
                        local hp_ext_c = ScriptUnit_has_extension(last_aim_unit, "health_system")
                        local server_hp_c = hp_ext_c and hp_ext_c:current_health() or 0
                        if server_hp_c > 0 then
                            local early_dmg = _estimate_shot_damage(player_unit_eff, last_aim_unit, true, clvl)
                            early_dmg_dbg = early_dmg or -1
                            if early_dmg and early_dmg >= server_hp_c then
                                should_release = true
                            end
                        end
                    end
                    if debug_vars.charge then
                        local _now_dbg = Managers.time and Managers.time:time("main") or 0
                        mod:info("[charge_dbg] t=%.3f ads=%s charge=%.3f max=%.3f dmg=%.1f -> %s",
                            _now_dbg, tostring(is_ads), clvl, max_c,
                            early_dmg_dbg, should_release and "RELEASE" or "hold")
                    end
                    if should_release then
                        return false  -- release edge → fires immediately
                    end
                elseif debug_vars.charge then
                    local _now_dbg = Managers.time and Managers.time:time("main") or 0
                    mod:info("[charge_dbg] t=%.3f charge_comp nil", _now_dbg)
                end
            elseif debug_vars.charge then
                local _now_dbg = Managers.time and Managers.time:time("main") or 0
                local start_action2 = weapon_template and weapon_template.actions and weapon_template.actions[
                    is_ads and "action_shoot_zoomed_start" or "action_shoot_hip_start"]
                mod:info("[charge_dbg] t=%.3f start_action check failed: key=%s exists=%s kind=%s",
                    _now_dbg, is_ads and "action_shoot_zoomed_start" or "action_shoot_hip_start",
                    tostring(start_action2 ~= nil),
                    tostring(start_action2 and start_action2.kind))
            end
        elseif debug_vars.charge then
            local _now_dbg = Managers.time and Managers.time:time("main") or 0
            mod:info("[charge_dbg] t=%.3f player_unit_eff nil", _now_dbg)
        end
        -- Don't fire at a target the server has already confirmed dead.
        local kill_gate_unit_fa = (active_behaviors.triggerbot_use_raycast ~= "off" and reticle_unit) or last_aim_unit
        if kill_gate_unit_fa then
            local hp_ext = ScriptUnit_has_extension(kill_gate_unit_fa, "health_system")
            if not hp_ext or hp_ext:current_health() <= 0 then
                return false
            end
        end
        if efficiency_equipped then
            last_efficiency_fire_time = Managers.time:time("main") or 0
        end
        if debug_vars.triggerbot then
            local _now_fa = Managers.time and Managers.time:time("main") or 0
            if _now_fa - debug_vars.tbot_last_miss_log >= 0.5 then
                debug_vars.tbot_last_miss_log = _now_fa
                mod:info("[tbot_dbg] fire full_auto: t=%.3f has_target=%s reticle_unit=%s",
                    _now_fa, tostring(has_target), tostring(reticle_unit ~= nil))
            end
        end
        if debug_vars.surgical then
            debug_vars.surgical_fired_unit = last_aim_unit
            debug_vars.surgical_fired_time = Managers.time and Managers.time:time("main")
        end
        return true
    end

    if action_name == "action_one_pressed" and fire_mode == "semi_auto" then
        local fire_interval, current_time = get_fire_interval()
        if current_time - last_semi_auto_fire_time >= fire_interval then
            -- Don't fire at a target the server has already confirmed dead.
            local kill_gate_unit = (active_behaviors.triggerbot_use_raycast ~= "off" and reticle_unit) or last_aim_unit
            if kill_gate_unit then
                local hp_ext = ScriptUnit_has_extension(kill_gate_unit, "health_system")
                if not hp_ext or hp_ext:current_health() <= 0 then
                    return false
                end
            end
            last_semi_auto_fire_time = current_time
            if efficiency_equipped then
                last_efficiency_fire_time = current_time
            end
            if debug_vars.triggerbot then
                mod:info("[tbot_dbg] fire semi_auto: interval=%.3f", fire_interval)
            end
            if debug_vars.surgical then
                debug_vars.surgical_fired_unit = last_aim_unit
                debug_vars.surgical_fired_time = Managers.time and Managers.time:time("main")
            end
            return true
        end
        return false
    end

    return func(self, action_name)
end

local function _on_attack_anim_event(unit, event_name, now)
    -- Reset per-attack; combo attacks each get a fresh window.
    -- Duplicate fires (host + listen-server same frame) use the same `now`, so safe.
    unit_attack_start_times[unit] = now
    unit_attack_is_heavy[unit]  = event_name:sub(1, 12) == "attack_move_" or event_name:sub(1, 11) == "attack_run_"

    local breed = _unit_breed_name[unit]

    -- Set end_t: use the precise hit frame from BreedActions when available,
    -- otherwise fall back to the generic window that covers any breed.
    -- Must reach at least now + hit_dt + LAYER_T_DURATION so the EXPIRE block
    -- does not clear unit_layer_a_trail before Layer T finishes.
    local hit_dt = breed and _breed_event_hit_times[breed] and _breed_event_hit_times[breed][event_name]
    unit_attack_end_times[unit] = now + (hit_dt and (hit_dt + LAYER_T_DURATION) or ATTACK_ANIM_WINDOW)

    if not breed then return end

    -- Snapshot the charge-state index; add to the sig table if unseen.
    local s_tbl, s_n = Unit.animation_get_state(unit, _anim_state_scratch)
    local cur_state = s_n and s_n > 0 and s_tbl[1]
    local sigs = _breed_attack_state_sigs[breed]

    if cur_state then
        if not sigs then sigs = {} ; _breed_attack_state_sigs[breed] = sigs end
        if not sigs[cur_state] then
            sigs[cur_state] = true
            mod:info("[gambits][guard] new state sig learned: breed=%s event=%s heavy=%s state=%d",
                breed, event_name, tostring(unit_attack_is_heavy[unit]), cur_state)
        end
        -- Store hit timing per (breed, state) so Layer A can reject stale re-arms.
        if hit_dt then
            local bsi = _breed_state_info[breed]
            if not bsi then bsi = {} ; _breed_state_info[breed] = bsi end
            if not bsi[cur_state] then
                bsi[cur_state] = { hit_dt = hit_dt, is_heavy = unit_attack_is_heavy[unit] }
            end
        end
    end

    if debug_vars.guard then
        local has_sigs = sigs ~= nil
        local t_tbl, t_n = Unit.animation_get_time(unit, _anim_time_scratch)
        local anim_t = (t_n and t_n > 0) and t_tbl[1] or -1
        local dist_str = "?"
        local enemy_pos = POSITION_LOOKUP[unit]
        if enemy_pos then
            local player = Managers.player:local_player(1)
            local player_pos = player and player.player_unit and POSITION_LOOKUP[player.player_unit]
            if player_pos then
                local d = enemy_pos - player_pos
                dist_str = string.format("%.1f", math.sqrt(Vector3_dot(d, d)))
            end
        end
        mod:info("[guard_dbg] EVENT: breed=%s event=%s heavy=%s state=%s anim_t=%.3f hit_dt=%s layer=%s dist=%s",
            breed, event_name, tostring(unit_attack_is_heavy[unit]),
            tostring(cur_state), anim_t,
            hit_dt and string.format("%.3f", hit_dt) or "?",
            has_sigs and "A" or "B", dist_str)
    end
end

-- Populate unit->breed map on spawn (runs on both server and client).
-- The attack-index cache is populated at runtime via the Unit.animation_event
-- intercept below (server/listen-server path) and rpc_minion_anim_event (client path).
-- Unit.index_by_animation_event does not exist in this engine version, so
-- spawn-time pre-population is not possible without firing live animation events.
mod:hook_safe("MinionAnimationExtension", "init", function(self, extension_init_context, unit, extension_init_data, ...)
    local breed = extension_init_data and extension_init_data.breed
    if not breed or not breed.name then return end
    _unit_breed_name[unit] = breed.name
    if not _breed_attack_idx_cache[breed.name] then
        _breed_attack_idx_cache[breed.name] = {}
    end
end)

-- SERVER / HOST path: event name is available directly from the extension method.
mod:hook_safe("MinionAnimationExtension", "anim_event", function(self, event_name, ...)
    if not event_name or event_name:sub(1, 7) ~= "attack_" then return end
    local unit = self._unit
    if not unit then return end
    _on_attack_anim_event(unit, event_name, (Managers.time and Managers.time:time("main")) or 0)
end)

-- Build a breed-level {event_index -> event_name} cache by intercepting Unit.animation_event.
-- On a listen server the server calls Unit.animation_event(unit, name) before sending the RPC,
-- so by the time rpc_minion_anim_event fires on the local client the cache is already populated.
local _orig_unit_anim_event = Unit.animation_event
Unit.animation_event = function(unit, event_name)
    local idx = _orig_unit_anim_event(unit, event_name)
    if event_name and event_name:sub(1, 7) == "attack_" and unit then
        local breed_name = _unit_breed_name[unit]
        if breed_name then
            local cache = _breed_attack_idx_cache[breed_name]
            if not cache then
                cache = {}
                _breed_attack_idx_cache[breed_name] = cache
            end
            if not cache[idx] then
                cache[idx] = event_name
            end
        end
    end
    return idx
end

-- CLIENT path: event arrives as an index; resolve via the breed cache.
mod:hook_safe("AnimationSystem", "rpc_minion_anim_event", function(self, channel_id, unit_id, event_index)
    local unit_spawner = Managers.state and Managers.state.unit_spawner
    if not unit_spawner then return end
    local unit = unit_spawner:unit(unit_id)
    if not unit then return end

    local breed_name = _unit_breed_name[unit]
    local cache = breed_name and _breed_attack_idx_cache[breed_name]
    local event_name = cache and cache[event_index]

    if not event_name or event_name:sub(1, 7) ~= "attack_" then return end
    _on_attack_anim_event(unit, event_name, (Managers.time and Managers.time:time("main")) or 0)
end)

-- _get_simulate falls back to calling self:_get() internally, so hooking it to the
-- same function as _get causes our logic to run twice per call (once as _get_simulate,
-- once as the internal _get delegate).  Give it a minimal hook that only injects
-- auto-guard — never fire inputs — to avoid the double-execution chain.
local _get_simulate = function(func, self, action_name)
    if self.type ~= "Ingame" then
        return func(self, action_name)
    end
    if cached_settings.enable_auto_guard and auto_guard_blocking and is_melee_weapon_equipped() then
        if action_name == "action_two_hold" then
            local now_gs = Managers.time:time("main") or 0
            if _guard_pulse_end_t > 0 and now_gs < _guard_pulse_end_t then
                return false
            end
            return true
        end
    end
    -- Raise the reentrance guard before calling the original _get_simulate so that
    -- the hooked _get (called internally by the original when no simulated value is
    -- set) skips fire-gate logic and behaves as a pure passthrough.
    _in_get_simulate_passthrough = true
    local result = func(self, action_name)
    _in_get_simulate_passthrough = false
    return result
end

mod:hook("InputService", "_get", _get)
mod:hook("InputService", "_get_simulate", _get_simulate)

mod:hook_safe(Block, "player_blocked_attack", function(target_unit, attacking_unit, hit_world_position, block_broken, weapon_template, attack_type, block_cost, is_perfect_block)
    if not debug_vars.guard then return end
    local player = Managers.player:local_player(1)
    if not player or target_unit ~= player.player_unit then return end
    local breed = _unit_breed_name[attacking_unit] or "unknown"
    local tth_str = _last_guard_up_tth and string.format("%.3f", _last_guard_up_tth) or "?"
    if block_broken then
        mod:info("[guard_dbg] BLOCK_BROKEN: auto_guard=%s breed=%s type=%s tth=%s",
            tostring(auto_guard_blocking), breed, tostring(attack_type), tth_str)
    else
        mod:info("[guard_dbg] BLOCK_SUCCESS: auto_guard=%s breed=%s type=%s perfect=%s tth=%s",
            tostring(auto_guard_blocking), breed, tostring(attack_type), tostring(is_perfect_block), tth_str)
    end
end)

mod:hook_safe("PlayerUnitToughnessExtension", "add_damage", function(self, damage_amount, attack_result, hit_actor, damage_profile, attack_type, attack_direction, hit_world_position_or_nil)
    if not debug_vars.guard then return end
    if damage_amount <= 0 then return end
    local player = Managers.player:local_player(1)
    if not player or self._unit ~= player.player_unit then return end
    mod:info("[guard_dbg] TOUGHNESS_HIT: auto_guard=%s type=%s dmg=%.1f",
        tostring(auto_guard_blocking), tostring(attack_type), damage_amount)
end)

mod:hook_safe("PlayerUnitFirstPersonExtension", "fixed_update", function(self, unit, dt, t, frame)
    local player = Managers.player:local_player(1)
    if not player or not player:unit_is_alive() then
        auto_guard_blocking = false
        melee_enemy_in_range = false
        melee_target_unit = nil
        melee_target_needs_heavy  = false
        melee_target_needs_thrust = false
        melee_heavy_phase       = 0
        melee_windup_detected_t = 0
        melee_activating = false
        melee_is_pickaxe = false
        _last_melee_equipped = false
        return
    end
    -- hook_safe fires for every PlayerUnitFirstPersonExtension instance (bots included).
    -- All state here belongs to the local player only; skip non-local units entirely.
    if unit ~= player.player_unit then return end

    -- Refresh per-frame caches once for the local player tick.
    _current_frame        = frame
    _cached_wielded_slot  = false  -- let get_wielded_slot() re-fetch on first use

    -- Auto guard: run scan when standalone guard is on, or when melee auto-fight is active
    local keybind = cached_settings.triggerbot_keybind
    local keybind_active = not next(keybind) or triggerbot_pressed

    local melee_equipped = is_melee_weapon_equipped()
    local melee_mode_active = cached_settings.enable_triggerbot and keybind_active and melee_equipped

    -- Track when melee is first drawn so we can suppress attacks during the wield animation.
    if melee_equipped and not _last_melee_equipped then
        melee_last_equip_t = Managers.time:time("main") or 0
    end
    _last_melee_equipped = melee_equipped

    if cached_settings.enable_auto_guard or melee_mode_active then
        -- Suppress guard detection only for manually-initiated heavies (player-pressed).
        -- Auto-fight heavies (melee_heavy_phase >= 1) must NOT suppress detection:
        -- the "guard always wins" block below needs auto_guard_blocking = true in order
        -- to cancel the auto-fight heavy and raise the block.  If we suppress here, that
        -- cancel path is never reached and the player eats hits during the charge.
        -- melee_heavy_phase is set exclusively by the auto-fight state machine, so the
        -- distinction between auto and manual is clean.
        local suppress_for_charge = false
        if melee_heavy_phase == 0 then
            local unit_data_ext = ScriptUnit_has_extension(unit, "unit_data_system")
            local wac = unit_data_ext and unit_data_ext:read_component("weapon_action")
            if wac then
                local wt = WeaponTemplate.current_weapon_template(wac)
                local _, action_settings = Action.current_action(wac, wt)
                local cur_kind = action_settings and action_settings.kind
                -- Suppress during the full heavy: windup + entire sweep.
                -- _prev_action_was_windup stays true for the duration of the sweep
                -- so every frame is suppressed, not just the first.
                if cur_kind == "windup" then
                    -- Only suppress manual heavies.  If auto_guard_blocking is already
                    -- true, the windup is either an auto-fight heavy that "guard always
                    -- wins" just canceled (game still animating) or the player pressed
                    -- heavy while guarding.  In both cases, keep the guard up.
                    if not auto_guard_blocking then
                        suppress_for_charge    = true
                        _prev_action_was_windup = true
                    else
                        _prev_action_was_windup = false
                    end
                elseif cur_kind == "sweep" and _prev_action_was_windup then
                    suppress_for_charge    = true
                    -- keep _prev_action_was_windup true to suppress all sweep frames
                else
                    _prev_action_was_windup = false
                end
            else
                _prev_action_was_windup = false
            end
        end
        -- Don't guard while in shroudfield: raising a block immediately breaks the
        -- invisibility keyword and reveals the player.
        local suppress_for_stealth = false
        if not suppress_for_charge then
            local buff_ext = ScriptUnit_has_extension(unit, "buff_system")
            suppress_for_stealth = buff_ext ~= nil and buff_ext:has_keyword(BuffSettings.keywords.invisible)
        end
        if suppress_for_charge or suppress_for_stealth then
            if debug_vars.guard and auto_guard_blocking then
                mod:info("[guard_dbg] SUPPRESS: charge=%s stealth=%s",
                    tostring(suppress_for_charge), tostring(suppress_for_stealth))
            end
            auto_guard_blocking = false
            _guard_active_unit  = nil
            _guard_pulse_end_t  = 0
            _guard_pulsed       = false
        else
            local prev_blocking = auto_guard_blocking
            local new_blocking, trigger_unit = check_power_attack_incoming(unit)

            -- Parry pulse: whenever the triggering unit changes while guard is already
            -- held, issue one brief release so the game sees a fresh press and grants
            -- a perfect block for the new attacker.  _guard_pulsed resets on attacker
            -- change so each new unit in the window gets exactly one pulse.
            if new_blocking and trigger_unit ~= _guard_active_unit then
                _guard_pulsed = false
            end
            if new_blocking and prev_blocking and not _guard_pulsed then
                local now_pu = Managers.time:time("main") or 0
                _guard_pulse_end_t = now_pu + GUARD_PULSE_DURATION
                _guard_pulsed = true
                if debug_vars.guard then
                    mod:info("[guard_dbg] PULSE: new_unit=%s prev_unit=%s",
                        tostring(_guard_trigger_info.breed), tostring(_guard_active_unit))
                end
            end

            if new_blocking then
                _guard_active_unit = trigger_unit
            else
                _guard_active_unit = nil
                _guard_pulse_end_t = 0
                _guard_pulsed      = false
            end

            auto_guard_blocking = new_blocking
            if debug_vars.guard then
                if not prev_blocking and auto_guard_blocking then
                    local ti = _guard_trigger_info
                    _last_guard_up_tth = ti.time_to_hit
                    if ti.time_to_hit then
                        mod:info("[guard_dbg] GUARD UP: layer=%s breed=%s state=%d anim_t=%.3f tth=%.3f",
                            ti.layer, tostring(ti.breed), ti.state or 0, ti.anim_t, ti.time_to_hit)
                    else
                        mod:info("[guard_dbg] GUARD UP: layer=%s breed=%s",
                            ti.layer, tostring(ti.breed))
                    end
                elseif prev_blocking and not auto_guard_blocking then
                    local dodge_reason = Dodge.is_dodging(unit, "melee") and "dodge" or "stale_or_range"
                    mod:info("[guard_dbg] GUARD DOWN: reason=%s", dodge_reason)
                end
            end
        end
    else
        auto_guard_blocking = false
    end

    -- Guard always wins: if a block is being injected, abort any in-progress
    -- charge or activation so the state machine starts clean after the guard ends.
    -- Exception: for the pickaxe in phase 1, keep the charge state so the game
    -- buffers start_attack and restarts the windup as soon as the block ends.
    if auto_guard_blocking and (melee_heavy_phase > 0 or melee_activating) then
        if not (melee_is_pickaxe and melee_heavy_phase == 1) then
            melee_heavy_phase       = 0
            melee_windup_detected_t = 0
            melee_activating        = false
        end
    end

    if melee_mode_active then
        local any_heavy_in_range
        melee_enemy_in_range, any_heavy_in_range = check_enemy_in_melee_range(unit)
        if melee_enemy_in_range then
            melee_target_needs_heavy = any_heavy_in_range

        elseif melee_heavy_phase == 0 then
            melee_target_needs_heavy  = false
            melee_target_needs_thrust = false
        end
        -- Run the phase state machine even when the enemy briefly leaves range
        -- (flinch/knockback during charge-up); only idle when both are false.
        if melee_enemy_in_range or melee_heavy_phase > 0 then
            local _udata = ScriptUnit_extension(unit, "unit_data_system")
            local _wac   = _udata and _udata:read_component("weapon_action")
            local _wt    = _wac and WeaponTemplate.current_weapon_template(_wac)
            melee_is_pickaxe = _wt ~= nil and _wt.name ~= nil and _wt.name:find("ogryn_pickaxe", 1, true) ~= nil
            local now_melee = Managers.time:time("main") or 0
            -- Trigger power-weapon activation before each heavy swing, but only when
            -- the weapon is not already charged (handles misses where charge persists,
            -- and re-charges after a hit that consumed the powered state).
            -- Skip activation while the target's void shield is up: powered heavy deals
            -- no extra damage to the shield (lerp_1 either way), so charge after it breaks.
            local void_shield_up = melee_target_unit and is_void_shield_active(melee_target_unit)
            if melee_enemy_in_range and melee_target_needs_heavy and melee_heavy_phase == 0 and not melee_activating then
                if weapon_has_power_special(_wt) and not void_shield_up then
                    if _is_weapon_special_active(unit) then
                        -- Already charged (e.g. previous swing missed); skip straight to heavy.
                        melee_heavy_phase   = 1
                        melee_heavy_start_t = now_melee
                        if debug_vars.melee then
                            mod:info("[melee_dbg] PHASE0->1 (already charged): needs_thrust=%s", tostring(melee_target_needs_thrust))
                        end
                    else
                        melee_activating         = true
                        melee_activate_start_t   = now_melee
                        melee_activate_input_key = get_power_special_input_key(_wt)
                        if debug_vars.melee then
                            mod:info("[melee_dbg] ACTIVATION start: needs_thrust=%s key=%s", tostring(melee_target_needs_thrust), tostring(melee_activate_input_key))
                        end
                    end
                end
            end
            -- State-based transition: as soon as the game reports the weapon is charged,
            -- begin the heavy swing.  This replaces the old fixed-time wait so the
            -- transition is always in sync with the actual hammer animation.
            if melee_activating and _is_weapon_special_active(unit) then
                melee_activating    = false
                melee_heavy_phase   = 1
                melee_heavy_start_t = now_melee
                if debug_vars.melee then
                    mod:info("[melee_dbg] ACTIVATION complete -> PHASE1: needs_thrust=%s needs_heavy=%s in_range=%s",
                        tostring(melee_target_needs_thrust), tostring(melee_target_needs_heavy), tostring(melee_enemy_in_range))
                end
            end
            -- Phase 1: hold action_one_hold until the game's own windup action confirms
            -- the heavy chain is available (chain_time elapsed since we first detected the
            -- windup), then release.  We track windup entry time ourselves because
            -- _wac.start_t is a component init timestamp (~0), not a per-action clock.
            if melee_heavy_phase == 1 then
                local cur_action_name = _wac and _wac.current_action_name
                local cur_action_settings = (cur_action_name and cur_action_name ~= "none")
                    and _wt and _wt.actions and _wt.actions[cur_action_name]
                local cur_kind = cur_action_settings and cur_action_settings.kind
                if debug_vars.melee then
                    local csm_ext = ScriptUnit_has_extension(unit, "character_state_machine_system")
                    local state_name = csm_ext and csm_ext:current_state_name() or "nil"
                    mod:info("[melee_dbg] phase1_tick: action=%s kind=%s windup_t=%.3f held=%.3f state=%s",
                        tostring(cur_action_name), tostring(cur_kind),
                        melee_windup_detected_t > 0 and (now_melee - melee_windup_detected_t) or -1,
                        now_melee - melee_heavy_start_t,
                        state_name)
                end
                if cur_kind == "windup" then
                    -- Record the moment we first see the windup so elapsed is accurate.
                    if melee_windup_detected_t == 0 then
                        melee_windup_detected_t = now_melee
                    end
                    local heavy_chain = cur_action_settings.allowed_chain_actions
                        and cur_action_settings.allowed_chain_actions.heavy_attack
                    local chain_t  = (heavy_chain and heavy_chain.chain_time) or 0
                    local elapsed_in_windup = now_melee - melee_windup_detected_t
                    if elapsed_in_windup >= chain_t then
                        local thrust_stacks = _get_windup_power_stacks(unit)
                        if debug_vars.melee then
                            mod:info("[melee_dbg] phase1_release: action=%s chain_t=%.3f elapsed=%.3f thrust=%s needs_thrust=%s",
                                tostring(cur_action_name), chain_t, elapsed_in_windup,
                                tostring(thrust_stacks), tostring(melee_target_needs_thrust))
                        end
                        if thrust_stacks == nil or not melee_target_needs_thrust or thrust_stacks >= 3 then
                            melee_heavy_phase       = 2
                            melee_heavy_start_t     = now_melee
                            melee_windup_detected_t = 0
                        end
                    end
                elseif cur_kind == "sweep" and melee_windup_detected_t > 0 then
                    -- Sweep committed after we already saw the windup this cycle (auto-complete).
                    -- If windup_detected_t == 0 we haven't seen the new windup yet — the game is
                    -- still finishing the PREVIOUS sweep, so keep holding rather than tapping once.
                    melee_heavy_phase       = 2
                    melee_heavy_start_t     = now_melee
                    melee_windup_detected_t = 0
                elseif (now_melee - melee_heavy_start_t) >= HEAVY_SWING_BUFFER then
                    -- Safety fallback: windup never appeared; release to avoid locking up.
                    if debug_vars.melee then
                        mod:info("[melee_dbg] phase1_fallback: no windup after %.3fs action=%s kind=%s",
                            now_melee - melee_heavy_start_t, tostring(cur_action_name), tostring(cur_kind))
                    end
                    melee_heavy_phase       = 2
                    melee_heavy_start_t     = now_melee
                    melee_windup_detected_t = 0
                end
            -- Phase 2 expiry: the heavy action is complete when weapon_action.start_t
            -- has advanced beyond the release time (a new action has started).
            -- HEAVY_SWING_BUFFER is a safety fallback in case start_t is unavailable.
            elseif melee_heavy_phase == 2 then
                if (_wac and _wac.start_t > melee_heavy_start_t + 0.05)
                or (now_melee - melee_heavy_start_t >= HEAVY_SWING_BUFFER) then
                    melee_heavy_phase       = 0
                    melee_windup_detected_t = 0
                end
            end
        else
            melee_heavy_phase       = 0
            melee_windup_detected_t = 0
            melee_activating        = false
        end
    else
        melee_enemy_in_range = false
        melee_target_unit = nil
        melee_target_needs_heavy  = false
        melee_target_needs_thrust = false
        melee_heavy_phase       = 0
        melee_windup_detected_t = 0
        melee_activating        = false
        melee_is_pickaxe        = false
    end

    local use_mouse2 = cached_settings.use_mouse2_fallback
    local mouse2_pressed = Mouse.button(Mouse.button_index("right")) > 0.5
    local should_aim = use_mouse2 and (mouse2_pressed ~= aim_button_pressed) or (not use_mouse2 and aim_button_pressed)

    if should_aim and (not cached_settings.require_main_weapon or is_main_weapon_equipped()) then
        auto_aim_priority_targets(unit)
    else
        last_aim_unit = nil
        last_aim_zone = nil
        last_aim_zone_blocked_frames = 0
        has_target = false
    end
end)

-- DamageCalculation is a plain require'd table, not a registered class, so
-- mod:hook won't find it by string name.  Monkey-patch directly instead.
-- Uses debug_vars.surgical_fired_unit (snapshotted at fire time) so projectile-
-- travel weapons (plasma, bolter) still match after last_aim_unit moves on.
-- Only patched when debug_vars.surgical is true to avoid wrapper overhead in prod.
-- On reload with true: restore the previous wrapper first, then re-patch cleanly.
-- On reload with false: the old wrapper (if any) is left in place — false is
-- treated as release mode and a full game restart is required to remove it.
if debug_vars.surgical then
    if DamageCalculation._gambits_orig_calculate then
        -- A previous patch is installed; unpatch it before re-wrapping.
        DamageCalculation.calculate = DamageCalculation._gambits_orig_calculate
    end
    DamageCalculation._gambits_orig_calculate = DamageCalculation.calculate
    DamageCalculation.calculate = function(...)
        local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 = DamageCalculation._gambits_orig_calculate(...)
        if debug_vars.surgical_fired_unit then
            local now = Managers.time and Managers.time:time("main")
            if now and debug_vars.surgical_fired_time and (now - debug_vars.surgical_fired_time) > debug_vars.surgical_miss_timeout then
                debug_vars.surgical_fired_unit = nil
                debug_vars.surgical_fired_time = nil
            end
            local target_unit        = select(30, ...)
            local is_critical_strike = select(11, ...)
            if target_unit == debug_vars.surgical_fired_unit then
                -- r3=base_damage (raw), r4=base_buff_damage (stat buff portion)
                local charge_level_srv = select(7, ...)
                mod:info("[surgical_srv] crit=%s  charge=%.4f  total=%.3f  base=%.3f  base_buff=%.3f  finesse=%.3f  adm=%.3f  zone_mult=%.3f  dmg_mult=%.4f",
                    tostring(is_critical_strike), charge_level_srv or 0,
                    r1 or 0, r3 or 0, r4 or 0, r6 or 0, r9 or 0, r10 or 0,
                    (r3 and r3 > 0) and ((r3 + (r4 or 0)) / r3) or 0)
                debug_vars.surgical_fired_unit = nil
                debug_vars.surgical_fired_time = nil
            end
        end
        return r1, r2, r3, r4, r5, r6, r7, r8, r9, r10
    end
end

mod:hook(CLASS.AccountManagerWinGDK, "_show_store_account_error", function(func, self, header_key, body_key, callback)
    if body_key == "loc_ms_store_mismatched_accounts" then
        if callback then
            callback()
        end
        return
    end
    return func(self, header_key, body_key, callback)
end)
