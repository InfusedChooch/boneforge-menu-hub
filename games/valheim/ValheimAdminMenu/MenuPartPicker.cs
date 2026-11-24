using System;
using System.Collections.Generic;
using System.Linq;
using TMPro;
using UnityEngine;
using UnityEngine.UI;

namespace ValheimAdminMenu
{
    internal sealed partial class MenuView
    {
        private const float PartPickerWidth = 896f, PartPickerHeight = 548f;
        private const int PartColumns = 3, PartsPerPage = 15;
        private PartPicker partPicker;

        private sealed class PartPicker
        {
            internal bool OpenedFromEditor;
            internal int FocusOnFrame, Page;
            internal Piece.PieceCategory Category = Piece.PieceCategory.All;
            internal RectTransform Panel, Results;
            internal TMP_InputField Search;
            internal TextMeshProUGUI Count;
            internal Button Previous, Next, Close;
            internal WorldEditParts.Entry[] Catalog;
            internal readonly Dictionary<Piece.PieceCategory, Button> Categories = new Dictionary<Piece.PieceCategory, Button>();
            internal readonly List<Button> Cards = new List<Button>();
        }

        internal void OpenPartPicker(bool openedFromEditor = false)
        {
            app.RequireWorld();
            if (!app.Open) app.SetOpen(true);
            if (!app.Open) return;
            ClosePopup();
            var catalog = WorldEditParts.Load();
            var picker = new PartPicker
            {
                OpenedFromEditor = openedFromEditor, Catalog = catalog.Parts, FocusOnFrame = Time.frameCount + 1
            };
            partPicker = picker;
            if (openedFromEditor) window.gameObject.SetActive(false);
            popup = Box(canvasRect, "Part picker overlay", new Color(0f, 0f, 0f, .57f), true);
            Stretch(popup);
            var panel = Box(popup, "Part picker", Panel, true);
            picker.Panel = panel;
            panel.anchorMin = panel.anchorMax = panel.pivot = new Vector2(.5f, .5f);
            panel.sizeDelta = new Vector2(PartPickerWidth, PartPickerHeight);
            Border(panel, GoldDim);
            var title = LabelAt(panel, L.T("world_edit.parts_title"), 22, 13, 723, 42, 28, Gold);
            title.font = displayFont;
            picker.Close = ActionButton(panel, L.T("chrome.cancel"), DismissPopup, null, false, "Close part picker");
            At((RectTransform)picker.Close.transform, 764, 17, 110, 34);
            picker.Search = InputBox(panel, "", _ =>
            {
                picker.Page = 0;
                RenderPartResults(picker);
            }, L.T("world_edit.parts_search"), 80);
            picker.Search.name = "Part search";
            At((RectTransform)picker.Search.transform, 22, 67, 852, 38);

            AddPartCategory(picker, Piece.PieceCategory.All, L.T("world_edit.parts_all"));
            foreach (var category in catalog.Parts.Select(part => part.Category).Distinct().OrderBy(value => value))
                AddPartCategory(picker, category, catalog.Categories.TryGetValue(category, out var label) ? label : category.ToString());

            picker.Results = Node(panel, "Part results");
            At(picker.Results, 208, 122, 666, 350);
            picker.Count = LabelAt(panel, "", 208, 488, 355, 38, 15, Muted);
            picker.Previous = ActionButton(panel, L.T("world_edit.parts_previous"), () =>
            {
                picker.Page--;
                RenderPartResults(picker);
            });
            At((RectTransform)picker.Previous.transform, 650, 488, 108, 36);
            picker.Next = ActionButton(panel, L.T("world_edit.parts_next"), () =>
            {
                picker.Page++;
                RenderPartResults(picker);
            });
            At((RectTransform)picker.Next.transform, 766, 488, 108, 36);
            LabelAt(panel, L.T("world_edit.parts_keyboard"), 22, 488, 176, 38, 13, Muted);
            foreach (var button in picker.Categories.Values.Concat(new[] { picker.Close, picker.Previous, picker.Next }))
                StylePartButtonFocus(button);
            FitPartPicker(picker);
            RenderPartResults(picker);
        }

        private void AddPartCategory(PartPicker picker, Piece.PieceCategory category, string label)
        {
            var button = ActionButton(picker.Panel, label, () =>
            {
                picker.Category = category;
                picker.Page = 0;
                RenderPartResults(picker);
            }, logAs: "Part category " + category);
            At((RectTransform)button.transform, 22, 122 + picker.Categories.Count * 35, 173, 31);
            var text = button.GetComponentInChildren<TextMeshProUGUI>();
            text.alignment = TextAlignmentOptions.MidlineLeft;
            picker.Categories.Add(category, button);
        }

        private void RenderPartResults(PartPicker picker)
        {
            if (partPicker != picker || !picker.Results) return;
            Clear(picker.Results);
            picker.Cards.Clear();
            foreach (var category in picker.Categories)
                ((Image)category.Value.targetGraphic).color = category.Key == picker.Category ? Selected : FieldColor;

            string query = picker.Search.text.Trim();
            var results = WorldEditParts.Filter(picker.Catalog, picker.Category, query);
            int pages = Math.Max(1, (results.Length + PartsPerPage - 1) / PartsPerPage);
            picker.Page = Mathf.Clamp(picker.Page, 0, pages - 1);
            foreach (var part in results.Skip(picker.Page * PartsPerPage).Take(PartsPerPage))
                AddPartCard(picker, part);
            if (results.Length == 0)
                LabelAt(picker.Results, L.T(picker.Catalog.Length == 0 ? "world_edit.parts_unavailable" : "world_edit.parts_no_matches"),
                    10, 10, 625, 42, 17, Muted);
            picker.Count.text = results.Length == 0 ? "" : L.Tf("world_edit.parts_page", results.Length, picker.Page + 1, pages);
            picker.Previous.interactable = picker.Page > 0;
            picker.Next.interactable = picker.Page + 1 < pages;
        }

        private void AddPartCard(PartPicker picker, WorldEditParts.Entry part)
        {
            var button = ActionButton(picker.Results, "", () => Run(() => app.Sculpt.StartPiece(part.Id), part.Name),
                logAs: "Part " + part.Id);
            button.name = part.Id;
            StylePartButtonFocus(button);
            var rect = (RectTransform)button.transform;
            int index = picker.Cards.Count;
            At(rect, index % PartColumns * 224, index / PartColumns * 71, 218, 65);
            picker.Cards.Add(button);
            var icon = Box(rect, "Part icon", FieldColor);
            At(icon, 8, 10, 44, 44);
            if (part.Icon)
            {
                var image = Box(icon, "Sprite", Color.white).GetComponent<Image>();
                Stretch((RectTransform)image.transform, 3, 3, 3, 3);
                image.sprite = part.Icon;
                image.preserveAspect = true;
            }
            var name = Label(rect, part.Name, 16, Ink, localize: false);
            At(name.rectTransform, 61, 5, 150, 36);
            name.overflowMode = TextOverflowModes.Ellipsis;
            var id = Label(rect, part.Id, 12, Muted, localize: false);
            At(id.rectTransform, 61, 42, 150, 16);
            ChromeCaption(id);
        }

        private void FitPartPicker(PartPicker picker)
        {
            var size = CanvasSize();
            float fit = Mathf.Min((size.x - 32f) / PartPickerWidth, (size.y - 32f) / PartPickerHeight);
            picker.Panel.localScale = Vector3.one * Mathf.Max(.1f, Mathf.Min(appliedScale, fit));
        }

        private static void StylePartButtonFocus(Button button)
        {
            var colors = button.colors;
            colors.selectedColor = new Color(1.4f, 1.25f, 1.05f);
            button.colors = colors;
        }

        private void TickPartPicker()
        {
            var picker = partPicker;
            if (picker == null || !inputSystem) return;
            FitPartPicker(picker);
            if (Time.frameCount == picker.FocusOnFrame) picker.Search.ActivateInputField();
            var selected = inputSystem.currentSelectedGameObject;
            if (Input.GetKeyDown(KeyCode.Tab))
            {
                var controls = new List<Selectable> { picker.Search };
                controls.AddRange(picker.Categories.Values);
                controls.AddRange(picker.Cards);
                if (picker.Previous.interactable) controls.Add(picker.Previous);
                if (picker.Next.interactable) controls.Add(picker.Next);
                controls.Add(picker.Close);
                int index = controls.FindIndex(control => control.gameObject == selected);
                bool backwards = Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift);
                int next = index < 0 ? (backwards ? controls.Count - 1 : 0)
                    : (index + (backwards ? -1 : 1) + controls.Count) % controls.Count;
                var controlNext = controls[next];
                inputSystem.SetSelectedGameObject(controlNext.gameObject);
                if (controlNext == picker.Search) picker.Search.ActivateInputField();
            }
            else if (Input.GetKeyDown(KeyCode.Return) || Input.GetKeyDown(KeyCode.KeypadEnter))
            {
                if (selected == picker.Search.gameObject)
                {
                    if (picker.Cards.Count == 1 && !picker.Previous.interactable && !picker.Next.interactable)
                        picker.Cards[0].onClick.Invoke();
                    else if (picker.Cards.Count > 0)
                        inputSystem.SetSelectedGameObject(picker.Cards[0].gameObject);
                }
                else if (selected && selected.transform.IsChildOf(picker.Panel) && selected.TryGetComponent(out Button button)
                    && button.interactable)
                    button.onClick.Invoke();
            }
        }
    }
}
