using System;
using System.Collections.Generic;
using HarmonyLib;
using UnityEngine;

namespace ValheimAdminMenu
{
    internal static class PlacementSnap
    {
        internal static bool UniversalSnap = true;
        private const float SearchRadius = 4.5f;
        private const float MaxPairDistance = 1.75f;
        private static readonly List<Piece> nearby = new List<Piece>();
        private static readonly List<Transform> ghostSnaps = new List<Transform>();
        private static readonly List<Transform> worldSnaps = new List<Transform>();
        private static readonly Collider[] overlap = new Collider[64];

        /// <summary>Snap ghost snap-points onto nearby world pieces. Safe to call while UniversalSnap is off (drag start).</summary>
        internal static void AlignGhost(GameObject ghost)
        {
            if (!ghost || !ghost.activeInHierarchy) return;
            if (DragBuilding.Active) return;
            if (IsExcludedGhost(ghost)) return;
            var piece = ghost.GetComponent<Piece>();
            if (!piece) return;

            ghostSnaps.Clear();
            try { piece.GetSnapPoints(ghostSnaps); } catch (Exception caught) { AppLog.Swallow(caught); return; }
            if (ghostSnaps.Count == 0) return;

            if (TrySnapDelta(piece, ghost.transform.position, ghost.transform.rotation, false, out var delta))
                ghost.transform.position += delta;
        }

        internal static bool TrySnapPart(Piece prefab, Vector3 origin, Quaternion rotation, out Vector3 delta)
        {
            ghostSnaps.Clear();
            prefab.GetSnapPoints(ghostSnaps);
            return TrySnapDelta(prefab, origin, rotation, true, out delta);
        }

        private static bool TrySnapDelta(Piece source, Vector3 origin, Quaternion rotation, bool prefab, out Vector3 delta)
        {
            delta = Vector3.zero;
            if (ghostSnaps.Count == 0) return false;
            CollectNearbyPieces(origin, SearchRadius);
            float best = MaxPairDistance * MaxPairDistance;
            bool found = false;
            foreach (var other in nearby)
            {
                if (other == source || other.transform.IsChildOf(source.transform)) continue;
                if (prefab && (!other.TryGetComponent(out ZNetView view) || !view.IsValid())) continue;
                worldSnaps.Clear();
                try { other.GetSnapPoints(worldSnaps); } catch (Exception caught) { AppLog.Swallow(caught); continue; }
                foreach (var local in ghostSnaps)
                {
                    if (!local) continue;
                    Vector3 point = prefab ? origin + rotation * (local.position - source.transform.position) : local.position;
                    foreach (var anchor in worldSnaps)
                    {
                        if (!anchor) continue;
                        Vector3 offset = anchor.position - point;
                        float distance = offset.sqrMagnitude;
                        if (distance >= best) continue;
                        // Adjacent identical pieces can share several anchors. Do not snap a copy into its twin.
                        if (prefab && other.m_name == source.m_name && (origin + offset - other.transform.position).sqrMagnitude < .001f
                            && Quaternion.Angle(rotation, other.transform.rotation) < .1f) continue;
                        best = distance;
                        delta = offset;
                        found = true;
                    }
                }
            }
            return found;
        }

        private static bool IsExcludedGhost(GameObject ghost)
        {
            if (!ghost) return true;
            // Creative cliffs/NPCs/props shouldn't jump onto building snap points.
            if (ghost.GetComponent<CreativeRecipe>()) return true;
            if (ghost.GetComponent<Plant>()) return true;
            if (ghost.GetComponent<TerrainModifier>() || ghost.GetComponentInChildren<TerrainModifier>(true)) return true;
            string n = ghost.name ?? "";
            if (n.IndexOf("ValheavenDragGhost", StringComparison.Ordinal) >= 0) return true;
            if (n.IndexOf("ValheavenPasteGhost_", StringComparison.Ordinal) >= 0) return true;
            return false;
        }

        private static void CollectNearbyPieces(Vector3 center, float radius)
        {
            nearby.Clear();
            int mask = LayerMask.GetMask("piece", "Default", "static_solid", "Default_small");
            int hitCount = Physics.OverlapSphereNonAlloc(center, radius, overlap, mask, QueryTriggerInteraction.Collide);
            for (int i = 0; i < hitCount; i++)
            {
                var col = overlap[i];
                if (!col) continue;
                var piece = col.GetComponentInParent<Piece>();
                if (!piece || piece.GetComponent<ItemDrop>() || piece.GetComponent<Character>()) continue;
                if (piece.GetComponent<Plant>()) continue;
                string pieceName = piece.gameObject ? piece.gameObject.name : "";
                if (pieceName.IndexOf("ValheavenDragGhost", StringComparison.Ordinal) >= 0) continue;
                if (pieceName.IndexOf("ValheavenPasteGhost_", StringComparison.Ordinal) >= 0) continue;
                if (!nearby.Contains(piece)) nearby.Add(piece);
            }
        }

        [HarmonyPatch(typeof(Player), "UpdatePlacementGhost")]
        private static class GhostSnapPatch
        {
            private static void Postfix(Player __instance)
            {
                if (!UniversalSnap || __instance != Player.m_localPlayer) return;
                if (DragBuilding.Active) return;
                if (FreeBuildRotation.Enabled) return;
                // Hoe / cultivator must keep vanilla ghost math.
                if (!Release250.IsBuildHammer(__instance)) return;
                var ghost = Reflection.Get<GameObject>(__instance, "m_placementGhost");
                if (ghost && ghost.activeInHierarchy) AlignGhost(ghost);
            }
        }
    }
}
