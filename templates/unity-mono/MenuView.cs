using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace Boneforge.MenuStarter
{
    public sealed class MenuView : MonoBehaviour
    {
        internal Func<string> CurrentArea;
        private static readonly System.Reflection.AssemblyName Identity = typeof(MenuView).Assembly.GetName();
        private static readonly string HintsKey = Identity.Name + ".ControlHints";
        private readonly List<KeyValuePair<string, Action>> pages = new List<KeyValuePair<string, Action>>();
        private int page;
        private Text content;
        private Canvas canvas;
        private bool hints;
        private string sampledArea;
        private float nextRefresh;
#if VALHEIM
        private UnityEngine.InputSystem.InputAction suspendedChat;

        private void UpdateChatInput(bool menuOpen)
        {
            var action = ZInput.instance?.GetButtonDef("Chat")?.ButtonAction;
            if (suspendedChat != action) suspendedChat = null;
            if (menuOpen && action != null && action.enabled)
            {
                action.Disable();
                ZInput.ResetButtonStatus("Chat");
                suspendedChat = action;
            }
            else if (!menuOpen && suspendedChat != null)
            {
                suspendedChat.Enable();
                suspendedChat = null;
            }
        }

        private void OnDisable() => UpdateChatInput(false);
#endif

        private void Awake()
        {
            hints = PlayerPrefs.GetInt(HintsKey, 1) != 0;
            pages.Add(new KeyValuePair<string, Action>("Overview", DrawOverview));
            pages.Add(new KeyValuePair<string, Action>("Settings", DrawSettings));
            var surface = new GameObject("Menu", typeof(RectTransform), typeof(Canvas), typeof(CanvasScaler));
            surface.transform.SetParent(transform, false);
            canvas = surface.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 30000;
            surface.GetComponent<CanvasScaler>().uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;

            var panel = new GameObject("Panel", typeof(RectTransform), typeof(Image));
            panel.transform.SetParent(surface.transform, false);
            var rect = panel.GetComponent<RectTransform>();
            rect.anchorMin = rect.anchorMax = rect.pivot = new Vector2(0, 1);
            rect.anchoredPosition = new Vector2(24, -24);
            rect.sizeDelta = new Vector2(460, 190);
            panel.GetComponent<Image>().color = new Color(0.08f, 0.10f, 0.13f, 0.96f);

            var label = new GameObject("Page", typeof(RectTransform), typeof(Text));
            label.transform.SetParent(panel.transform, false);
            content = label.GetComponent<Text>();
            content.rectTransform.anchorMin = Vector2.zero;
            content.rectTransform.anchorMax = Vector2.one;
            content.rectTransform.offsetMin = new Vector2(16, 12);
            content.rectTransform.offsetMax = new Vector2(-16, -12);
            content.font = Font.CreateDynamicFontFromOSFont("Arial", 17);
            content.fontSize = 17;
            content.supportRichText = false;
            canvas.enabled = false;
        }

        private void Update()
        {
            bool refresh = Input.GetKeyDown(KeyCode.F8);
            if (refresh) canvas.enabled = !canvas.enabled;
#if VALHEIM
            if (canvas.enabled || suspendedChat != null) UpdateChatInput(canvas.enabled);
#endif
            if (!canvas.enabled) return;
            int step = Input.GetKeyDown(KeyCode.RightArrow) ? 1 : Input.GetKeyDown(KeyCode.LeftArrow) ? -1 : 0;
            if (step != 0) page = (page + step + pages.Count) % pages.Count;
            if (refresh || step != 0 || Input.GetKeyDown(KeyCode.Return) || Time.unscaledTime >= nextRefresh)
            {
                pages[page].Value();
                nextRefresh = Time.unscaledTime + 0.25f;
            }
        }

        private void DrawOverview()
        {
            var area = CurrentArea?.Invoke();
            bool ready = !string.IsNullOrEmpty(area);
            if (!ready) sampledArea = null;
            else if (Input.GetKeyDown(KeyCode.Return)) sampledArea = area;
            string feature = ready ? "Enter: Read current area" : "Read current area unavailable. Waiting for a game area.";
            Draw((ready ? "Game adapter ready" : "Game adapter unavailable") + "\n" + feature +
                (sampledArea == null ? "" : "\n" + sampledArea));
        }

        private void DrawSettings()
        {
            if (Input.GetKeyDown(KeyCode.Return))
            {
                hints = !hints;
                PlayerPrefs.SetInt(HintsKey, hints ? 1 : 0);
                PlayerPrefs.Save();
            }
            Draw("Enter: Show control hints [" + (hints ? "On" : "Off") + "]");
        }

        private void Draw(string body)
        {
            content.text = Identity.Name + "  " + Identity.Version.ToString(3) + "\n<  " + pages[page].Key +
                "  >\n\n" + body + (hints ? "\n\nLeft / Right: page     F8: close" : "");
        }
    }
}
