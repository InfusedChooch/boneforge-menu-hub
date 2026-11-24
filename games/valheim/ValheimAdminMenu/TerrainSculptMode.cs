using System;
using System.Linq;
using HarmonyLib;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal sealed partial class TerrainSculptMode
    {
        private float viewYaw;
        private Quaternion Heading => Quaternion.Euler(0, viewYaw, 0);
        private float? sampledHeight;
        private static readonly string[] Operations = { "raise", "lower", "smooth", "level", "paint", "terrace", "peak" };
        private static readonly string[] ToolKeys =
        {
            "world_edit.tool.raise", "world_edit.tool.lower", "world_edit.tool.smooth",
            "world_edit.tool.flatten", "world_edit.tool.paint"
        };

        private readonly Plugin app;
        private Player player;
        private Camera camera;
        private Vector3 focus, normalPosition;
        private Quaternion normalRotation;
        private bool hasNormalPose;
        private Vector3? target;
        private float altitude;
        private int tool;
        private string notice;
        private float noticeUntil;
        private int blockInputThroughFrame = -1;
        private string strokeOperation;
        private Vector3 strokePoint;
        private float nextStamp;
        private float flattenHeight;
        private (Vector3 Focus, float Altitude)? resumeView;

        internal TerrainSculptMode(Plugin app) { this.app = app; }
        internal bool Active { get; private set; }
        internal bool CanToggleWithShortcut => Application.isFocused && Player.m_localPlayer && !NativeUiIsOpen()
            && !Player.m_localPlayer.IsDead() && !Player.m_localPlayer.IsTeleporting();
        private static bool ControlHeld => Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
        private static bool ShiftHeld => Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift);
        internal bool BlocksInput => Active || Time.frameCount <= blockInputThroughFrame;

        internal void Start()
        {
            if (Active)
            {
                app.SetOpen(false);
                return;
            }
            app.RequireWorld();
            if (!GameCamera.instance || !GameCamera.instance.TryGetComponent(out Camera currentCamera))
                throw new InvalidOperationException(L.T("world_edit.camera_unavailable"));
            if (GameCamera.InFreeFly() || app.Phase.FreecamBuild)
                throw new InvalidOperationException(L.T("world_edit.freecam_active"));

            player = app.RequirePlayer();
            camera = currentCamera;
            focus = player.transform.position;
            altitude = 40f;
            if (resumeView.HasValue)
            {
                focus = resumeView.Value.Focus;
                altitude = resumeView.Value.Altitude;
                resumeView = null;
            }
            target = null;
            notice = null;
            if (Release250.PastePreviewActive) Release250.CancelPastePreview(silent: true);
            Active = true;
            app.SetOpen(false);
            Plugin.ReleaseCursor();
        }

        internal void StartBlueprint(string name)
        {
            var placement = BlueprintStore.ReadPlacement(name);
            Start();
            FinishStroke();
            ExitRegionTool();
            EndSelectionTool();
            ClosePartsPanel();
            Release250.BeginSavedBlueprint(placement.Pieces, placement.Terrain);
            blueprintBrowser = true;
            blueprintNames = BlueprintStore.List().Select(item => item.name).ToArray();
        }

        internal void StartPiece(string name)
        {
            app.RequireWorld();
            var prefab = string.IsNullOrWhiteSpace(name) ? null : ZNetScene.instance.GetPrefab(name.Trim());
            if (!WorldEditParts.CanPlace(prefab))
                throw new InvalidOperationException(L.T("world_edit.parts_unavailable"));
            Start();
            FinishStroke();
            ExitRegionTool();
            float height = Release250.CursorPart == null ? 0f : Release250.PasteHeightOffset;
            OpenPartsPanel();
            Release250.BeginCursorPiece(prefab.name, WorldEditParts.DisplayName(prefab.GetComponent<Piece>(), prefab.name));
            Release250.PasteHeightOffset = height;
        }

        internal void CancelOrStop()
        {
            if (helpOpen || historyOpen || layersOpen)
            {
                helpOpen = historyOpen = layersOpen = false;
                return;
            }
            if (selectionPreview) { CancelTransform(); return; }
            if (editTool != EditTool.None) { EndSelectionTool(); return; }
            if (Release250.CursorPasteActive) CancelBlueprint();
            else if (partsOpen) ClosePartsPanel();
            else if (CancelRegionTool()) return;
            else Stop();
        }

        internal void ToggleEditor()
        {
            if (Active) Stop();
            else Start();
        }

        private void TestHere() => TestAt(target ?? focus);

        private void TestAt(Vector3 point)
        {
            FinishStroke();
            if (!Heightmap.GetHeight(point, out float ground))
                throw new InvalidOperationException("Aim at loaded ground before testing here.");
            app.Features.Teleport(new Vector3(point.x, ground + .2f, point.z));
            resumeView = (focus, altitude);
            Stop();
            var key = HotkeyRegistry.WorldEditor?.Key ?? KeyCode.None;
            app.Report(key == KeyCode.None ? "Testing in the Viking view. Return through the World Edit tab."
                : $"Testing in the Viking view. Press {key} to return to World Edit.");
        }

        internal void ClearScene()
        {
            Stop();
            resumeView = null;
            ClearRegions();
            partCatalog = partResults = null;
            partQuery = "";
            categoryIndex = 0;
            editGroups.Clear();
            EditorPieceRef.Clear();
            sampledHeight = null;
        }

        internal void Stop()
        {
            if (!Active) return;
            FinishStroke();
            dragStart = null;
            panPointer = null;
            dockPointerCaptured = false;
            partsOpen = historyOpen = EditingPartSearch = focusPartSearch = false;
            RestoreLayers();
            EndSelectionTool();
            hiddenUi = helpOpen = layersOpen = false;
            resizing = 0;
            Active = false;
            if (Release250.CursorPasteActive) Release250.CancelPastePreview(silent: true);
            target = null;
            blockInputThroughFrame = Time.frameCount;
            RestoreCamera();
            camera = null;
            player = null;
            if (GameCamera.instance) GameCamera.instance.UpdateMouseCapture();
        }

        internal void RestoreCamera()
        {
            if (!hasNormalPose) return;
            hasNormalPose = false;
            if (camera) camera.transform.SetPositionAndRotation(normalPosition, normalRotation);
        }

        internal void UpdateCamera(GameCamera view)
        {
            if (!Active) return;
            if (!player || player != Player.m_localPlayer || player.IsDead() || player.IsTeleporting()
                || !camera || camera.gameObject != view.gameObject || GameCamera.InFreeFly() || app.Phase.FreecamBuild)
            {
                Stop();
                return;
            }

            normalPosition = camera.transform.position;
            normalRotation = camera.transform.rotation;
            hasNormalPose = true;
            bool inputAvailable = Application.isFocused && !app.Open && !app.MenuJustClosed && !NativeUiIsOpen();
            Vector2 pointer = Input.mousePosition;
            if (!inputAvailable || !Input.GetMouseButton(0)) resizing = 0;
            bool overDock = IsOverDock(pointer);
            if (EditingPartSearch && Input.GetMouseButtonDown(0) && !OverPartSearch(pointer))
                EditingPartSearch = false;
            if (inputAvailable && !EditingPartSearch)
            {
                if (Input.GetKeyDown(KeyCode.H)) { hiddenUi = !hiddenUi; helpOpen = false; }
                if (Input.GetKeyDown(KeyCode.F1)) { helpOpen = !helpOpen; layersOpen = historyOpen = hiddenUi = false; }
            }
            TickLayers();
            if (EditingPartSearch || helpOpen) inputAvailable = false;
            bool dockGesture = ReadDockPointer(overDock, inputAvailable);
            bool panGesture = inputAvailable && ReadPanGesture(pointer, Input.GetMouseButtonDown(2),
                Input.GetMouseButton(2), overDock || dockGesture);
            if (inputAvailable) ReadNavigation(!overDock && !dockGesture && !panGesture);
            else panPointer = null;

            camera.transform.SetPositionAndRotation(focus + Vector3.up * altitude, Heading * Quaternion.Euler(90f, 0f, 0f));
            target = null;
            if (!inputAvailable || dockGesture || panGesture)
            {
                FinishStroke();
                dragStart = null;
                boxStart = null;
                Release250.UpdateCursorPaste(null);
                return;
            }
            HandlePointer(pointer);
        }

        private static bool NativeUiIsOpen()
        {
            return Console.IsVisible() || Release250.ChatHasFocus() || TextInput.IsVisible()
                || InventoryGui.IsVisible() || StoreGui.IsVisible() || global::Menu.IsVisible() || Minimap.IsOpen()
                || Hud.IsPieceSelectionVisible() || (TextViewer.instance && TextViewer.instance.IsVisible());
        }

        private void ReadNavigation(bool zoomInViewport)
        {
            var direction = new Vector2(Axis(KeyCode.D, KeyCode.A), Axis(KeyCode.W, KeyCode.S));
            if (ControlHeld) direction = Vector2.zero;
            var movement = new Vector3(direction.x, 0f, direction.y).normalized * altitude * Time.unscaledDeltaTime;
            viewYaw = Mathf.Repeat(viewYaw + Axis(KeyCode.E, KeyCode.Q) * 90f * Time.unscaledDeltaTime, 360f);
            MoveFocus(Heading * movement);
            float wheel = Input.mouseScrollDelta.y;
            if (zoomInViewport && wheel != 0f)
            {
                if (BrushActive && ControlHeld) app.World.BrushRadius = Mathf.Clamp(app.World.BrushRadius + wheel, 1f, 50f);
                else if (BrushActive && ShiftHeld) AdjustStrength(wheel);
                else altitude = Mathf.Clamp(altitude * Mathf.Pow(.85f, wheel), 12f, 100f);
            }

            if (Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl))
            {
                if (Input.GetKeyDown(KeyCode.Z) || Input.GetKeyDown(KeyCode.Y))
                    ReplayHistory(Input.GetKeyDown(KeyCode.Z));
            }
            if (strokeOperation == null)
                for (int i = 0; i < Operations.Length; i++)
                    if (Input.GetKeyDown((KeyCode)((int)KeyCode.Alpha1 + i))) SelectBrush(i);
        }

        private void MoveFocus(Vector3 movement)
        {
            var next = focus + movement;
            if (Heightmap.GetHeight(next, out float ground))
            {
                next.y = Mathf.MoveTowards(focus.y, ground, 80f * Time.unscaledDeltaTime);
                focus = next;
            }
        }

        private static int Axis(KeyCode positive, KeyCode negative) =>
            (Input.GetKey(positive) ? 1 : 0) - (Input.GetKey(negative) ? 1 : 0);

        private Vector3? FindTarget(Vector2 pointer)
        {
            if (!camera || !camera.pixelRect.Contains(pointer)) return null;
            if (IsOverDock(pointer)) return null;
            var ray = camera.ScreenPointToRay(pointer);
            if (!Physics.Raycast(ray, out var hit, 250f, LayerMask.GetMask("terrain"), QueryTriggerInteraction.Ignore))
                return null;
            if (!Heightmap.FindHeightmap(hit.point)) return null;
            if (Release250.CursorPart != null && Release250.CursorPieceSnap &&
                Physics.Raycast(ray, out var surface, hit.distance, LayerMask.GetMask("piece"), QueryTriggerInteraction.Ignore))
                return surface.point;
            return hit.point;
        }

        private void HandlePointer(Vector2 pointer)
        {
            target = FindTarget(pointer);
            if (partsOpen && !hiddenUi && !rightClosed && Input.GetKeyDown(KeyCode.Slash))
            {
                focusPartSearch = true;
                return;
            }
            if (Input.GetKeyDown(KeyCode.P))
            {
                FinishStroke();
                TogglePartsPanel();
                return;
            }
            if (Input.GetKeyDown(KeyCode.T))
            {
                TryEdit(TestHere, showResult: true);
                return;
            }
            if (Input.GetKeyDown(KeyCode.B))
            {
                TryEdit(OpenClipboardPreview);
                return;
            }
            if (Release250.CursorPasteActive)
            {
                if (Input.GetMouseButtonDown(1))
                {
                    CancelBlueprint();
                    return;
                }
                if (Input.GetKeyDown(KeyCode.R)) RotatePreview();
                if (Release250.CursorArea == null)
                {
                    if (Input.GetKeyDown(KeyCode.PageUp)) AdjustPlacementHeight(1);
                    if (Input.GetKeyDown(KeyCode.PageDown)) AdjustPlacementHeight(-1);
                }
                Release250.UpdateCursorPaste(target);
                if (target.HasValue && Input.GetMouseButtonDown(0))
                    TryEdit(Release250.ConfirmPaste, showResult: true);
                return;
            }

            if (HandleSelection(pointer) || partsOpen || blueprintBrowser) return;
            if (HandleRegionPointer()) return;
            HandleTerrainStroke(Input.GetMouseButtonDown(0), Input.GetMouseButton(0));
        }

        private void HandleTerrainStroke(bool pressed, bool held)
        {
            if (!target.HasValue)
            {
                FinishStroke();
                return;
            }
            if (pressed)
            {
                if (tool == 3 && (Input.GetKey(KeyCode.LeftAlt) || Input.GetKey(KeyCode.RightAlt)))
                {
                    sampledHeight = target.Value.y;
                    ShowNotice($"Flatten height sampled at {sampledHeight:0.0} m.");
                    return;
                }
                app.World.BeginTerrainEdit();
                strokeOperation = BrushOperation(tool, ControlHeld, ShiftHeld);
                flattenHeight = sampledHeight ?? target.Value.y;
                Stamp(target.Value);
                nextStamp = Time.unscaledTime + .07f;
                return;
            }
            if (strokeOperation == null) return;
            if (held && Time.unscaledTime < nextStamp) return;
            Vector3 hit = target.Value;
            var delta = new Vector2(hit.x - strokePoint.x, hit.z - strokePoint.z);
            float spacing = Mathf.Clamp(app.World.BrushRadius * .35f, .5f, 4f);
            if (delta.magnitude >= spacing)
            {
                nextStamp = Time.unscaledTime + .07f;
                int count = Mathf.FloorToInt(delta.magnitude / spacing);
                int budget = strokeOperation == "level" ? 1 : 3;
                Vector2 step = delta.normalized * spacing;
                for (int i = 0; i < Mathf.Min(budget, count) && strokeOperation != null; i++)
                {
                    var point = strokePoint + new Vector3(step.x, 0f, step.y);
                    if (!Heightmap.GetHeight(point, out float height)) { FinishStroke(); break; }
                    point.y = height;
                    Stamp(point);
                }
                if (!held && strokeOperation != null && count > budget) Stamp(hit);
            }
            if (!held) FinishStroke();
        }

        internal static string BrushOperation(int index, bool inverse, bool smooth)
        {
            if (smooth) return "smooth";
            if (inverse && index < 2) return Operations[1 - index];
            return Operations[index];
        }

        private void AdjustStrength(float ticks)
        {
            if (tool == 4) app.World.PaintStrength = Mathf.Clamp(app.World.PaintStrength + ticks * .1f, .1f, 1f);
            else if (tool < 2 || tool >= 5) app.World.BrushAmount = Mathf.Clamp(app.World.BrushAmount + ticks * .25f, .05f, 8f);
        }

        private void Stamp(Vector3 point)
        {
            strokePoint = point;
            if (strokeOperation == "level") point.y = flattenHeight;
            try { app.World.SculptTerrain(strokeOperation, point); }
            catch (InvalidOperationException error)
            {
                FinishStroke();
                app.Report(error.Message);
                ShowNotice(error.Message);
            }
        }

        private void FinishStroke()
        {
            if (strokeOperation == null) return;
            string label = WorldTools.BrushLabel(strokeOperation);
            strokeOperation = null;
            app.EditHistory.Record(label, app.World.FinishTerrainEdit());
        }

        private void CancelBlueprint()
        {
            Release250.CancelPastePreview();
            ShowNotice(app.Status);
        }

        private void TryEdit(Action action, bool showResult = false)
        {
            try
            {
                action();
                if (showResult) ShowNotice(app.Status);
            }
            catch (InvalidOperationException error)
            {
                app.Report(error.Message);
                ShowNotice(error.Message);
            }
        }

        private void ShowNotice(string text)
        {
            notice = text;
            noticeUntil = Time.unscaledTime + 3f;
        }

        private bool HasNotice => notice != null && Time.unscaledTime < noticeUntil;
        internal void Draw()
        {
            if (!Active || !camera || app.Open || NativeUiIsOpen()) return;
            if (Event.current.type == EventType.Repaint) DrawWorldOverlay();
            if (!hiddenUi) DrawDock();
        }

        private void DrawWorldOverlay()
        {
            bool placing = Release250.CursorPasteActive;
            var oldColor = GUI.color;
            if (DrawSelection() || DrawRegions()) return;
            if (placing || partsOpen || blueprintBrowser || !target.HasValue) return;
            try
            {
                GUI.color = new Color(.98f, .75f, .29f);
                var center = target.Value;
                float radius = Mathf.Clamp(app.World.BrushRadius, 1f, 50f);
                int segments = app.World.Square ? 4 : 32;
                float step = 2f * Mathf.PI / segments;
                float phase = app.World.Square ? Mathf.PI / 4f : 0f;
                if (app.World.Square) radius *= Mathf.Sqrt(2f);
                for (int i = 0; i < segments; i++)
                    Release250.DrawScreenLine(camera, Rim(center, radius, phase + i * step), Rim(center, radius, phase + (i + 1) * step));
            }
            finally { GUI.color = oldColor; }
        }

        private static Vector3 Rim(Vector3 center, float radius, float angle) =>
            center + new Vector3(Mathf.Cos(angle) * radius, .1f, Mathf.Sin(angle) * radius);
    }

    [HarmonyPatch(typeof(GameCamera), "LateUpdate")]
    internal static class TerrainSculptCameraPatch
    {
        private static void Prefix() => Plugin.Instance?.Sculpt?.RestoreCamera();

        private static void Postfix(GameCamera __instance)
        {
            var app = Plugin.Instance;
            if (app?.Sculpt?.Active != true) return;
            try { app.Sculpt.UpdateCamera(__instance); }
            catch (Exception error)
            {
                app.Sculpt.Stop();
                AppLog.Error("World Edit", "Sculpt mode stopped. " + error);
                app.Report(error.GetBaseException().Message);
            }
        }
    }
}
