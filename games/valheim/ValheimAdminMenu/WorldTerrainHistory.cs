using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal sealed partial class WorldTools
    {
        private Dictionary<TerrainComp, (Heightmap Map, TileArrays Before)> pendingTerrainEdit;

        internal static string BrushLabel(string operation)
        {
            switch (operation)
            {
                case "level":
                case "levellook":
                case "levelplayer": return "flatten terrain";
                case "raise": return "raise terrain";
                case "lower": return "lower terrain";
                case "terrace": return "terrace terrain";
                case "peak": return "raise peak";
                case "smooth": return "smooth terrain";
                case "paint": return "paint ground";
                case "fillholes": return "fill dips";
                default: return "reset terrain heights and paint";
            }
        }

        internal void BeginTerrainEdit()
        {
            if (pendingTerrainEdit != null) throw new InvalidOperationException("Finish the current terrain edit first.");
            pendingTerrainEdit = new Dictionary<TerrainComp, (Heightmap, TileArrays)>();
        }

        private void EditTerrain(string label, Action action)
        {
            if (pendingTerrainEdit != null) { action(); return; }
            BeginTerrainEdit();
            try { action(); }
            finally { app.EditHistory.Record(label, FinishTerrainEdit()); }
        }

        private void CaptureTerrain(IEnumerable<(Heightmap map, TerrainComp comp)> tiles)
        {
            foreach (var (map, comp) in tiles)
                if (!pendingTerrainEdit.ContainsKey(comp))
                    pendingTerrainEdit.Add(comp, (map, new TileArrays(comp, true)));
        }

        internal WorldEditHistory.Change FinishTerrainEdit()
        {
            var pending = pendingTerrainEdit;
            pendingTerrainEdit = null;
            if (pending == null) return null;
            var changes = new List<TileChange>();
            foreach (var tile in pending)
            {
                if (!tile.Key || !tile.Value.Map) continue;
                var after = new TileArrays(tile.Key, false);
                var change = new TileChange(tile.Key, tile.Value.Map, tile.Value.Before, after);
                if (change.HasChanges) changes.Add(change);
            }
            if (changes.Count == 0) return null;
            return new WorldEditHistory.Change(
                () => changes.ForEach(tile => tile.Check(undo: true)),
                () => changes.ForEach(tile => tile.Restore(undo: true)),
                () => changes.ForEach(tile => tile.Check(undo: false)),
                () => changes.ForEach(tile => tile.Restore(undo: false)));
        }

        private sealed class TileArrays
        {
            internal readonly bool[] ModifiedHeight, ModifiedPaint;
            internal readonly float[] Level, Smooth;
            internal readonly Color[] Mask;

            internal TileArrays(TerrainComp comp, bool clone)
            {
                ModifiedHeight = Read<bool>(comp, "m_modifiedHeight", clone);
                ModifiedPaint = Read<bool>(comp, "m_modifiedPaint", clone);
                Level = Read<float>(comp, "m_levelDelta", clone);
                Smooth = Read<float>(comp, "m_smoothDelta", clone);
                Mask = Read<Color>(comp, "m_paintMask", clone);
            }

            private static T[] Read<T>(TerrainComp comp, string field, bool clone)
            {
                var values = Reflection.Get<T[]>(comp, field);
                return clone ? (T[])values.Clone() : values;
            }

            internal (bool, float, float) Height(int i) => (ModifiedHeight[i], Level[i], Smooth[i]);
            internal (bool, Color) Paint(int i) => (ModifiedPaint[i], Mask[i]);
        }

        private sealed class TileChange
        {
            private readonly TerrainComp comp;
            private readonly Heightmap map;
            private readonly (int Index, (bool, float, float) Before, (bool, float, float) After)[] heights;
            private readonly (int Index, (bool, Color) Before, (bool, Color) After)[] paint;

            internal TileChange(TerrainComp comp, Heightmap map, TileArrays before, TileArrays after)
            {
                this.comp = comp;
                this.map = map;
                heights = Enumerable.Range(0, before.Level.Length)
                    .Where(i => !before.Height(i).Equals(after.Height(i)))
                    .Select(i => (i, before.Height(i), after.Height(i))).ToArray();
                paint = Enumerable.Range(0, before.Mask.Length)
                    .Where(i => !before.Paint(i).Equals(after.Paint(i)))
                    .Select(i => (i, before.Paint(i), after.Paint(i))).ToArray();
            }

            internal bool HasChanges => heights.Length != 0 || paint.Length != 0;

            internal void Check(bool undo)
            {
                if (!comp || !map || !Own(comp.gameObject))
                    throw new InvalidOperationException("Load and own the edited terrain before replaying this entry.");
                if (!PrivateArea.CheckAccess(map.transform.position, map.m_width * map.m_scale * .71f, false, true))
                {
                    var origin = map.transform.position - new Vector3(1, 0, 1) * (map.m_width * map.m_scale * .5f);
                    int stride = map.m_width + 1;
                    bool Protected(Vector3 point) => !PrivateArea.CheckAccess(point, 0, false, true);
                    if (heights.Any(h => Protected(origin + new Vector3(h.Index % stride, 0, h.Index / stride) * map.m_scale))
                        || paint.Any(p => Protected(map.VertexMaskToWorld(p.Index % map.m_width, p.Index / map.m_width))))
                        throw new InvalidOperationException("A ward protects part of this terrain edit.");
                }
                var arrays = new TileArrays(comp, false);
                if (heights.Any(h => !arrays.Height(h.Index).Equals(undo ? h.After : h.Before))
                    || paint.Any(p => !arrays.Paint(p.Index).Equals(undo ? p.After : p.Before)))
                    throw new InvalidOperationException("The edited terrain has changed since this history entry.");
            }

            internal void Restore(bool undo)
            {
                var arrays = new TileArrays(comp, false);
                foreach (var h in heights)
                    (arrays.ModifiedHeight[h.Index], arrays.Level[h.Index], arrays.Smooth[h.Index]) = undo ? h.Before : h.After;
                foreach (var p in paint)
                    (arrays.ModifiedPaint[p.Index], arrays.Mask[p.Index]) = undo ? p.Before : p.After;
                SaveTerrainTile(comp, map);
            }
        }

        private static void SaveTerrainTile(TerrainComp comp, Heightmap map)
        {
            Vector3 center = map.transform.position;
            float reach = map.m_width * map.m_scale;
            Reflection.Set(comp, "m_lastOpPoint", center);
            Reflection.Set(comp, "m_lastOpRadius", reach);
            Reflection.Method(typeof(TerrainComp), "Save", typeof(bool)).Invoke(comp, new object[] { false });
            map.Poke(1);
            if (ClutterSystem.instance) ClutterSystem.instance.ResetGrass(center, reach);
        }
    }
}
