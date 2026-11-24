using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal sealed partial class TerrainSculptMode
    {
        private enum RegionTool { None, Area, Landform }
        private RegionTool regionTool;
        private Vector3? dragStart;
        private (Vector3 First, Vector3 Second)? areaSelection;
        private TerrainAreaStamp copiedArea;
        private List<Release250.CopiedPiece> areaPieces;
        private readonly List<Hill> hills = new List<Hill>();
        private Hill selectedHill;

        private sealed class Hill
        {
            internal readonly Vector3 Center;
            internal readonly float Radius, Height;
            internal Hill(Vector3 center, float radius, float height)
            { Center = center; Radius = radius; Height = height; }

            internal float Contribution(Vector3 point)
            {
                var displacement = new Vector2(point.x - Center.x, point.z - Center.z);
                return Height * (1f - Mathf.SmoothStep(0f, 1f, displacement.magnitude / Radius));
            }
        }

        private void ClearRegions()
        {
            ExitRegionTool();
            areaSelection = null;
            copiedArea = null;
            areaPieces = null;
            hills.Clear();
        }

        private void ExitRegionTool()
        {
            regionTool = RegionTool.None;
            selectedHill = null;
            dragStart = null;
        }

        private bool CancelRegionTool()
        {
            if (regionTool == RegionTool.None) return false;
            ExitRegionTool();
            return true;
        }

        private bool HandleRegionPointer()
        {
            if (Input.GetKeyDown(KeyCode.G) || Input.GetKeyDown(KeyCode.L))
            {
                SelectRegion(Input.GetKeyDown(KeyCode.G) ? RegionTool.Area : RegionTool.Landform);
                return true;
            }
            bool control = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
            if (control && Input.GetKeyDown(KeyCode.V))
            {
                FinishStroke();
                TryEdit(OpenAreaPreview);
                return true;
            }
            if (regionTool == RegionTool.Area && control && Input.GetKeyDown(KeyCode.C))
            {
                TryEdit(CopyArea, showResult: true);
                return true;
            }
            if (regionTool == RegionTool.None) return false;
            if (Input.GetMouseButtonDown(1))
            {
                dragStart = null;
                if (regionTool == RegionTool.Area) areaSelection = null;
                else selectedHill = null;
                return true;
            }
            if (regionTool == RegionTool.Landform && selectedHill != null)
            {
                if (Input.GetKeyDown(KeyCode.PageUp)) TryEdit(() => ResizeHill(2f), showResult: true);
                if (Input.GetKeyDown(KeyCode.PageDown)) TryEdit(() => ResizeHill(-2f), showResult: true);
                if (Input.GetKeyDown(KeyCode.Delete)) TryEdit(() => EditHill(selectedHill, null, "remove hill"), showResult: true);
            }
            if (Input.GetMouseButtonDown(0) && target.HasValue)
            {
                if (regionTool == RegionTool.Landform)
                {
                    var hit = target.Value;
                    selectedHill = hills.LastOrDefault(hill => hill.Contribution(hit) > .05f);
                    if (selectedHill != null) return true;
                }
                dragStart = target;
            }
            if (!Input.GetMouseButtonUp(0) || !dragStart.HasValue) return true;
            var start = dragStart.Value;
            dragStart = null;
            if (target.HasValue) CompleteRegionDrag(start, target.Value);
            return true;
        }

        private void CompleteRegionDrag(Vector3 start, Vector3 end)
        {
            if (regionTool == RegionTool.Area)
            {
                areaSelection = (start, end);
                return;
            }
            float radius = Mathf.Clamp(Vector2.Distance(new Vector2(start.x, start.z),
                new Vector2(end.x, end.z)), 2f, 50f);
            float height = ExtendedHills ? 25f : 6f;
            TryEdit(() => EditHill(null, new Hill(start, radius, height), "create hill"), showResult: true);
        }

        private void CopyArea()
        {
            if (!areaSelection.HasValue) throw new InvalidOperationException("Drag an area before copying.");
            var selection = areaSelection.Value;
            var stamp = new TerrainAreaStamp(selection.First, selection.Second);
            var pieces = Release250.CollectAreaPieces(stamp);
            copiedArea = stamp;
            areaPieces = pieces;
            app.Report($"Copied {stamp.Size.x:0.#} × {stamp.Size.y:0.#} m and {pieces.Count} pieces or objects. Ctrl+V previews it.");
        }

        private void OpenAreaPreview()
        {
            if (copiedArea == null) throw new InvalidOperationException("Copy a selected area with Ctrl+C first.");
            Release250.BeginCursorArea(copiedArea, areaPieces);
            Release250.UpdateCursorPaste(target);
        }

        private static bool ExtendedHills => WorldTools.CanExtendTerrain && ValheavenLandformHeightPatch.Available;

        private void ResizeHill(float delta)
        {
            var old = selectedHill;
            float height = Mathf.Clamp(old.Height + delta, 1f, ExtendedHills ? 50f : 8f);
            if (Mathf.Approximately(height, old.Height)) return;
            EditHill(old, new Hill(old.Center, old.Radius, height), "resize hill");
        }

        private void EditHill(Hill before, Hill after, string label)
        {
            var footprint = after ?? before;
            bool extended = (before?.Height ?? 0f) > 8f || (after?.Height ?? 0f) > 8f;
            if (extended && !ExtendedHills) throw new InvalidOperationException("Tall hills require a local world with the height hook available.");
            app.World.BeginTerrainEdit();
            WorldEditHistory.Change terrain;
            bool success = false;
            try
            {
                app.World.ApplyRegion(footprint.Center, footprint.Radius + 2f, (point, _) =>
                    (after?.Contribution(point) ?? 0f) - (before?.Contribution(point) ?? 0f), extended: extended);
                success = true;
            }
            finally
            {
                terrain = app.World.FinishTerrainEdit();
                if (!success) app.EditHistory.Record(label, terrain);
            }
            if (terrain == null) throw new InvalidOperationException("The hill made no terrain change.");
            SetHill(before, after);
            var handles = new WorldEditHistory.Change(() => { }, () => SetHill(after, before), () => { }, () => SetHill(before, after));
            app.EditHistory.Record(label, WorldEditHistory.Change.Combine(terrain, handles));
            app.Report(after == null ? "Hill removed." : $"Hill height {after.Height:0.#} m, radius {after.Radius:0.#} m.");
        }

        private void SetHill(Hill old, Hill replacement)
        {
            if (old != null) hills.Remove(old);
            if (replacement != null) hills.Add(replacement);
            if (selectedHill == old) selectedHill = replacement;
        }

        private string RegionTitle()
        {
            if (Release250.CursorArea != null)
            {
                var size = Release250.CursorArea.Size;
                return $"Paste area  |  {size.x:0.#} × {size.y:0.#} m  |  Rotation {Release250.PasteYaw:0}°";
            }
            if (regionTool == RegionTool.Area)
            {
                if (!areaSelection.HasValue) return "Area copy  |  Drag a rectangle";
                var box = areaSelection.Value;
                return $"Area selected  |  {Mathf.Abs(box.First.x - box.Second.x):0.#} × {Mathf.Abs(box.First.z - box.Second.z):0.#} m";
            }
            if (regionTool == RegionTool.Landform)
                return selectedHill == null ? "Landforms  |  Drag from the center to create a hill"
                    : $"Selected hill  |  Height {selectedHill.Height:0.#} m  |  Radius {selectedHill.Radius:0.#} m";
            return null;
        }

        private bool DrawRegions()
        {
            var previousColor = GUI.color;
            try
            {
                if (Release250.CursorArea != null)
                {
                    if (target.HasValue)
                        DrawRectangle(Release250.PasteWorldOrigin(), Release250.CursorArea.Size,
                            Release250.PasteRotation(), new Color(.53f, 1f, .67f));
                    return true;
                }
                if (regionTool == RegionTool.Area)
                {
                    var selection = dragStart.HasValue && target.HasValue ? (dragStart.Value, target.Value) : areaSelection;
                    if (selection.HasValue)
                    {
                        var (a, b) = selection.Value;
                        DrawRectangle((a + b) * .5f, new Vector2(Mathf.Abs(a.x - b.x), Mathf.Abs(a.z - b.z)),
                            Quaternion.identity, new Color(.42f, .85f, 1f));
                    }
                    return true;
                }
                if (regionTool == RegionTool.Landform)
                {
                    foreach (var hill in hills)
                        DrawHillOutline(hill.Center, hill.Radius, hill == selectedHill
                            ? new Color(1f, .75f, .33f) : new Color(.9f, .75f, .55f, .48f));
                    if (dragStart.HasValue && target.HasValue)
                    {
                        var delta = target.Value - dragStart.Value;
                        DrawHillOutline(dragStart.Value, new Vector2(delta.x, delta.z).magnitude, Color.white);
                    }
                    return true;
                }
                return false;
            }
            finally { GUI.color = previousColor; }
        }

        private void DrawHillOutline(Vector3 center, float radius, Color color)
        {
            GUI.color = color;
            const int segments = 32;
            float angle = 2f * Mathf.PI / segments;
            for (int i = 0; i < segments; i++)
                Release250.DrawScreenLine(camera, OnGround(Rim(center, radius, i * angle)), OnGround(Rim(center, radius, (i + 1) * angle)));
        }

        private void DrawRectangle(Vector3 center, Vector2 size, Quaternion rotation, Color color)
        {
            GUI.color = color;
            var x = rotation * (Vector3.right * size.x * .5f);
            var z = rotation * (Vector3.forward * size.y * .5f);
            Vector3 a = OnGround(center - x - z), b = OnGround(center + x - z);
            Vector3 c = OnGround(center + x + z), d = OnGround(center - x + z);
            Release250.DrawScreenLine(camera, a, b);
            Release250.DrawScreenLine(camera, b, c);
            Release250.DrawScreenLine(camera, c, d);
            Release250.DrawScreenLine(camera, d, a);
        }

        private static Vector3 OnGround(Vector3 point)
        {
            if (Heightmap.GetHeight(point, out float y)) point.y = y + .15f;
            return point;
        }
    }
}
