using System;
using System.Collections.Generic;

namespace ValheimAdminMenu
{
    internal sealed class MenuSearchHit
    {
        internal string LabelKey;
        internal string KeywordsKey;
        internal int Tab;
        internal int Sub;
        internal string ResolvedLabel => L.T(LabelKey);
        internal string ResolvedKeywords => L.T(KeywordsKey);
    }

    /// <summary>Header search index (tab / sub-tab targets).</summary>
    internal static class MenuSearchIndex
    {
        // Tab map: 0 Character, 1 Build, 2 Items, 3 Entities, 4 VFX, 5 Equipment, 6 Farming,
        // 7 World, 8 Teleport, 9 Camera, 10 ESP, 11 Events, 12 Hotkeys, 13 Settings, 14 World Edit
        internal static readonly MenuSearchHit[] All =
        {
            H("search.one_hit_creatures", "search.one_hit_creatures.kw", 0, 0),
            H("search.one_hit_structures", "search.one_hit_structures.kw", 0, 0),
            H("search.god_mode", "search.god_mode.kw", 0, 0),
            H("search.keep_inventory", "search.keep_inventory.kw", 0, 1),
            H("search.keep_food", "search.keep_food.kw", 0, 1),
            H("search.death_recovery", "search.death_recovery.kw", 0, 1),
            H("search.flight", "search.flight.kw", 0, 3),
            H("search.sit", "search.sit.kw", 0, 3),
            H("sub.world.terrain", "search.world_edit_terrain.kw", MenuView.WorldEditTab, MenuView.WorldEditTerrainSub),
            H("world_edit.parts_title", "search.world_edit_parts.kw", MenuView.WorldEditTab, MenuView.WorldEditStructuresSub),
            H("search.copy_structure", "search.copy_structure.kw", MenuView.WorldEditTab, MenuView.WorldEditStructuresSub),
            H("search.blueprint", "search.blueprint.kw", MenuView.WorldEditTab, MenuView.WorldEditStructuresSub),
            H("search.piece_scale", "search.piece_scale.kw", 1, 5),
            H("search.repair_hammer", "search.repair_hammer.kw", 1, 5),
            H("search.chest_sort", "search.chest_sort.kw", 1, 4),
            H("search.auto_pickup", "search.auto_pickup.kw", 1, 4),
            H("search.deposit_junk", "search.deposit_junk.kw", 1, 4),
            H("search.inv_capacity", "search.inv_capacity.kw", 1, 4),
            H("search.stack_size", "search.stack_size.kw", 1, 4),
            H("search.item_spawn", "search.item_spawn.kw", 2, -1),
            H("search.vfx_spawn", "search.vfx_spawn.kw", 4, -1),
            H("search.farming", "search.farming.kw", 6, -1),
            H("search.force_grow", "search.force_grow.kw", 6, -1),
            H("search.copy_structure2", "search.copy_structure2.kw", MenuView.WorldEditTab, MenuView.WorldEditStructuresSub),
            H("search.fit_location", "search.fit_location.kw", MenuView.WorldEditTab, MenuView.WorldEditStructuresSub),
            H("search.freecam", "search.freecam.kw", 9, -1),
            H("search.freecam_build", "search.freecam_build.kw", 9, -1),
            H("search.melee_lock", "search.melee_lock.kw", 0, 0),
            H("search.flying_mount", "search.flying_mount.kw", 0, 3),
            H("search.mount_next", "search.mount_next.kw", 0, 3),
            H("search.paste_level", "search.paste_level.kw", MenuView.WorldEditTab, MenuView.WorldEditStructuresSub),
            H("search.photo_mode", "search.photo_mode.kw", 9, -1),
            H("search.minimap_zoom", "search.minimap_zoom.kw", 9, -1),
            H("search.tp_ping", "search.tp_ping.kw", 8, -1),
            H("search.portal_fade", "search.portal_fade.kw", 8, -1),
            H("search.credits", "search.edition.kw", 12, -1),
            H("search.hotkeys", "search.hotkeys.kw", 11, -1),
            H("search.settings_save", "search.settings_save.kw", 12, -1),
            H("search.language", "search.language.kw", 12, -1),
        };

        private static MenuSearchHit H(string labelKey, string keywordsKey, int tab, int sub)
            => new MenuSearchHit { LabelKey = labelKey, KeywordsKey = keywordsKey, Tab = tab, Sub = sub };
    }
}
