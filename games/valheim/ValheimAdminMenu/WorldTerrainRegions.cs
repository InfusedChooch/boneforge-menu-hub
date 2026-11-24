using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection.Emit;
using HarmonyLib;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal sealed class TerrainAreaStamp
    {
        internal readonly Vector3 Center;
        internal readonly Vector2 Size;
        internal readonly float MinHeight, MaxHeight;
        private readonly float[,] heights;
        private readonly Color[,] paint;

        internal TerrainAreaStamp(Vector3 first, Vector3 second)
        {
            float x0 = Mathf.Min(first.x, second.x), z0 = Mathf.Min(first.z, second.z);
            Size = new Vector2(Mathf.Abs(first.x - second.x), Mathf.Abs(first.z - second.z));
            if (Size.x < 1f || Size.y < 1f || Size.x > 200f || Size.y > 200f)
                throw new InvalidOperationException("Select at least 1 × 1 m and at most 200 × 200 m.");
            Center = new Vector3(x0 + Size.x / 2f, 0f, z0 + Size.y / 2f);
            if (!Heightmap.GetHeight(Center, out float middle))
                throw new InvalidOperationException("Load the entire area before copying.");
            Center.y = middle;
            int width = Mathf.CeilToInt(Size.x) + 1, depth = Mathf.CeilToInt(Size.y) + 1;
            heights = new float[width, depth];
            paint = new Color[width, depth];
            MinHeight = MaxHeight = middle;
            for (int z = 0; z < depth; z++)
            for (int x = 0; x < width; x++)
            {
                var point = new Vector3(x0 + Size.x * x / (width - 1), middle, z0 + Size.y * z / (depth - 1));
                var map = Heightmap.FindHeightmap(point);
                if (!map || !map.GetWorldHeight(point, out float height))
                    throw new InvalidOperationException("Load the entire area before copying.");
                heights[x, z] = height - middle;
                paint[x, z] = map.GetPaintMask(point);
                MinHeight = Mathf.Min(MinHeight, height);
                MaxHeight = Mathf.Max(MaxHeight, height);
            }
        }

        internal bool Contains(Vector3 local) =>
            Mathf.Abs(local.x) <= Size.x / 2f + .001f && Mathf.Abs(local.z) <= Size.y / 2f + .001f;

        private Vector2 Grid(Vector3 local) => new Vector2(
            Mathf.Clamp01(local.x / Size.x + .5f) * (heights.GetLength(0) - 1),
            Mathf.Clamp01(local.z / Size.y + .5f) * (heights.GetLength(1) - 1));

        internal float Height(Vector3 local)
        {
            var grid = Grid(local);
            int x = Mathf.FloorToInt(grid.x), z = Mathf.FloorToInt(grid.y);
            int x1 = Mathf.Min(x + 1, heights.GetLength(0) - 1), z1 = Mathf.Min(z + 1, heights.GetLength(1) - 1);
            return Mathf.Lerp(Mathf.Lerp(heights[x, z], heights[x1, z], grid.x - x),
                Mathf.Lerp(heights[x, z1], heights[x1, z1], grid.x - x), grid.y - z);
        }

        internal Color GroundPaint(Vector3 local)
        {
            var grid = Grid(local);
            return paint[Mathf.RoundToInt(grid.x), Mathf.RoundToInt(grid.y)];
        }
    }

    internal sealed partial class WorldTools
    {
        internal const string ExtendedTerrainKey = "valheaven.landform.extended";
        internal const float LandformLimit = 64f;
        internal static bool CanExtendTerrain => ZNet.instance && ZNet.instance.IsServer() && !ZNet.IsOpenServer();

        internal void ApplyArea(TerrainAreaStamp area, Vector3 origin, Quaternion rotation)
        {
            var inverse = Quaternion.Inverse(rotation);
            ApplyRegion(origin, area.Size.magnitude / 2f + 2f, (point, current) =>
            {
                var local = inverse * (point - origin);
                return area.Contains(local) ? (float?)(origin.y + area.Height(local) - current) : null;
            }, point =>
            {
                var local = inverse * (point - origin);
                return area.Contains(local) ? (Color?)area.GroundPaint(local) : null;
            }, extended: false);
        }

        internal void ApplyRegion(Vector3 center, float reach, Func<Vector3, float, float?> heightDelta,
            Func<Vector3, Color?> paintAt = null, bool extended = false)
        {
            app.RequireWorld();
            if (!PrivateArea.CheckAccess(center, reach, false, true))
                throw new InvalidOperationException("A ward protects this terrain region.");
            if (extended && !CanExtendTerrain)
                throw new InvalidOperationException("Tall landforms require a local single-player world.");
            var maps = new List<Heightmap>();
            Heightmap.FindHeightmap(center, reach, maps);
            if (maps.Count == 0) throw new InvalidOperationException("Load the edited terrain first.");
            var tiles = maps.Select(map => (map, comp: map.GetAndCreateTerrainCompiler())).ToList();
            if (tiles.Any(tile => !tile.comp || !Own(tile.comp.gameObject)))
                throw new InvalidOperationException("The editor needs ownership of every affected terrain tile.");
            CaptureTerrain(tiles);
            foreach (var (map, comp) in tiles)
            {
                var arrays = new TileArrays(comp, false);
                var offset = map.transform.position;
                float half = map.m_width * .5f;
                int pitch = map.m_width + 1;
                bool changed = false;
                for (int z = 0; z < pitch; z++)
                for (int x = 0; x < pitch; x++)
                {
                    var point = offset + new Vector3((x - half) * map.m_scale, 0f, (z - half) * map.m_scale);
                    int i = z * pitch + x;
                    float current = map.GetHeight(x, z) + offset.y;
                    var delta = heightDelta(point, current);
                    if (delta.HasValue && Mathf.Abs(delta.Value) > .0001f)
                    {
                        float existing = arrays.Level[i] + arrays.Smooth[i];
                        float limit = extended ? LandformLimit : 8f;
                        float next = Mathf.Clamp(existing + delta.Value, Mathf.Min(-limit, existing), Mathf.Max(limit, existing));
                        if (!Mathf.Approximately(existing, next))
                        {
                            arrays.ModifiedHeight[i] = true;
                            arrays.Level[i] = next;
                            arrays.Smooth[i] = 0f;
                            changed = true;
                        }
                    }
                    if (paintAt == null || x == map.m_width || z == map.m_width) continue;
                    var color = paintAt(point + new Vector3(.5f * map.m_scale, 0f, .5f * map.m_scale));
                    if (!color.HasValue) continue;
                    int at = z * map.m_width + x;
                    if (arrays.ModifiedPaint[at] && arrays.Mask[at].Equals(color.Value)) continue;
                    arrays.ModifiedPaint[at] = true;
                    arrays.Mask[at] = color.Value;
                    changed = true;
                }
                if (!changed) continue;
                if (extended) comp.GetComponent<ZNetView>().GetZDO().Set(ExtendedTerrainKey, true);
                SaveTerrainTile(comp, map);
            }
        }
    }

    [HarmonyPatch(typeof(TerrainComp), nameof(TerrainComp.ApplyToHeightmap))]
    internal static class ValheavenLandformHeightPatch
    {
        private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> original)
        {
            var code = original.ToList();
            var clamp = AccessTools.Method(typeof(Mathf), nameof(Mathf.Clamp), new[] { typeof(float), typeof(float), typeof(float) });
            var matches = code.Select((instruction, index) => (instruction, index)).Where(item => item.instruction.Calls(clamp)).ToArray();
            if (matches.Length != 1)
            {
                AppLog.Warning("Valheaven landform height hook unavailable. The game terrain limit remains in effect.");
                return code;
            }
            var call = matches[0].instruction;
            var loadCompiler = new CodeInstruction(OpCodes.Ldarg_0);
            loadCompiler.labels.AddRange(call.labels);
            call.labels.Clear();
            loadCompiler.blocks.AddRange(call.blocks);
            call.blocks.Clear();
            code.Insert(matches[0].index, loadCompiler);
            call.operand = AccessTools.Method(typeof(ValheavenLandformHeightPatch), nameof(ClampHeight));
            Available = true;
            return code;
        }

        internal static bool Available { get; private set; }

        private static float ClampHeight(float value, float min, float max, TerrainComp comp)
        {
            if ((value >= min && value <= max) || !WorldTools.CanExtendTerrain)
                return Mathf.Clamp(value, min, max);
            var view = comp.GetComponent<ZNetView>();
            if (!view || view.GetZDO()?.GetBool(WorldTools.ExtendedTerrainKey, false) != true)
                return Mathf.Clamp(value, min, max);
            float middle = (min + max) / 2f;
            return Mathf.Clamp(value, middle - WorldTools.LandformLimit, middle + WorldTools.LandformLimit);
        }
    }
}
