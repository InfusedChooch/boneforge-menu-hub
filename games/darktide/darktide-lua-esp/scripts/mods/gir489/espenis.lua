local mod = get_mod("espenis")
local Breed = require("scripts/utilities/breed")
local UIFonts = require("scripts/managers/ui/ui_fonts")

-- Localize globals and functions for speed
local ScriptUnit = ScriptUnit
local Managers = Managers
local Unit = Unit
local Camera = Camera
local Quaternion = Quaternion
local Vector3 = Vector3
local Vector2 = Vector2
local Gui = Gui
local Gui2 = Gui2
local Color = Color
local RESOLUTION_LOOKUP = RESOLUTION_LOOKUP
local Localize = Localize
local math_clamp = math.clamp
local pairs = pairs
local next = next
local tonumber = tonumber

local BOX_THICKNESS = 2

-- Caches
local text_dimension_cache = {}
local font_data_cache = nil

local COLOR_MODE_CONFIGS = {
    green_red = {r_low=255, g_low=0, b_low=0, r_delta=-255, g_delta=255, b_delta=0},
    orange_red = {r_low=255, g_low=0, b_low=0, r_delta=0, g_delta=165, b_delta=0},
    purple_red = {r_low=255, g_low=0, b_low=0, r_delta=0, g_delta=0, b_delta=255},
    cyan_red = {r_low=255, g_low=0, b_low=0, r_delta=-255, g_delta=255, b_delta=255},
    yellow_red = {r_low=255, g_low=0, b_low=0, r_delta=0, g_delta=255, b_delta=0},
    blue_red = {r_low=255, g_low=0, b_low=0, r_delta=-255, g_delta=0, b_delta=255},
    white_red = {r_low=255, g_low=0, b_low=0, r_delta=0, g_delta=255, b_delta=255},
    pink_red = {r_low=255, g_low=0, b_low=0, r_delta=0, g_delta=105, b_delta=180}
}
local DEFAULT_COLOR_CONFIG = COLOR_MODE_CONFIGS.green_red

mod:hook_safe("HudElementCrosshair", "update", function(self, dt, t, ui_renderer, render_settings, input_service)
    local draw_box_enabled = mod:get("draw_box")
    local draw_name_enabled = mod:get("draw_name")
    if not draw_box_enabled and not draw_name_enabled then
        return
    end

    local player = Managers.player and Managers.player:local_player(1)
    if not player or not player:unit_is_alive() then
        return
    end

    local camera = Managers.state and Managers.state.camera and Managers.state.camera:camera(player.viewport_name)
    if not camera then
        return
    end

    local extension_manager = Managers.state and Managers.state.extension
    if not extension_manager then
        return
    end

    local gui = ui_renderer and ui_renderer.gui
    if not gui then
        return
    end

    -- Per-frame color config lookup (locals for speed)
    local boss_cfg  = COLOR_MODE_CONFIGS[mod:get("boss_color_mode")]  or DEFAULT_COLOR_CONFIG
    local elite_cfg = COLOR_MODE_CONFIGS[mod:get("elite_color_mode")] or DEFAULT_COLOR_CONFIG
    local spec_cfg  = COLOR_MODE_CONFIGS[mod:get("special_color_mode")] or DEFAULT_COLOR_CONFIG
    local type_color_lookup = { boss = boss_cfg, elite = elite_cfg, special = spec_cfg }

    -- Try primary ext type then fallback
    local entities = extension_manager:get_entities("MinionHuskLocomotionExtension")
    if next(entities) == nil then
        entities = extension_manager:get_entities("MinionLocomotionExtension")
        if next(entities) == nil then
            return
        end
    end

    local screen_w, screen_h = RESOLUTION_LOOKUP.width, RESOLUTION_LOOKUP.height
    local z_depth = 999

    -- Cache font data once per frame if name drawing is enabled
    if draw_name_enabled and not font_data_cache then
        font_data_cache = UIFonts.data_by_type("proxima_nova_bold")
    end
    local font_path = font_data_cache and font_data_cache.path
    local font_size = 12

    -- Camera locals
    local cam_pos = Camera.world_position(camera)
    local cam_rot = Camera.world_rotation(camera)
    local cam_forward = Quaternion.forward(cam_rot)

    -- Hot loop
    for unit, _ in pairs(entities) do
        -- unit_data extension once
        local unit_data_ext = ScriptUnit.has_extension(unit, "unit_data_system")
        if not unit_data_ext then
            goto continue
        end

        local breed = unit_data_ext:breed()
        if not breed or Breed.is_player(breed) then
            goto continue
        end

        local bname = breed.name
        if bname and bname:find("hazard") then
            goto continue
        end

        local tags = breed.tags
        if not tags then
            goto continue
        end

        local enemy_type
        if breed.is_boss then
            enemy_type = "boss"
        elseif tags.elite then
            enemy_type = "elite"
        elseif tags.special then
            enemy_type = "special"
		elseif breed.tags.ritualist then
			enemy_type = "boss"
        else
            goto continue
        end

        -- health extension once and alive check
        if not ScriptUnit.has_extension(unit, "health_system") then
            goto continue
        end
        local health_ext = ScriptUnit.extension(unit, "health_system")
        if not health_ext or not health_ext:is_alive() then
            goto continue
        end

        -- world position and frustum forward dot
        local unit_pos = Unit.world_position(unit, 1)
        local to_unit = unit_pos - cam_pos
        if Vector3.dot(cam_forward, to_unit) <= 0 then
            goto continue
        end

        -- project foot and head (single offset) once
        local foot_screen = Camera.world_to_screen(camera, unit_pos)
        if not foot_screen or foot_screen.z <= 0 then
            goto continue
        end

        -- small head offset: reuse vector math via adding components
        local head_world = Vector3(unit_pos.x, unit_pos.y, unit_pos.z + 2.0)
        local head_screen = Camera.world_to_screen(camera, head_world)
        if not head_screen or head_screen.z <= 0 then
            goto continue
        end

        local height = math.abs(head_screen.y - foot_screen.y)
        if height < 5 then
            goto continue
        end

        local width = height * 0.5
        local center_x = (foot_screen.x + head_screen.x) * 0.5
        local half_w = width * 0.5

        -- clamp box bounds to screen
        local box_min_x = math_clamp(center_x - half_w, 0, screen_w)
        local box_max_x = math_clamp(center_x + half_w, 0, screen_w)
        local box_min_y = math_clamp(head_screen.y, 0, screen_h)
        local box_max_y = math_clamp(foot_screen.y, 0, screen_h)

        -- health pct and color computation (single local cfg lookup)
        local max_health = health_ext:max_health()
        local health_pct = (max_health > 0) and (health_ext:current_health() / max_health) or 1
        local cfg = type_color_lookup[enemy_type] or spec_cfg
        local r = math_clamp(cfg.r_low + cfg.r_delta * health_pct, 0, 255)
        local g = math_clamp(cfg.g_low + cfg.g_delta * health_pct, 0, 255)
        local b = math_clamp(cfg.b_low + cfg.b_delta * health_pct, 0, 255)
        local box_color = Color(255, r, g, b)

        -- draw box: minimal allocations
        if draw_box_enabled then
            local w = box_max_x - box_min_x
            local h = box_max_y - box_min_y
            if w > 0 and h > 0 then
                Gui.rect(gui, Vector3(box_min_x, box_min_y, z_depth), Vector2(w, BOX_THICKNESS), box_color)
                Gui.rect(gui, Vector3(box_min_x, box_max_y - BOX_THICKNESS, z_depth), Vector2(w, BOX_THICKNESS), box_color)
                Gui.rect(gui, Vector3(box_min_x, box_min_y, z_depth), Vector2(BOX_THICKNESS, h), box_color)
                Gui.rect(gui, Vector3(box_max_x - BOX_THICKNESS, box_min_y, z_depth), Vector2(BOX_THICKNESS, h), box_color)
            end
        end

        -- draw name using cached text extents
        if draw_name_enabled and font_path then
            local enemy_name = Localize(breed.display_name)
            local cached = text_dimension_cache[enemy_name]
            local text_w, text_h

            if cached then
                text_w, text_h = cached.width, cached.height
            else
                local tmin, tmax = Gui2.slug_text_max_extents(gui, enemy_name, font_path, font_size, "flags")
                local tmin_x, tmin_y = Vector3.to_elements(tmin)
                local tmax_x, tmax_y = Vector3.to_elements(tmax)
                text_w, text_h = tmax_x - tmin_x, tmax_y - tmin_y
                if text_w > 0 and text_h > 0 then
                    text_dimension_cache[enemy_name] = { width = text_w, height = text_h }
                else
                    text_w, text_h = 0, 0
                end
            end

            local text_x = center_x - (text_w * 0.5)
            local text_y = box_min_y - text_h - 2
            local pos = Vector3(text_x, text_y, z_depth)
            Gui2.slug_text(gui, enemy_name, font_path, font_size, pos, Vector2(math.huge, math.huge), { shadow = false, color = box_color })
        end

        ::continue::
    end
end)
