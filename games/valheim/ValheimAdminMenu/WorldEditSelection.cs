using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;

namespace ValheimAdminMenu
{
    // History entries share this handle when an undo recreates a deleted structure under a new ZDO ID.
    internal sealed class EditorPieceRef
    {
        private static readonly Dictionary<ZDOID, WeakReference<EditorPieceRef>> refs = new Dictionary<ZDOID, WeakReference<EditorPieceRef>>();
        internal ZDOID Id { get; private set; }
        internal GameObject Instance => ZNetScene.instance ? ZNetScene.instance.FindInstance(Id) : null;
        internal static void Clear() => refs.Clear();
        internal static EditorPieceRef Track(ZNetView view)
        {
            var id = view.GetZDO().m_uid;
            if (refs.TryGetValue(id, out var weak) && weak.TryGetTarget(out var existing)) return existing;
            var handle = new EditorPieceRef();
            handle.Attach(view);
            return handle;
        }
        internal void Attach(ZNetView view)
        {
            refs.Remove(Id);
            Id = view.GetZDO().m_uid;
            refs[Id] = new WeakReference<EditorPieceRef>(this);
        }
    }

    internal sealed partial class TerrainSculptMode
    {
        private enum EditTool { None, Select, Pipette }
        private EditTool editTool;
        private readonly HashSet<EditorPieceRef> selected = new HashSet<EditorPieceRef>();
        private readonly List<HashSet<EditorPieceRef>> editGroups = new List<HashSet<EditorPieceRef>>();
        private Vector2? boxStart;
        private bool selectionPreview, translating, duplicating;
        private ObjectPose[] originals;
        private Vector3 pivot, shift;
        private float turn, lift;

        private sealed class ObjectPose
        {
            internal EditorPieceRef Handle;
            internal Vector3 Position, Scale;
            internal Quaternion Rotation;
            internal string Prefab;
            internal byte[] Data;
            internal uint Revision;
            internal ObjectPose At(Vector3 pos, Quaternion rot) => new ObjectPose
            {
                Handle = Handle,
                Prefab = Prefab,
                Scale = Scale,
                Data = Data,
                Revision = Revision,
                Position = pos,
                Rotation = rot
            };
        }

        private void ChooseEditTool(EditTool next)
        {
            SelectBrush(tool);
            editTool = next;
        }
        private void EndSelectionTool()
        {
            blueprintBrowser = false;
            editTool = EditTool.None;
            selected.Clear();
            boxStart = null;
            CancelTransform();
        }
        private void CancelTransform()
        {
            selectionPreview = translating = duplicating = false;
            originals = null; shift = Vector3.zero; turn = lift = 0;
        }

        private ZNetView PickObject(Vector2 pointer)
        {
            var hits = Physics.RaycastAll(camera.ScreenPointToRay(pointer), 250f, Physics.DefaultRaycastLayers, QueryTriggerInteraction.Ignore);
            foreach (var hit in hits.OrderBy(h => h.distance))
            {
                if (hit.collider.GetComponentInParent<Heightmap>()) break;
                var v = hit.collider.GetComponentInParent<ZNetView>();
                if (v && v.IsValid() && Eligible(v) && !BlockedLayer(v)) return v;
            }
            return null;
        }
        private static bool Eligible(ZNetView view) => view && view.IsValid() &&
            (view.GetComponent<Piece>() || view.GetComponent<TreeBase>() || view.GetComponent<TreeLog>() ||
             view.GetComponent<MineRock>() || view.GetComponent<MineRock5>());

        private void PickSample(ZNetView view)
        {
            if (!view || !view.TryGetComponent(out Piece piece)) throw new InvalidOperationException("Pick a registered build piece.");
            var rot = piece.transform.rotation.eulerAngles;
            string id = Utils.GetPrefabName(view.gameObject);
            OpenPartsPanel();
            if (!partCatalog.Any(p => p.Id == id)) { ChooseEditTool(EditTool.Pipette); throw new InvalidOperationException("This object has no registered build recipe."); }
            StartPiece(id);
            Release250.PastePitch = rot.x; Release250.PasteYaw = rot.y; Release250.PasteRoll = rot.z;
        }

        private bool HandleSelection(Vector2 pointer)
        {
            if (editTool == EditTool.None) return false;
            if (Input.GetMouseButtonDown(1)) { if (selectionPreview) CancelTransform(); else selected.Clear(); boxStart = null; return true; }
            if (editTool == EditTool.Pipette)
            {
                if (!IsOverDock(pointer) && Input.GetMouseButtonDown(0)) TryEdit(() => PickSample(PickObject(pointer)));
                return true;
            }
            if (selectionPreview)
            {
                if (translating && target.HasValue) shift = target.Value - pivot;
                if (Input.GetKeyDown(KeyCode.R)) turn += ShiftHeld ? -15f : 15f;
                if (Input.GetKeyDown(KeyCode.PageUp)) lift += ShiftHeld ? .1f : 1f;
                if (Input.GetKeyDown(KeyCode.PageDown)) lift -= ShiftHeld ? .1f : 1f;
                if (target.HasValue && Input.GetMouseButtonDown(0)) TryEdit(CommitTransform);
                return true;
            }
            if (Input.GetKeyDown(KeyCode.M)) TryEdit(() => BeginTransform(true, false));
            if (Input.GetKeyDown(KeyCode.R)) TryEdit(() => { BeginTransform(false, false); turn = ShiftHeld ? -15 : 15; });
            if (Input.GetKeyDown(KeyCode.PageUp) || Input.GetKeyDown(KeyCode.PageDown))
                TryEdit(() => { BeginTransform(false, false); lift = (Input.GetKeyDown(KeyCode.PageUp) ? 1 : -1) * (ShiftHeld ? .1f : 1f); });
            if (ControlHeld && Input.GetKeyDown(KeyCode.D)) TryEdit(() => BeginTransform(true, true));
            if (ControlHeld && Input.GetKeyDown(KeyCode.G)) TryEdit(() => SetGroup(!ShiftHeld));
            if (Input.GetKeyDown(KeyCode.Delete)) TryEdit(DeleteSelection);
            if (Input.GetMouseButtonDown(0) && !IsOverDock(pointer)) boxStart = pointer;
            if (Input.GetMouseButtonUp(0) && boxStart.HasValue)
            {
                var start = boxStart.Value; boxStart = null;
                if (IsOverDock(pointer)) return true;
                if (!ShiftHeld) selected.Clear();
                if (Vector2.Distance(start, pointer) < 5f) AddSelection(PickObject(pointer));
                else
                {
                    var rect = BoxRect(start, pointer);
                    foreach (var view in WorldTools.Loaded<ZNetView>())
                    {
                        if (!Eligible(view) || BlockedLayer(view)) continue;
                        var screen = camera.WorldToScreenPoint(view.transform.position);
                        if (screen.z > 0 && rect.Contains(new Vector2(screen.x, screen.y))) AddSelection(view);
                    }
                }
            }
            return true;
        }

        private static Rect BoxRect(Vector2 a, Vector2 b) => Rect.MinMaxRect(Mathf.Min(a.x, b.x), Mathf.Min(a.y, b.y), Mathf.Max(a.x, b.x), Mathf.Max(a.y, b.y));
        private void AddSelection(ZNetView v)
        {
            if (!Eligible(v) || BlockedLayer(v)) return;
            var handle = EditorPieceRef.Track(v);
            var group = editGroups.Find(g => g.Contains(handle));
            if (group == null) selected.Add(handle);
            else foreach (var member in group)
            {
                var obj = member.Instance;
                if (obj && !BlockedLayer(obj.GetComponent<ZNetView>())) selected.Add(member);
            }
        }
        private void SetGroup(bool create)
        {
            if (selected.Count < (create ? 2 : 1)) throw new InvalidOperationException("Select the pieces to group or ungroup.");
            editGroups.RemoveAll(g => g.Overlaps(selected));
            if (create) editGroups.Add(new HashSet<EditorPieceRef>(selected));
            ShowNotice(create ? $"Grouped {selected.Count} objects for this session." : "Group released.");
        }

        private static void CheckLocation(Vector3 position)
        {
            if (!Heightmap.FindHeightmap(position)) throw new InvalidOperationException("Load the destination terrain first.");
            if (!PrivateArea.CheckAccess(position, 0f, false, true)) throw new InvalidOperationException("A ward protects this position.");
        }
        private static ZNetView RequireObject(EditorPieceRef handle)
        {
            var obj = handle.Instance;
            var v = obj ? obj.GetComponent<ZNetView>() : null;
            if (!Eligible(v)) throw new InvalidOperationException("A selected object was removed or unloaded.");
            if (!v.IsOwner()) throw new InvalidOperationException("You must own every selected object.");
            CheckLocation(obj.transform.position);
            return v;
        }
        private static readonly HashSet<string> StructuralPrefabs = new HashSet<string>(StringComparer.Ordinal)
        {
            "wood_floor", "wood_floor_1x1", "wood_wall", "wood_wall_half", "wood_wall_quarter",
            "woodwall", "woodwallhalf", "wood_beam", "wood_beam_1m", "wood_beam_26", "wood_beam_45",
            "wood_pole", "wood_pole2", "wood_pole_log", "wood_pole_log_4", "wood_roof", "wood_roof_45",
            "wood_roof_icorner", "wood_roof_icorner_45", "wood_roof_ocorner", "wood_roof_ocorner_45",
            "wood_roof_top", "wood_roof_top_45", "stone_floor", "stone_floor_2x2",
            "stone_wall_1x1", "stone_wall_2x1", "stone_wall_4x2"
        };

        private static bool SimpleStructure(ZNetView view)
        {
            if (!view.GetComponent<WearNTear>() || !view.GetComponent<Piece>() || view.GetZDO().GetConnection() != null) return false;
            string id = Utils.GetPrefabName(view.gameObject);
            return StructuralPrefabs.Contains(id) && !view.GetComponentInChildren<Container>(true);
        }
        private ObjectPose[] CaptureSelection(bool copyData)
        {
            if (selected.Count == 0) throw new InvalidOperationException("Select at least one object.");
            return selected.Select(handle =>
            {
                var v = RequireObject(handle);
                if (BlockedLayer(v)) throw new InvalidOperationException("A selected layer is locked or hidden.");
                var zdo = v.GetZDO();
                var t = v.transform;
                var pose = new ObjectPose
                {
                    Handle = handle,
                    Prefab = Utils.GetPrefabName(v.gameObject),
                    Position = t.position,
                    Rotation = t.rotation,
                    Scale = t.localScale,
                    Revision = zdo.DataRevision
                };
                if (copyData)
                {
                    if (!SimpleStructure(v)) throw new InvalidOperationException("Duplicate and delete support plain structural floors, walls, beams, poles and roofs only.");
                    var pkg = new ZPackage(); zdo.Serialize(pkg); pose.Data = pkg.GetArray();
                }
                return pose;
            }).ToArray();
        }
        private static void ValidatePoses(ObjectPose[] poses, bool revision = false)
        {
            foreach (var pose in poses)
            {
                var view = RequireObject(pose.Handle);
                if (Utils.GetPrefabName(view.gameObject) != pose.Prefab || Vector3.Distance(view.transform.position, pose.Position) > .015f ||
                    Quaternion.Angle(view.transform.rotation, pose.Rotation) > .2f ||
                    Vector3.Distance(view.GetZDO().GetPosition(), pose.Position) > .015f ||
                    Quaternion.Angle(view.GetZDO().GetRotation(), pose.Rotation) > .2f ||
                    (view.transform.localScale - pose.Scale).sqrMagnitude > .0001f || (revision && view.GetZDO().DataRevision != pose.Revision))
                    throw new InvalidOperationException("A selected object changed since this edit.");
            }
        }
        private void BeginTransform(bool move, bool duplicate)
        {
            var poses = CaptureSelection(duplicate);
            originals = poses;
            pivot = poses.Aggregate(Vector3.zero, (p, s) => p + s.Position) / poses.Length;
            shift = Vector3.zero; turn = lift = 0; translating = move; duplicating = duplicate; selectionPreview = true;
        }
        private ObjectPose Destination(ObjectPose p)
        {
            var r = Quaternion.Euler(0, turn, 0);
            return p.At(PreviewPosition(p.Position, r), r * p.Rotation);
        }
        private static void ApplyPoses(ObjectPose[] poses)
        {
            foreach (var p in poses)
            {
                var v = p.Handle.Instance.GetComponent<ZNetView>();
                v.transform.SetPositionAndRotation(p.Position, p.Rotation);
                var z = v.GetZDO(); z.SetPosition(p.Position); z.SetRotation(p.Rotation);
                if (v.TryGetComponent(out ZSyncTransform sync)) sync.SyncNow();
                ZDOMan.instance.ForceSendZDO(z.m_uid);
            }
            Physics.SyncTransforms();
        }
        private static void CheckDestinations(ObjectPose[] poses)
        {
            foreach (var p in poses) CheckLocation(p.Position);
        }
        private static void TransformBatch(ObjectPose[] from, ObjectPose[] to)
        {
            ValidatePoses(from); CheckDestinations(to);
            try { ApplyPoses(to); } catch { ApplyPoses(from); throw; }
        }
        private void CommitTransform()
        {
            if (!selectionPreview) return;
            var before = originals; var after = before.Select(Destination).ToArray();
            ValidatePoses(before, duplicating); CheckDestinations(after);
            if (duplicating)
            {
                foreach (var p in after) p.Handle = new EditorPieceRef();
                RestoreStructures(after);
                app.EditHistory.Record("duplicate selection", StructureChange(after, true));
                selected.Clear(); foreach (var p in after) selected.Add(p.Handle);
            }
            else if (shift.sqrMagnitude > .000001f || Mathf.Abs(turn) + Mathf.Abs(lift) > .001f)
            {
                TransformBatch(before, after);
                app.EditHistory.Record("transform selection", new WorldEditHistory.Change(
                    () => { ValidatePoses(after); CheckDestinations(before); }, () => TransformBatch(after, before),
                    () => { ValidatePoses(before); CheckDestinations(after); }, () => TransformBatch(before, after)));
            }
            CancelTransform();
        }
        private static void RestoreStructures(ObjectPose[] poses)
        {
            CheckDestinations(poses);
            if (poses.Any(p => !ZNetScene.instance.GetPrefab(p.Prefab))) throw new InvalidOperationException("A structural prefab is unavailable.");
            var spawned = new List<GameObject>();
            try
            {
                foreach (var p in poses)
                {
                    var obj = UnityEngine.Object.Instantiate(ZNetScene.instance.GetPrefab(p.Prefab), p.Position, p.Rotation);
                    spawned.Add(obj); var v = obj.GetComponent<ZNetView>();
                    if (!v.IsValid() || !v.IsOwner()) throw new InvalidOperationException("Could not create an owned piece.");
                    var z = v.GetZDO();
                    z.Deserialize(new ZPackage(p.Data)); z.SetPosition(p.Position); z.SetRotation(p.Rotation);
                    v.SetLocalScale(p.Scale); p.Handle.Attach(v);
                    ZDOMan.instance.ForceSendZDO(z.m_uid); p.Revision = z.DataRevision;
                }
            }
            catch { foreach (var obj in spawned) if (obj) ZNetScene.instance.Destroy(obj); throw; }
        }
        private static void RemoveStructures(ObjectPose[] poses)
        {
            ValidatePoses(poses);
            foreach (var p in poses)
            {
                var v = RequireObject(p.Handle);
                if (!SimpleStructure(v)) throw new InvalidOperationException("A piece is no longer a plain structure.");
                var pkg = new ZPackage(); v.GetZDO().Serialize(pkg); p.Data = pkg.GetArray();
            }
            var removed = new List<ObjectPose>();
            try { foreach (var p in poses) { ZNetScene.instance.Destroy(p.Handle.Instance); removed.Add(p); } }
            catch { RestoreStructures(removed.ToArray()); throw; }
        }
        private static WorldEditHistory.Change StructureChange(ObjectPose[] poses, bool created)
        {
            Action checkRemove = () => ValidatePoses(poses), remove = () => RemoveStructures(poses);
            Action checkRestore = () => CheckDestinations(poses), restore = () => RestoreStructures(poses);
            return created ? new WorldEditHistory.Change(checkRemove, remove, checkRestore, restore) :
                new WorldEditHistory.Change(checkRestore, restore, checkRemove, remove);
        }
        private void DeleteSelection()
        {
            var poses = CaptureSelection(true);
            RemoveStructures(poses);
            app.EditHistory.Record("delete selection", StructureChange(poses, false));
            selected.Clear(); CancelTransform();
        }
        private void DrawSelectionControls(float w)
        {
            if (editTool == EditTool.Pipette) { GUI.Label(new Rect(10, 50, w, 65), "Click a built piece to continue building with its rotation.", dockText); return; }
            GUI.Label(new Rect(10, 50, w, 30), $"{selected.Count} selected", dockText);
            if (selectionPreview)
            {
                GUI.Label(new Rect(10, 81, w, 54), $"Preview    {turn:0}°    {lift:+0.0;-0.0;0} m", dockText);
                if (DockButton(10, 139, w, "Confirm")) TryEdit(CommitTransform);
                if (DockButton(10, 171, w, "Cancel")) CancelTransform();
                return;
            }
            bool any = selected.Count > 0;
            if (DockButton(10, 83, w, "Move   M", enabled: any)) TryEdit(() => BeginTransform(true, false));
            if (DockButton(10, 115, w, "Rotate   R", enabled: any)) TryEdit(() => { BeginTransform(false, false); turn = 15; });
            if (DockButton(10, 147, w, "Duplicate   Ctrl+D", enabled: any)) TryEdit(() => BeginTransform(true, true));
            if (DockButton(10, 179, w, "Delete", enabled: any)) TryEdit(DeleteSelection);
            if (DockButton(10, 221, w / 2 - 2, "Group", enabled: selected.Count > 1)) TryEdit(() => SetGroup(true));
            if (DockButton(10 + w / 2, 221, w / 2 - 2, "Ungroup", enabled: any)) TryEdit(() => SetGroup(false));
        }
        private Vector3 PreviewPosition(Vector3 position, Quaternion rotation) =>
            pivot + shift + Vector3.up * lift + rotation * (position - pivot);

        private bool DrawSelection()
        {
            if (editTool == EditTool.None) return false;
            if (boxStart.HasValue)
            {
                var rect = BoxRect(boxStart.Value, Input.mousePosition);
                rect.y = Screen.height - rect.yMax;
                Fill(rect, new Color(.95f, .73f, .34f, .24f));
            }

            var previousColor = GUI.color;
            GUI.color = selectionPreview ? Color.cyan : DockGold;
            try
            {
                if (selectionPreview)
                {
                    var rotation = Quaternion.Euler(0, turn, 0);
                    foreach (var pose in originals)
                    {
                        var obj = pose.Handle.Instance;
                        if (obj) DrawSelectionBounds(obj, PreviewPosition(pose.Position, rotation), rotation * pose.Rotation);
                    }
                }
                else
                {
                    foreach (var handle in selected)
                    {
                        var obj = handle.Instance;
                        if (obj) DrawSelectionBounds(obj, obj.transform.position, obj.transform.rotation);
                    }
                }
            }
            finally { GUI.color = previousColor; }
            return true;
        }

        private void DrawSelectionBounds(GameObject obj, Vector3 position, Quaternion rotation)
        {
            var transform = obj.transform;
            var collider = obj.GetComponentInChildren<Collider>();
            var bounds = collider ? collider.bounds : new Bounds(transform.position, Vector3.one);
            var delta = rotation * Quaternion.Inverse(transform.rotation);
            for (int cornerIndex = 0; cornerIndex < 8; cornerIndex++)
            {
                var corner = new Vector3(
                    (cornerIndex & 1) == 0 ? bounds.min.x : bounds.max.x,
                    (cornerIndex & 2) == 0 ? bounds.min.y : bounds.max.y,
                    (cornerIndex & 4) == 0 ? bounds.min.z : bounds.max.z);
                var start = position + delta * (corner - transform.position);
                for (int axis = 0; axis < 3; axis++)
                {
                    if ((cornerIndex & (1 << axis)) != 0) continue;
                    var edge = Vector3.zero;
                    edge[axis] = bounds.size[axis];
                    Release250.DrawScreenLine(camera, start, start + delta * edge);
                }
            }
        }
    }
}
