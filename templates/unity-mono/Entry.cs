using System;
using UnityEngine;

namespace Boneforge.MenuStarter
{
    public static class Entry
    {
        private static MenuView instance;

        // Call on Unity's main thread. Return null or empty until an area is available.
        public static void Start(Func<string> currentArea = null)
        {
            if (!instance)
            {
                var root = new GameObject(typeof(Entry).Assembly.GetName().Name);
                try
                {
                    instance = root.AddComponent<MenuView>();
                    UnityEngine.Object.DontDestroyOnLoad(root);
                }
                catch
                {
                    UnityEngine.Object.Destroy(root);
                    throw;
                }
            }
            if (currentArea != null) instance.CurrentArea = currentArea;
        }
    }
}
