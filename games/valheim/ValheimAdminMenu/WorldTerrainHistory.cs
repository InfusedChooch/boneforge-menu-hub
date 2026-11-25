using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal sealed partial class WorldTools
    {
        private Dictionary<ZDOID, (TileChange Change, TileArrays Buffer)> pendingTerrainEdit;

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
            pendingTerrainEdit = new Dictionary<ZDOID, (TileChange, TileArrays)>();
        }

        private void EditTerrain(string label, Action action)
        {
            if (pendingTerrainEdit != null) { action(); return; }
            BeginTerrainEdit();
            try { action(); }
            finally { app.EditHistory.Record(label, FinishTerrainEdit()); }
        }

        private TerrainStamp CaptureTerrain(IEnumerable<(Heightmap map, TerrainComp comp)> tiles)
        {
            var stamp = new TerrainStamp();
            foreach (var (_, comp) in tiles)
            {
                var id = comp.GetComponent<ZNetView>().GetZDO().m_uid;
                var live = new TileArrays(comp, false);
                if (!pendingTerrainEdit.TryGetValue(id, out var tile))
                {
                    tile = (new TileChange(id), new TileArrays(comp, true));
                    pendingTerrainEdit.Add(id, tile);
                }
                else tile.Buffer.CopyFrom(live);
                stamp.Tiles.Add((tile.Change, tile.Buffer, live));
            }
            return stamp;
        }

        // Each stamp runs synchronously. Changes between stamps belong to other edits.
        private sealed class TerrainStamp : IDisposable
        {
            internal readonly List<(TileChange Change, TileArrays Before, TileArrays Live)> Tiles
                = new List<(TileChange, TileArrays, TileArrays)>();

            public void Dispose()
            {
                foreach (var tile in Tiles) tile.Change.Merge(tile.Before, tile.Live);
            }
        }

        internal WorldEditHistory.Change FinishTerrainEdit()
        {
            var pending = pendingTerrainEdit;
            pendingTerrainEdit = null;
            if (pending == null) return null;
            var changes = pending.Values.Select(tile => tile.Change).Where(change => change.HasChanges).ToList();
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

            internal void CopyFrom(TileArrays live)
            {
                live.ModifiedHeight.CopyTo(ModifiedHeight, 0);
                live.ModifiedPaint.CopyTo(ModifiedPaint, 0);
                live.Level.CopyTo(Level, 0);
                live.Smooth.CopyTo(Smooth, 0);
                live.Mask.CopyTo(Mask, 0);
            }

            private static T[] Read<T>(TerrainComp comp, string field, bool clone)
            {
                var values = Reflection.Get<T[]>(comp, field);
                return clone ? (T[])values.Clone() : values;
            }

            internal (bool, float, float) Height(int i) => (ModifiedHeight[i], Level[i], Smooth[i]);
            internal (bool, Color) Paint(int i) => (ModifiedPaint[i], Mask[i]);
        }

        internal static void MergeTerrainPoint<T>(Dictionary<int, (T Before, T After)> changes, int index, T before, T after)
            where T : struct, IEquatable<T>
        {
            if (before.Equals(after)) return;
            if (changes.TryGetValue(index, out var prior) && prior.After.Equals(before))
                before = prior.Before;
            // If another writer intervened, undo only as far as their latest value.
            if (before.Equals(after)) changes.Remove(index);
            else changes[index] = (before, after);
        }

        private sealed class TileChange
        {
            private readonly ZDOID id;
            private TerrainComp comp;
            private Heightmap map;
            private readonly Dictionary<int, ((bool, float, float) Before, (bool, float, float) After)> heights
                = new Dictionary<int, ((bool, float, float), (bool, float, float))>();
            private readonly Dictionary<int, ((bool, Color) Before, (bool, Color) After)> paint
                = new Dictionary<int, ((bool, Color), (bool, Color))>();

            internal TileChange(ZDOID id) { this.id = id; }

            internal void Merge(TileArrays before, TileArrays after)
            {
                for (int i = 0; i < before.Level.Length; i++)
                    MergeTerrainPoint(heights, i, before.Height(i), after.Height(i));
                for (int i = 0; i < before.Mask.Length; i++)
                    MergeTerrainPoint(paint, i, before.Paint(i), after.Paint(i));
            }

            internal bool HasChanges => heights.Count != 0 || paint.Count != 0;

            internal void Check(bool undo)
            {
                var obj = ZNetScene.instance.FindInstance(id);
                comp = obj ? obj.GetComponent<TerrainComp>() : null;
                map = comp ? Heightmap.FindHeightmap(comp.transform.position) : null;
                if (!map || !Own(obj))
                    throw new InvalidOperationException("Load and own the edited terrain before replaying this entry.");
                if (!PrivateArea.CheckAccess(map.transform.position, map.m_width * map.m_scale * .71f, false, true))
                {
                    var origin = map.transform.position - new Vector3(1, 0, 1) * (map.m_width * map.m_scale * .5f);
                    int stride = map.m_width + 1;
                    bool Protected(Vector3 point) => !PrivateArea.CheckAccess(point, 0, false, true);
                    if (heights.Any(h => Protected(origin + new Vector3(h.Key % stride, 0, h.Key / stride) * map.m_scale))
                        || paint.Any(p => Protected(map.VertexMaskToWorld(p.Key % map.m_width, p.Key / map.m_width))))
                        throw new InvalidOperationException("A ward protects part of this terrain edit.");
                }
                var arrays = new TileArrays(comp, false);
                if (heights.Any(h => !arrays.Height(h.Key).Equals(undo ? h.Value.After : h.Value.Before))
                    || paint.Any(p => !arrays.Paint(p.Key).Equals(undo ? p.Value.After : p.Value.Before)))
                    throw new InvalidOperationException("The edited terrain has changed since this history entry.");
            }

            internal void Restore(bool undo)
            {
                var arrays = new TileArrays(comp, false);
                foreach (var h in heights)
                    (arrays.ModifiedHeight[h.Key], arrays.Level[h.Key], arrays.Smooth[h.Key]) = undo ? h.Value.Before : h.Value.After;
                foreach (var p in paint)
                    (arrays.ModifiedPaint[p.Key], arrays.Mask[p.Key]) = undo ? p.Value.Before : p.Value.After;
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
