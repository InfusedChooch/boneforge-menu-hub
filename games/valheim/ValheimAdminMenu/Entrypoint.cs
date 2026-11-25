using System;
using System.Threading;
using HarmonyLib;
using UnityEngine;
using ValheimAdminMenu;

namespace Valheaven
{
    /// <summary>Native version.dll calls this from a worker thread after Mono is up. We only schedule a main-thread gate here.</summary>
    public static class Entrypoint
    {
        private static bool started;
        private static int scheduled;
        private static volatile bool gatesInstalled;
        private static Harmony bootstrap;
        private static int failures;
        private static float retryAt;

        /// <summary>Idempotent. Safe from a non-main Mono thread.</summary>
        public static void Start()
        {
            if (Interlocked.Exchange(ref scheduled, 1) != 0) return;

            bootstrap = new Harmony("valheaven.bootstrap");
            var ready = new HarmonyMethod(typeof(Entrypoint), nameof(OnMainThreadReady));
            int gates = 0;
            // Frame callbacks run after Start, including when the loader attaches mid-session.
            foreach (var frame in new[]
                     {
                         AccessTools.Method(typeof(FejdStartup), "Update"),
                         AccessTools.Method(typeof(Game), "Update")
                     })
            {
                if (frame == null) continue;
                try { bootstrap.Patch(frame, postfix: ready); gates++; }
                catch (Exception ex) { try { AppLog.Warning("Bootstrap gate " + frame.DeclaringType?.Name + " failed: " + ex.Message); } catch (Exception caught) { AppLog.Swallow(caught); } }
            }

            if (gates == 0)
                throw new MissingMethodException("No Unity main-thread bootstrap gate found.");
            gatesInstalled = true;
        }

        // Harmony postfix. Unity objects only on the main thread.
        private static void OnMainThreadReady()
        {
            // The loader may still be patching the other callback when this one first fires.
            if (!gatesInstalled || started) return;
            var database = ObjectDB.instance;
            if (!database || database.m_items == null || database.m_items.Count == 0) return;
            // Per-frame gates fire every frame; after a failure, retry about once a second rather than every frame.
            if (failures > 0 && Time.realtimeSinceStartup < retryAt) return;
            try
            {
                // Plugin.Awake destroys a duplicate host.
                var host = new GameObject("ValheavenHost");
                UnityEngine.Object.DontDestroyOnLoad(host);
                host.AddComponent<Plugin>();
                started = true;
                AppLog.Info("Bootstrap host created on main thread (" + SystemInfo.graphicsDeviceType + ").");
            }
            catch (Exception ex)
            {
                failures++;
                retryAt = Time.realtimeSinceStartup + 1f;
                // Don't rethrow into Unity's callback; keep the gates patched and retry.
                if (failures <= 5 || failures % 60 == 0)
                {
                    try { AppLog.Error("Bootstrap failed (attempt " + failures + "): " + ex); }
                    catch (Exception caught) { AppLog.Swallow(caught); /* AppLog itself may not be writable yet */ }
                }
                return;
            }

            try { bootstrap?.UnpatchAll(bootstrap.Id); } catch (Exception caught) { AppLog.Swallow(caught); /* ignore */ }
            bootstrap = null;
        }
    }
}
