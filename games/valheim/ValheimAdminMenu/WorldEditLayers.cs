using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal sealed partial class TerrainSculptMode
    {
        private static readonly string[] layerNames = { "Build pieces", "Trees", "Rocks" };
        private readonly bool[] hiddenLayers = new bool[3], lockedLayers = new bool[3];
        private readonly Dictionary<Renderer, int> hiddenRenderers = new Dictionary<Renderer, int>();
        private float nextLayerScan;

        private static int LayerOf(ZNetView view)
        {
            if (view.GetComponent<TreeBase>() || view.GetComponent<TreeLog>()) return 1;
            if (view.GetComponent<MineRock>() || view.GetComponent<MineRock5>()) return 2;
            return view.GetComponent<Piece>() ? 0 : -1;
        }
        private bool BlockedLayer(ZNetView view)
        {
            int index = LayerOf(view);
            return index >= 0 && (hiddenLayers[index] || lockedLayers[index]);
        }
        private void SetLayer(int index, bool hide, bool locked)
        {
            hiddenLayers[index] = hide; lockedLayers[index] = locked;
            if (!hide)
                foreach (var pair in hiddenRenderers.Where(p => p.Value == index).ToArray())
                { if (pair.Key) pair.Key.forceRenderingOff = false; hiddenRenderers.Remove(pair.Key); }
            if (hide || locked)
            {
                if (selectionPreview) CancelTransform();
                selected.RemoveWhere(h => !h.Instance || BlockedLayer(h.Instance.GetComponent<ZNetView>()));
            }
            nextLayerScan = 0; TickLayers();
        }
        private void TickLayers()
        {
            if (Time.unscaledTime < nextLayerScan || !hiddenLayers.Any(v => v)) return;
            nextLayerScan = Time.unscaledTime + 1f;
            foreach (var v in WorldTools.Loaded<ZNetView>())
            {
                if (!v.IsValid()) continue;
                int index = LayerOf(v);
                if (index < 0 || !hiddenLayers[index]) continue;
                foreach (var r in v.GetComponentsInChildren<Renderer>(true))
                    if (!r.forceRenderingOff && r.GetComponentInParent<ZNetView>() == v)
                    { r.forceRenderingOff = true; hiddenRenderers[r] = index; }
            }
            foreach (var dead in hiddenRenderers.Keys.Where(r => !r).ToArray()) hiddenRenderers.Remove(dead);
        }
        private void RestoreLayers()
        {
            foreach (var r in hiddenRenderers.Keys) if (r) r.forceRenderingOff = false;
            hiddenRenderers.Clear();
            System.Array.Clear(hiddenLayers, 0, 3); System.Array.Clear(lockedLayers, 0, 3); nextLayerScan = 0;
        }
        private void DrawLayers(float w)
        {
            for (int i = 0; i < 3; i++)
            {
                float y = 43 + i * 33;
                GUI.Label(new Rect(10, y + 2, w - 136, 24), layerNames[i], dockText);
                if (DockButton(w - 128, y, 58, hiddenLayers[i] ? "Hidden" : "Visible", hiddenLayers[i])) SetLayer(i, !hiddenLayers[i], lockedLayers[i]);
                if (DockButton(w - 67, y, 58, lockedLayers[i] ? "Locked" : "Lock", lockedLayers[i])) SetLayer(i, hiddenLayers[i], !lockedLayers[i]);
            }
        }
    }
}
