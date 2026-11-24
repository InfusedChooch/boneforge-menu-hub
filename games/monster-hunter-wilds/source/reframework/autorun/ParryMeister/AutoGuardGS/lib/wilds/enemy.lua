-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 GGG <1635656638@qq.com>
-- lib/wilds/enemy：怪物。
local M = {}

-- 攻击来源是不是怪物（小怪也算）。T_CharacterBase 传 sdk.typeof("app.CharacterBase")，初始化时取一次
-- Hit owners may be a GameObject or a CharacterBase component.
local function character(owner, T_CharacterBase)
    if not owner then return nil end
    if owner:get_type_definition():is_a("app.CharacterBase") then return owner end
    return owner:call("getComponent(System.Type)", T_CharacterBase)
end

function M.is_enemy(owner, T_CharacterBase)
    local chara = character(owner, T_CharacterBase)
    if chara then return chara:get_type_definition():is_a("app.EnemyCharacter") end
    if not owner then return false end
    -- Observed monster projectiles have no CharacterBase (e.g. em0160_00_Shell).
    -- Match that specific game-object format; generic/player shells stay excluded.
    local ok, name = pcall(owner.call, owner, "get_Name")
    return ok and type(name) == "string" and name:lower():match("^em%d%d%d%d_%d%d_shell$") ~= nil
end

-- Called only while the local hunter is in the training area. The training
-- device need not have a CharacterBase; keep hunter/Palico attacks excluded.
function M.is_training_source(owner, T_CharacterBase)
    local chara = character(owner, T_CharacterBase)
    if not chara then return true end
    local td = chara:get_type_definition()
    return not td:is_a("app.HunterCharacter") and not td:is_a("app.OtomoCharacter")
end

-- 按 SystemIndex（攻击预告里的 EmSystemIndex）找怪物本体 app.EnemyCharacter；链上任一环为 nil 返回 nil。
-- 路径 2026-10-11 MCP 核对：EnemyManager:findEnemy_SystemIndex(Int32) → app.cEnemyManageInfo → get_Character()
function M.by_system_index(idx)
    local mgr = sdk.get_managed_singleton("app.EnemyManager")
    if not mgr then return nil end
    local info = mgr:call("findEnemy_SystemIndex(System.Int32)", idx)
    if not info then return nil end
    return info:call("get_Character")
end

return M
