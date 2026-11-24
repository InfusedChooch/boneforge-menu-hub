using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal static class WorldEditParts
    {
        internal sealed class Entry
        {
            internal string Id, Name;
            internal Piece.PieceCategory Category;
            internal Sprite Icon;
        }

        internal static bool CanPlace(GameObject prefab) => prefab && prefab.GetComponent<Piece>()
            && prefab.GetComponent<ZNetView>() && !prefab.GetComponent<TerrainOp>() && !prefab.GetComponent<TerrainModifier>();

        internal static string DisplayName(Piece piece, string fallback)
        {
            string name = piece.m_name;
            if (Localization.instance != null) name = Localization.instance.Localize(name);
            return string.IsNullOrWhiteSpace(name) || name.StartsWith("$", StringComparison.Ordinal)
                || name.StartsWith("[", StringComparison.Ordinal) ? fallback : name;
        }

        internal static Entry[] Filter(Entry[] catalog, Piece.PieceCategory category, string query)
        {
            var group = catalog.Where(part => category == Piece.PieceCategory.All || part.Category == category);
            query = query.Trim();
            var exact = group.FirstOrDefault(part => string.Equals(part.Id, query, StringComparison.OrdinalIgnoreCase));
            return exact != null ? new[] { exact } : group.Where(part => CatalogRules.Matches(part.Id, part.Name, query)).ToArray();
        }

        internal static (Entry[] Parts, Dictionary<Piece.PieceCategory, string> Categories) Load()
        {
            var labels = new Dictionary<Piece.PieceCategory, string>();
            if (!ObjectDB.instance || !ZNetScene.instance) return (Array.Empty<Entry>(), labels);
            var parts = new List<Entry>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var tables = ObjectDB.instance.m_items.Where(item => item)
                .Select(item => item.GetComponent<ItemDrop>()?.m_itemData?.m_shared?.m_buildPieces)
                .Where(table => table).Distinct();
            foreach (var table in tables)
            {
                for (int i = 0; i < table.m_categories.Count && i < table.m_categoryLabels.Count; i++)
                {
                    string label = table.m_categoryLabels[i];
                    labels[table.m_categories[i]] = Localization.instance != null ? Localization.instance.Localize(label) : label;
                }
                foreach (var prefab in table.m_pieces)
                {
                    if (!CanPlace(prefab) || ZNetScene.instance.GetPrefab(prefab.name) != prefab || !seen.Add(prefab.name)) continue;
                    var piece = prefab.GetComponent<Piece>();
                    if (!piece.m_enabled) continue;
                    parts.Add(new Entry
                    {
                        Id = prefab.name,
                        Name = DisplayName(piece, prefab.name),
                        Icon = piece.m_icon,
                        Category = piece.m_category
                    });
                }
            }
            return (parts.OrderBy(part => part.Name, StringComparer.CurrentCultureIgnoreCase)
                .ThenBy(part => part.Id, StringComparer.OrdinalIgnoreCase).ToArray(), labels);
        }
    }
}
