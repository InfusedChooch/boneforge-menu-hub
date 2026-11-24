using System;
using System.Linq;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal sealed partial class TerrainSculptMode
    {
        private float leftWidth = 152f, rightWidth = 248f;
        private bool leftClosed, rightClosed, hiddenUi, helpOpen, layersOpen;
        private int resizing;
        private float UiScale => SculptViewport.DockScale(Screen.width, Screen.height);
        private float UiWidth => Screen.width / UiScale;
        private float UiHeight => Screen.height / UiScale;
        private Rect LeftPanel => SculptViewport.Side(false, UiWidth, UiHeight, leftWidth, leftClosed);
        private Rect RightPanel => SculptViewport.Side(true, UiWidth, UiHeight, rightWidth, rightClosed);
        private Rect Popup => new Rect(LeftPanel.xMax + 6, 44, Mathf.Min(300, RightPanel.x - LeftPanel.xMax - 12), helpOpen ? 268 : layersOpen ? 153 : 220);
        private bool IsOverDock(Vector2 pointer)
        {
            if (hiddenUi) return false;
            var p = ToGuiPoint(pointer);
            return resizing != 0 || p.y < 42 || p.y >= UiHeight - 30 || LeftPanel.Contains(p) || RightPanel.Contains(p)
                || ((historyOpen || layersOpen || helpOpen) && Popup.Contains(p));
        }

        private void DrawDock()
        {
            EnsureDockStyles();
            var matrix = GUI.matrix;
            GUI.matrix = matrix * Matrix4x4.Scale(new Vector3(UiScale, UiScale, 1));
            try
            {
                Panel(new Rect(0, 0, UiWidth, 40));
                GUI.Label(new Rect(12, 4, 145, 32), "World Edit", dockTitle);
                if (DockButton(153, 6, 70, "Undo", enabled: app.EditHistory.UndoCount > 0)) ReplayHistory(true);
                if (DockButton(225, 6, 63, "Redo", enabled: app.EditHistory.RedoCount > 0)) ReplayHistory(false);
                if (DockButton(294, 6, 83, "History  " + app.EditHistory.UndoCount, historyOpen))
                {
                    historyOpen = !historyOpen;
                    layersOpen = helpOpen = false;
                    historyScroll = Vector2.zero;
                }
                if (DockButton(379, 6, 64, "Layers", layersOpen))
                {
                    layersOpen = !layersOpen;
                    historyOpen = helpOpen = false;
                }
                if (DockButton(UiWidth - 268, 6, 70, "Center")) CenterCamera();
                if (DockButton(UiWidth - 195, 6, 80, "Test here")) TryEdit(() => TestAt(focus), true);
                if (DockButton(UiWidth - 112, 6, 49, "Help", helpOpen))
                {
                    helpOpen = !helpOpen;
                    historyOpen = layersOpen = false;
                }
                if (DockButton(UiWidth - 61, 6, 53, "Exit")) { Stop(); return; }
                DrawSide(false);
                DrawSide(true);
                if (historyOpen || helpOpen || layersOpen) DrawPopup();
                var footer = new Rect(0, UiHeight - 28, UiWidth, 28);
                Panel(footer);
                GUI.Label(new Rect(12, footer.y + 3, UiWidth - 24, 22), HasNotice ? notice : Hints(), dockCaption);
            }
            finally { GUI.matrix = matrix; }
        }

        private static void Panel(Rect r)
        {
            Fill(r, DockPanel);
            Fill(new Rect(r.x, r.y, r.width, 1), DockGold);
        }

        private void DrawSide(bool right)
        {
            var r = right ? RightPanel : LeftPanel;
            Panel(r);
            GUI.BeginGroup(r);
            try
            {
                bool collapsed = right ? rightClosed : leftClosed;
                if (DockButton(right ? 1 : r.width - 25, 5, 24, right == collapsed ? "‹" : "›"))
                {
                    if (right) { rightClosed = !rightClosed; EditingPartSearch = focusPartSearch = false; }
                    else leftClosed = !leftClosed;
                    return;
                }
                if (collapsed) return;
                if (right)
                {
                    GUI.Label(new Rect(34, 5, r.width - 40, 32), InspectorTitle(), dockTitle);
                    if (partsOpen) DrawPartsPanel(); else DrawOptions();
                }
                else DrawRail();
            }
            finally { GUI.EndGroup(); }
            if (!(right ? rightClosed : leftClosed)) ResizeSide(r, right);
        }

        private void ResizeSide(Rect panel, bool right)
        {
            var edge = new Rect(right ? panel.x : panel.xMax - 5, panel.y + 36, 5, panel.height - 36);
            Fill(edge, DockLine);
            var e = Event.current;
            int side = right ? 1 : -1;
            if (e.type == EventType.MouseDown && e.button == 0 && edge.Contains(e.mousePosition))
            {
                resizing = side;
                dockPointerCaptured = true;
                e.Use();
            }
            if (resizing != side) return;
            if (e.type == EventType.MouseDrag)
            {
                if (right) rightWidth = Mathf.Clamp(UiWidth - e.mousePosition.x, 224, UiWidth * .37f);
                else leftWidth = Mathf.Clamp(e.mousePosition.x, 132, UiWidth * .23f);
                e.Use();
            }
            if (e.type == EventType.MouseUp) { resizing = 0; e.Use(); }
        }

        private void DrawRail()
        {
            float w = LeftPanel.width - 20, y = 14;
            void Heading(string name) { GUI.Label(new Rect(10, y, w, 22), name, dockCaption); y += 22; }
            void Tool(string name, bool selected, Action choose)
            {
                if (DockButton(9, y, w, name, selected)) { rightClosed = false; choose(); }
                y += 30;
            }
            Heading("EDIT");
            Tool("Select", editTool == EditTool.Select, () => ChooseEditTool(EditTool.Select));
            Tool("Pipette", editTool == EditTool.Pipette, () => ChooseEditTool(EditTool.Pipette));
            y += 8; Heading("TERRAIN");
            Tool("Shape ground", BrushActive && tool != 4, () => SelectBrush(tool == 4 ? 0 : tool));
            Tool("Paint ground", BrushActive && tool == 4, () => SelectBrush(4));
            Tool("Hills", regionTool == RegionTool.Landform, () => SelectRegion(RegionTool.Landform));
            Tool("Area copy", regionTool == RegionTool.Area, () => SelectRegion(RegionTool.Area));
            y += 8; Heading("BUILD");
            Tool("Build pieces", partsOpen, () => { if (!partsOpen) TogglePartsPanel(); });
            Tool("Blueprints", BlueprintTool, OpenBlueprintInspector);
        }

        private bool BrushActive => editTool == EditTool.None && !partsOpen && !blueprintBrowser
            && !Release250.CursorPasteActive && regionTool == RegionTool.None;

        private bool blueprintBrowser;
        private string[] blueprintNames = Array.Empty<string>();
        private Vector2 blueprintScroll;
        private bool BlueprintTool => blueprintBrowser || (Release250.CursorPasteActive && Release250.CursorArea == null && Release250.CursorPart == null);
        private void OpenBlueprintInspector()
        {
            SelectBrush(tool);
            blueprintBrowser = true;
            TryEdit(() => blueprintNames = BlueprintStore.List().Select(b => b.name).ToArray());
        }
        private string InspectorTitle()
        {
            if (partsOpen) return "Build pieces";
            if (BlueprintTool) return "Blueprints";
            if (editTool != EditTool.None) return editTool.ToString();
            if (regionTool == RegionTool.Area || Release250.CursorArea != null) return "Area copy";
            if (regionTool == RegionTool.Landform) return "Hills";
            return tool == 4 ? "Paint ground" : "Shape ground";
        }
        private string Hints()
        {
            if (selectionPreview) return "Click ground to confirm    R rotate    PgUp / PgDn height    Esc cancel";
            if (partsOpen && Release250.CursorPart == null) return "/ search parts    Choose a piece to place";
            if (partsOpen) return "/ search    R rotate    PgUp / PgDn height    Shift fine    Click to place";
            if (BlueprintTool) return Release250.CursorPasteActive
                ? "R rotate    PgUp / PgDn height    Click to place    Esc cancel"
                : "Choose a saved blueprint    B previews the structure clipboard";
            if (editTool == EditTool.Select) return "Click or drag to select    Shift add    M move    R rotate    Ctrl+D duplicate    Del delete";
            if (editTool == EditTool.Pipette) return "Click a built piece to pick its prefab and rotation    Esc cancel";
            if (regionTool != RegionTool.None) return RegionTitle() + "    •    T test here";
            return "Ctrl+wheel radius    Shift+wheel strength    Ctrl invert    Shift smooth    Q / E orbit    H hide    F1 help";
        }

        private void DrawOptions()
        {
            float w = RightPanel.width - 20;
            if (editTool != EditTool.None) { DrawSelectionControls(w); return; }
            if (BlueprintTool)
            {
                if (Release250.CursorPasteActive) DrawPlacementControls(48, false);
                float top = Release250.CursorPasteActive ? 120 : 48;
                blueprintScroll = GUI.BeginScrollView(new Rect(10, top, w, RightPanel.height - top - 12), blueprintScroll,
                    new Rect(0, 0, w - 18, Mathf.Max(34, blueprintNames.Length * 30)));
                try
                {
                    for (int i = 0; i < blueprintNames.Length; i++)
                        if (DockButton(0, i * 30, w - 18, blueprintNames[i])) { string name = blueprintNames[i]; TryEdit(() => StartBlueprint(name)); }
                    if (blueprintNames.Length == 0) GUI.Label(new Rect(2, 2, w - 20, 32), "No saved blueprints", dockCaption);
                }
                finally { GUI.EndScrollView(); }
                return;
            }
            if (regionTool != RegionTool.None || Release250.CursorArea != null)
            {
                GUI.Label(new Rect(10, 49, w, 54), RegionTitle(), dockText);
                if (regionTool == RegionTool.Landform)
                {
                    if (DockButton(10, 112, w / 2 - 2, "−2 m", enabled: selectedHill != null)) TryEdit(() => ResizeHill(-2), true);
                    if (DockButton(12 + w / 2, 112, w / 2 - 2, "+2 m", enabled: selectedHill != null)) TryEdit(() => ResizeHill(2), true);
                    if (DockButton(10, 146, w, "Remove hill", enabled: selectedHill != null)) TryEdit(() => EditHill(selectedHill, null, "remove hill"), true);
                }
                else
                {
                    if (DockButton(10, 112, w, "Copy selection", enabled: areaSelection.HasValue)) TryEdit(CopyArea, true);
                    if (DockButton(10, 146, w, "Preview paste", enabled: copiedArea != null)) TryEdit(OpenAreaPreview);
                }
                return;
            }
            float y = 52;
            if (tool == 4)
            {
                for (int i = 0; i < 5; i++)
                {
                    if (DockButton(10, y, w, WorldTools.PaintModeLabel(i), app.World.PaintMode == i))
                        app.World.PaintMode = i;
                    y += 29;
                }
            }
            else
            {
                int j = 0;
                for (int i = 0; i < Operations.Length; i++)
                {
                    if (i == 4) continue;
                    string name = i < 5 ? L.T(ToolKeys[i]) : i == 5 ? "Terrace" : "Peak";
                    if (DockButton(10 + j % 2 * w / 2, y + j / 2 * 31, w / 2 - 2, name, tool == i)) SelectBrush(i);
                    j++;
                }
                y += 100;
            }
            if (DockButton(10, y, w / 2 - 2, "Round", !app.World.Square)) app.World.Square = false;
            if (DockButton(10 + w / 2, y, w / 2 - 2, "Square", app.World.Square)) app.World.Square = true;
            y += 36;
            GUI.Label(new Rect(10, y, w, 22), $"Radius    {app.World.BrushRadius:0.#} m", dockText);
            app.World.BrushRadius = Mathf.Round(GUI.HorizontalSlider(new Rect(10, y + 25, w, 18), app.World.BrushRadius, 1, 50));
            y += 57;
            if (tool < 2 || tool >= 4)
            {
                bool paint = tool == 4;
                float value = paint ? app.World.PaintStrength : app.World.BrushAmount;
                GUI.Label(new Rect(10, y, w, 22), paint ? $"Paint strength    {value:P0}" : $"Height step    {value:0.##} m", dockText);
                float result = GUI.HorizontalSlider(new Rect(10, y + 25, w, 18), value, paint ? .1f : .05f, paint ? 1 : 8);
                if (paint) app.World.PaintStrength = result; else app.World.BrushAmount = result;
            }
            if (tool == 3 && DockButton(10, y, w, sampledHeight.HasValue ? $"Clear sampled height {sampledHeight:0.0} m" : "Alt+click to sample height", enabled: sampledHeight.HasValue)) sampledHeight = null;
        }

        private void DrawPopup()
        {
            var r = Popup;
            Panel(r);
            GUI.BeginGroup(r);
            try
            {
                GUI.Label(new Rect(10, 5, r.width - 46, 30), helpOpen ? "Controls" : layersOpen ? "Layers" : "Edit history", dockTitle);
                if (DockButton(r.width - 34, 5, 28, "×")) { historyOpen = layersOpen = helpOpen = false; return; }
                if (helpOpen)
                    GUI.Label(new Rect(12, 45, r.width - 24, 210), "WASD or middle-drag    Pan\nWheel    Zoom\nQ / E    Rotate camera\nH    Hide or show interface\nP    Parts     /    Search\nB    Clipboard blueprint\nG    Area     L    Hills\nCtrl+Z / Ctrl+Y    Undo / redo\nT    Test here     Esc    Cancel", dockText);
                else if (layersOpen) DrawLayers(r.width);
                else
                {
                    var h = app.EditHistory;
                    int last = h.UndoCount + h.RedoCount;
                    historyScroll = GUI.BeginScrollView(new Rect(8, 42, r.width - 16, r.height - 50), historyScroll, new Rect(0, 0, r.width - 36, 30 * (last + 1)));
                    try
                    {
                        for (int pos = last; pos >= 0; pos--)
                        {
                            int index = pos;
                            if (DockButton(0, (last - pos) * 30, r.width - 36, $"{pos}   {h.LabelAt(pos)}", pos == h.UndoCount))
                                TryEdit(() => { FinishStroke(); h.GoTo(index); }, true);
                        }
                    }
                    finally { GUI.EndScrollView(); }
                }
            }
            finally { GUI.EndGroup(); }
        }
    }
}
