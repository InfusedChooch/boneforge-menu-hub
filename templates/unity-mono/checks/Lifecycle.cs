using System;
using Boneforge.MenuStarter;

// Stand-ins for the three Unity operations used by the production entry point.
namespace UnityEngine
{
    public class Object
    {
        internal bool Destroyed;
        internal static Object Persistent;
        public static implicit operator bool(Object value) => value != null && !value.Destroyed;
        public static void DontDestroyOnLoad(Object value) => Persistent = value;
        public static void Destroy(Object value) => value.Destroyed = true;
    }

    public class GameObject : Object
    {
        public static int Created;
        public static Object Component;
        public GameObject(string name) { Created++; }
        public T AddComponent<T>() where T : Object, new()
        {
            var component = new T();
            Component = component;
            return component;
        }
    }
}

namespace Boneforge.MenuStarter
{
    internal class MenuView : UnityEngine.Object
    {
        public Func<string> CurrentArea;
    }
}

internal static class Lifecycle
{
    private static void Main()
    {
        Entry.Start();
        var first = (MenuView)UnityEngine.GameObject.Component;
        Entry.Start(() => "Forest");
        Entry.Start();
        if (UnityEngine.GameObject.Created != 1 || !UnityEngine.Object.Persistent ||
            first.CurrentArea() != "Forest") throw new Exception("Duplicate startup or lost adapter");

        UnityEngine.Object.Destroy(first);
        Entry.Start();
        if (UnityEngine.GameObject.Created != 2 || first == UnityEngine.GameObject.Component)
            throw new Exception("Destroyed host was not replaced");
        Console.WriteLine("Duplicate startup, persistence registration and host replacement passed.");
    }
}
