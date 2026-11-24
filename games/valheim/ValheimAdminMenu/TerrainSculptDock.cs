using System;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal static class SculptViewport
    {
        internal static float DockScale(int width, int height) =>
            Mathf.Max(.25f, Mathf.Min(1.25f, width / 960f, height / 560f));

        internal static Rect Side(bool right, float width, float height, float expandedWidth, bool collapsed)
        {
            float w = collapsed ? 26f : Mathf.Min(expandedWidth, width * (right ? .37f : .23f));
            return new Rect(right ? width - w : 0f, 42f, w, Mathf.Max(1, height - 72f));
        }

        internal static Vector3 PanMovement(Vector2 pixels, float verticalSpan, int pixelHeight) =>
            new Vector3(-pixels.x, 0f, -pixels.y) * (verticalSpan / Mathf.Max(1, pixelHeight));
    }

    internal sealed partial class TerrainSculptMode
    {
        private static readonly Color DockPanel = new Color(.034f, .032f, .029f, .985f);
        private static readonly Color DockLine = new Color(.38f, .32f, .23f);
        private static readonly Color DockGold = new Color(.95f, .76f, .44f);
        private Vector2? panPointer;
        private bool dockPointerCaptured;
        private GUIStyle dockTitle, dockText, dockCaption, dockButton;

        private bool ReadDockPointer(bool overDock, bool inputAvailable)
        {
            if (!inputAvailable) { dockPointerCaptured = false; return false; }
            if (Input.GetMouseButtonDown(0)) dockPointerCaptured = overDock;
            bool captured = dockPointerCaptured;
            if (!Input.GetMouseButton(0)) dockPointerCaptured = false;
            return captured;
        }

        private bool ReadPanGesture(Vector2 pointer, bool pressed, bool held, bool blocked)
        {
            if (pressed && !blocked && camera.pixelRect.Contains(pointer))
            {
                FinishStroke();
                dragStart = null;
                panPointer = pointer;
            }
            if (!panPointer.HasValue) return false;
            Vector2 pixels = pointer - panPointer.Value;
            panPointer = held ? (Vector2?)pointer : null;
            float span = camera.orthographic ? camera.orthographicSize * 2f
                : 2f * altitude * Mathf.Tan(camera.fieldOfView * Mathf.Deg2Rad / 2f);
            MoveFocus(Heading * SculptViewport.PanMovement(pixels, span, camera.pixelHeight));
            return true;
        }

        private void SelectBrush(int index)
        {
            FinishStroke();
            if (Release250.CursorPasteActive) Release250.CancelPastePreview(silent: true);
            ExitRegionTool();
            ClosePartsPanel();
            EndSelectionTool();
            tool = index;
        }

        private void SelectRegion(RegionTool selection)
        {
            FinishStroke();
            if (Release250.CursorPasteActive) Release250.CancelPastePreview(silent: true);
            dragStart = null;
            ClosePartsPanel();
            EndSelectionTool();
            regionTool = selection;
        }

        private void ReplayHistory(bool undo)
        {
            FinishStroke();
            TryEdit(undo ? (Action)app.EditHistory.Undo : app.EditHistory.Redo, showResult: true);
        }

        private static void RotatePreview() =>
            Release250.PasteYaw = Mathf.DeltaAngle(0f, Release250.PasteYaw + 15f);

        private void CenterCamera()
        {
            if (player) focus = player.transform.position;
        }

        private void OpenClipboardPreview()
        {
            FinishStroke();
            Release250.BeginCursorPaste();
            ExitRegionTool();
            ClosePartsPanel();
            EndSelectionTool();
            Release250.UpdateCursorPaste(target);
        }

        private void EnsureDockStyles()
        {
            if (dockTitle != null) return;
            dockTitle = new GUIStyle(GUI.skin.label) { fontSize = 22, fontStyle = FontStyle.Bold };
            dockTitle.normal.textColor = DockGold;
            dockText = new GUIStyle(GUI.skin.label) { fontSize = 15, wordWrap = true };
            dockText.normal.textColor = new Color(.96f, .92f, .83f);
            dockCaption = new GUIStyle(dockText) { fontSize = 12 };
            dockCaption.normal.textColor = new Color(.8f, .77f, .69f);
            dockButton = new GUIStyle(dockText)
            {
                fontSize = 13,
                alignment = TextAnchor.MiddleCenter,
                wordWrap = false,
                clipping = TextClipping.Clip,
                padding = new RectOffset(3, 3, 1, 1)
            };
        }

        private bool DockButton(float x, float y, float width, string label, bool selected = false, bool enabled = true)
        {
            return SurfaceButton(new Rect(x, y, width, 27f), label, selected, enabled);
        }

        private bool SurfaceButton(Rect rect, string label, bool selected, bool enabled)
        {
            bool hover = enabled && rect.Contains(Event.current.mousePosition);
            if (Event.current.type == EventType.Repaint)
            {
                Fill(rect, selected ? new Color(.20f, .135f, .059f) : hover ? new Color(.14f, .12f, .088f) : new Color(.07f, .065f, .055f));
                Fill(new Rect(rect.x, rect.yMax - 1, rect.width, 1), selected ? DockGold : DockLine);
                if (selected) Fill(new Rect(rect.x, rect.y, 2, rect.height), DockGold);
            }
            bool previous = GUI.enabled;
            GUI.enabled = previous && enabled;
            int size = dockButton.fontSize;
            try
            {
                if (label.Length > 0)
                {
                    float natural = dockButton.CalcSize(new GUIContent(label)).x;
                    if (natural > rect.width) dockButton.fontSize = Mathf.Max(10, Mathf.FloorToInt(size * rect.width / natural));
                }
                return GUI.Button(rect, label, dockButton);
            }
            finally { GUI.enabled = previous; dockButton.fontSize = size; }
        }

        private static void Fill(Rect rect, Color color)
        {
            var oldColor = GUI.color;
            GUI.color = color;
            GUI.DrawTexture(rect, Texture2D.whiteTexture);
            GUI.color = oldColor;
        }
    }
}
