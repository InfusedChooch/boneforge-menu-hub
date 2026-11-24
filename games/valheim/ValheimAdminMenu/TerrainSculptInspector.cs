using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal sealed partial class TerrainSculptMode
    {
        private Vector2 partScroll, categoryScroll, historyScroll;
        private bool partsOpen, historyOpen, focusPartSearch;
        private int categoryIndex;
        private string partQuery = "";
        private WorldEditParts.Entry[] partCatalog, partResults;
        private Piece.PieceCategory[] categories;
        private Dictionary<Piece.PieceCategory, string> categoryLabels;
        internal bool EditingPartSearch { get; private set; }

        private Rect SearchBox => new Rect(10, 44, RightPanel.width - 20, 25);
        private Vector2 ToGuiPoint(Vector2 pointer) =>
            new Vector2(pointer.x, Screen.height - pointer.y) / SculptViewport.DockScale(Screen.width, Screen.height);
        private bool OverPartSearch(Vector2 pointer) => partsOpen && SearchBox.Contains(ToGuiPoint(pointer) - RightPanel.position);
        private static string HeightLabel => $"{Release250.PasteHeightOffset:+0.##;-0.##;0} m";

        private void OpenPartsPanel()
        {
            FinishStroke();
            ExitRegionTool();
            if (partCatalog == null || partCatalog.Length == 0)
            {
                var catalog = WorldEditParts.Load();
                partCatalog = catalog.Parts;
                categoryLabels = catalog.Categories;
                categories = new[] { Piece.PieceCategory.All }.Concat(partCatalog.Select(p => p.Category)
                    .Where(c => c != Piece.PieceCategory.All).Distinct().OrderBy(c => c)).ToArray();
                RefreshParts();
            }
            EndSelectionTool();
            partsOpen = true;
            rightClosed = false;
        }

        private void ClosePartsPanel()
        {
            partsOpen = EditingPartSearch = focusPartSearch = false;
        }

        private void TogglePartsPanel()
        {
            if (partsOpen) { rightClosed = !rightClosed; EditingPartSearch = focusPartSearch = false; return; }
            if (Release250.CursorPasteActive && Release250.CursorPart == null)
                Release250.CancelPastePreview(silent: true);
            OpenPartsPanel();
        }

        private void RefreshParts()
        {
            partResults = WorldEditParts.Filter(partCatalog, categories[categoryIndex], partQuery);
            partScroll = Vector2.zero;
        }

        private static void AdjustPlacementHeight(int direction)
        {
            Release250.PasteHeightOffset = Mathf.Clamp(Release250.PasteHeightOffset + direction * (ShiftHeld ? .1f : 1f), -50f, 50f);
        }

        private void DrawPartsPanel()
        {
            if (Event.current.type == EventType.MouseDown)
                EditingPartSearch = OverPartSearch(Input.mousePosition);
            if (EditingPartSearch && Event.current.type == EventType.KeyDown &&
                (Event.current.keyCode == KeyCode.Escape || Event.current.keyCode == KeyCode.Return))
            {
                bool choose = Event.current.keyCode == KeyCode.Return && partResults.Length == 1;
                EditingPartSearch = false;
                GUI.FocusControl(null);
                Event.current.Use();
                if (choose) TryEdit(() => StartPiece(partResults[0].Id));
            }
            if (!EditingPartSearch && GUI.GetNameOfFocusedControl() == "ValheavenPartSearch") GUI.FocusControl(null);
            GUI.SetNextControlName("ValheavenPartSearch");
            string query = GUI.TextField(SearchBox, partQuery, 80);
            if (focusPartSearch && Event.current.type == EventType.Repaint)
            {
                focusPartSearch = false;
                EditingPartSearch = true;
                GUI.FocusControl("ValheavenPartSearch");
            }
            if (partQuery.Length == 0 && !EditingPartSearch) GUI.Label(new Rect(SearchBox.x + 5, SearchBox.y + 2, SearchBox.width - 10, 22), "Search name or prefab ID  (/)", dockCaption);
            if (query != partQuery) { partQuery = query; RefreshParts(); }
            float w = RightPanel.width - 20, y = 75;
            int columns = Mathf.Max(2, (int)(w / 70)), index = 0;
            int categoryRows = Mathf.CeilToInt(categories.Length / (float)columns);
            float categoryHeight = Mathf.Min(3, categoryRows) * 28;
            bool categoryOverflow = categoryRows > 3;
            categoryScroll = GUI.BeginScrollView(new Rect(10, y, w, categoryHeight), categoryScroll,
                new Rect(0, 0, w - (categoryOverflow ? 18 : 0), categoryRows * 28));
            try
            {
                float categoryWidth = (w - (categoryOverflow ? 18 : 0)) / columns;
                foreach (var category in categories)
                {
                    string label = category == Piece.PieceCategory.All ? "All" :
                        categoryLabels.TryGetValue(category, out var name) ? name : category.ToString();
                    if (DockButton((index % columns) * categoryWidth, 28 * (index / columns), categoryWidth - 2, label, index == categoryIndex))
                    { categoryIndex = index; RefreshParts(); }
                    index++;
                }
            }
            finally { GUI.EndScrollView(); }
            y += categoryHeight + 4;
            float cell;
            float bottom = RightPanel.height - 149;
            var area = new Rect(10, y, w, Mathf.Max(36, bottom - y));
            columns = Mathf.Max(2, (int)((w - 18) / 36));
            cell = (w - 18) / columns;
            int rows = (partResults.Length + columns - 1) / columns;
            WorldEditParts.Entry hovered = null;
            partScroll = GUI.BeginScrollView(area, partScroll, new Rect(0, 0, w - 18, rows * cell));
            try
            {
                int start = Mathf.Max(0, (int)(partScroll.y / cell)) * columns;
                int end = Mathf.Min(partResults.Length, start + columns * (2 + Mathf.CeilToInt(area.height / cell)));
                for (int i = start; i < end; i++)
                {
                    var part = partResults[i];
                    var tile = new Rect(i % columns * cell, i / columns * cell, cell - 2, cell - 2);
                    if (tile.Contains(Event.current.mousePosition)) hovered = part;
                    bool picked = SurfaceButton(tile, part.Icon ? "" : part.Name, part.Id == Release250.CursorPart?.Prefab, true);
                    if (picked) TryEdit(() => StartPiece(part.Id));
                    if (!part.Icon) continue;
                    var tex = part.Icon.texture;
                    var r = part.Icon.rect;
                    var uv = UnityEngine.Sprites.DataUtility.GetOuterUV(part.Icon);
                    var icon = new Rect(tile.x + 4, tile.y + 4, tile.width - 8, tile.height - 8);
                    if (r.width > r.height) { float h = icon.width * r.height / r.width; icon.y += (icon.height - h) / 2; icon.height = h; }
                    else if (r.height > r.width) { float width = icon.height * r.width / r.height; icon.x += (icon.width - width) / 2; icon.width = width; }
                    GUI.DrawTextureWithTexCoords(icon, tex, new Rect(uv.x, uv.y, uv.z - uv.x, uv.w - uv.y));
                }
            }
            finally { GUI.EndScrollView(); }
            var selected = Release250.CursorPart;
            GUI.Label(new Rect(10, bottom + 2, w, 22), hovered?.Name ?? selected?.DisplayName ?? (rows == 0 ? "No matches" : $"{partResults.Length} parts"), dockText);
            GUI.Label(new Rect(10, bottom + 23, w, 19), hovered?.Id ?? selected?.Prefab ?? "", dockCaption);
            DrawPlacementControls(bottom + 44, true);
        }

        private void DrawPlacementControls(float y, bool part)
        {
            float w = RightPanel.width - 20;
            if (part && DockButton(10, y, w, Release250.CursorSnapped ? "Snapped" : "Snap to pieces", Release250.CursorPieceSnap))
                Release250.CursorPieceSnap = !Release250.CursorPieceSnap;
            if (part) y += 30;
            for (int i = 0; i < gridSizes.Length; i++)
            {
                float size = gridSizes[i];
                if (DockButton(10 + i * w / 4, y, w / 4 - 2, size == 0 ? "Free" : $"{size:0.#} m", size == Release250.CursorGrid))
                    Release250.CursorGrid = size;
            }
            y += 30;
            if (DockButton(10, y, 32, "−", enabled: Release250.CursorPasteActive)) AdjustPlacementHeight(-1);
            GUI.Label(new Rect(46, y + 3, w - 132, 24), HeightLabel, dockText);
            if (DockButton(w - 83, y, 32, "+", enabled: Release250.CursorPasteActive)) AdjustPlacementHeight(1);
            if (DockButton(w - 47, y, 57, $"{Release250.PasteYaw:0}° ↻", enabled: Release250.CursorPasteActive)) RotatePreview();
        }

        private static readonly float[] gridSizes = { 0f, .5f, 1f, 2f };
    }
}
