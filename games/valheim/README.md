# Valheaven | Boneforge Edition

A Windows mod menu for Valheim with building, crafting, and world tools. It loads from `version.dll` alongside `valheim.exe` and runs without BepInEx.

- **Current release** 4.0.2
- **Verified on** Valheim 1.0.30 for Windows (Steam build 26870846, network version 42), including a vanilla dedicated server.
- **Open menu** Press **F8** by default. Change the key in Settings.

## License

Boneforge Edition is available under the [GNU General Public License v3.0](../../LICENSE).

This is an unofficial Valheim mod. Iron Gate Studio and Coffee Stain Publishing are unaffiliated with the project. The mod is available free of charge and comes without warranty.

## Changelog

- **4.0.2 (November 25, 2026)** World Edit now preserves independent terrain changes between brush stamps, replays terrain history after a tile reloads, and restores only the pieces removed by placement undo. Menu startup waits for the game’s item database before installing feature hooks.

- **November 25, 2026 compatibility check.** The released 4.0.1 DLL passed 400 offline checks and 85 in-game assertions on Valheim 1.0.30. All 168 Harmony hooks loaded. Tests covered World Edit, dedicated-server placement and reconnect, and both Forge of Potential options.
- **4.0.1 (November 24, 2026)** Added the top-down World Edit workspace on **F6**, with a searchable parts picker, snapping and grid controls, terrain brushes, area copy, saved blueprints, group transforms, and shared undo/redo.
- **4.0.0 (November 24, 2026)** Boneforge Edition version update.
- **Boneforge Edition (November 24, 2026)** Updated the menu branding, credits, and documentation.
- **3.0.6:** Hammer all prefabs can now place dungeons and world locations. Dungeons (crypts, caves, infested mines, Hildir's dungeons) build a new random layout with loot and enemies up in the sky, with a named entrance portal where you place it and an exit inside; camps and villages build in place. Locations (troll caves, burial chambers, frost caves, altars, ...) place whole, with their interiors and doors. Removing either with the hammer also removes what it spawned. Fixed: drag building, free rotation, snap, placement HUD, paste and bag/stack settings resetting on restart; placed spawners vanishing; Logging: Valheaven.log now records a session header, menu actions, toggles and hotkeys, and errors that used to be silent; Settings -> Diagnostics adds a Debug logging toggle, Write to log and Open log folder.
- **3.0.5:** Fixed the real cause of the "falling/sliding mode" and "can't place anything (hammer/hoe/cultivator)" bugs. DX11: extra bootstrap path when the menu never started, menu-visibility details in Valheaven.log, and a hint when Exclusive Fullscreen is active.
- **3.0.4:** God mode / flight keep working when other mods overwrite vanilla debug flags (re-assert + local fly fallback only if needed). Settings → Interface → Section layout: Dropdowns (default) or Full list.
- **3.0.3:** Craft-from-chests no longer hitch when opening the crafting menu (cache nearby chest stacks; stop ClaimOwnership spam on every recipe check).
- **3.0.2:** Hardened related 3.0 features - free-rotation / universal snap / drag only on build hammer (not hoe/cultivator); paste/drag/freecam-build/mount float state clears on portal/death; mount AI gravity restored on detach.
- **3.0.1:** Drag-build no longer blocks hammer/hoe/cultivator placement (off by default; click places, hold to drag walls/floors/beams/roofs). Freecam-build / portal leftover no-gravity “falling slide” cleared.
- **DX11 menu not showing (Vulkan OK):** stop auto-closing on focus loss (Exclusive Fullscreen blips when unlocking the cursor). Bootstrap failures now log + retry; menu canvas/show path is more resilient. Ready line logs GFX + fullscreen mode.

---

## What you get

A full overlay menu: character cheats and QoL, building / crafting helpers, item spawner + editor, farming, world tools (weather, terrain, structure copy/paste + blueprints), teleport bookmarks, camera stuff, ESP, events, and hotkey binds.

In a loaded world, open **F8 → World Edit** to shape or paint terrain, copy and preview structures, manage saved blueprints, or enable freecam building. Multiplayer terrain editing requires ownership of the loaded terrain tiles.

### Top-down World Edit

Press **F6** to enter or leave the editor. Rebind it under **Hotkeys → Toggle top-down World Edit**.

| Control | Action |
| --- | --- |
| WASD or middle-drag | Pan the camera |
| Wheel · Q / E | Zoom · turn the camera |
| H · F1 | Hide the interface · show controls |
| Panel arrow · inner edge | Collapse the panel · drag to resize |
| Ctrl+Z / Ctrl+Y | Undo or redo one stroke or batch |
| History | Click a row to return to that state within the last 24 edits. Esc closes the panel. |

**Building.** Open **Build pieces** or press **P** for the parts panel. Pick a category or press **/** to search by name or prefab ID. **Enter** selects a single match. Hover over a tile to see its name and ID. Click the world repeatedly to build with the selected piece.

- Choose **Free**, **0.5**, **1**, or **2 m** grid spacing. Enable **Snap to pieces** to use nearby native anchors. **Snapped** confirms alignment.
- **R** rotates 15°. **PgUp/PgDn** adjust height by 1 m. Hold **Shift** for 0.1 m steps. **Pipette** samples a built piece and its rotation.
- **Blueprints** previews a saved build. **B** previews the structure clipboard. Left-click places the preview. Right-click or **Esc** cancels it.

**Selection and layers.** Click, Shift-click to add, or drag a box. **M** moves, **R** rotates, **PgUp/PgDn** change height, and **Ctrl+D** duplicates. Confirm with a world click or the inspector button. **Esc** cancels. **Ctrl+G** groups the selection for the session and **Ctrl+Shift+G** ungroups it. Moves preserve object identity and stored state. Duplicate and Delete support plain floors, walls, beams, roofs, and poles. Group edits check wards, ownership, loaded destinations, and current positions. **Layers** hides or locks build pieces, trees, and mineable rocks locally. Exiting restores visibility.

**Terrain brushes.** Use **1–7** for Raise, Lower, Smooth, Flatten, Paint, Terrace, and Peak, respectively. **Ctrl+wheel** changes radius and **Shift+wheel** changes strength where available. Start a stroke with **Ctrl** to invert Raise/Lower or **Shift** to smooth. **Alt-click** samples a Flatten height. Terrace rounds heights toward the chosen step. Peak raises the center most. Paint has separate material and strength controls.

**Area copy.** Choose **Area copy**, drag a rectangle, then use **Ctrl+C** to copy and **Ctrl+V** to preview. Left-click stamps the terrain, ground paint, and supported loaded objects. The preview stays armed for repeated placements. The structure clipboard stays available on **B**. **G** switches from a terrain brush to area selection.

**Hills.** Press **L** from a terrain brush and drag outward to create a hill. Click a hill, then use **PgUp/PgDn** to change its height or **Delete** to remove it. Tall hills render in local worlds with Valheaven loaded. Hill handles and history last for the loaded world session. The terrain itself is saved. Press **T** to test the ground under your pointer in the Viking view, then use the editor hotkey to return.

Settings, bookmarks, blueprints, and a log land next to the game folder. If that folder isn't writable, they go under `%AppData%\Valheaven\` instead.

---

## Install

1. Download the [Windows ZIP](https://github.com/InfusedChooch/boneforge-menu-hub/releases/download/v4.0.2/boneforge-valheaven-v4.0.2-win-x64.zip) or build `version.dll` using the [build steps](#build).
2. Extract or copy `version.dll` next to `valheim.exe`. If you built from source, you can also use the install script:

```powershell
.\Install-Valheaven.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Valheim"
```

3. Launch Valheim and hit **F8**.

Don't touch `winhttp.dll` / Doorstop for this mod.

To uninstall, delete `version.dll`. Optional leftovers: `Valheaven.settings.json`, `Valheaven.bookmarks.json`, `Valheaven.blueprints.json`, `Valheaven.log`, and a `blueprints\` folder.

---

## Localization

Strings are JSON packs in `ValheimAdminMenu/Locales/`. **`en.json` is the source of truth.**

Shipped: English, Russian, German, French, Spanish, Portuguese (Brazil), Chinese Simplified/Traditional, Japanese.

See [`ValheimAdminMenu/Locales/README.md`](ValheimAdminMenu/Locales/README.md) for the short how-to.

Quick rules:

- Change values, not keys
- Keep `{0}` / `{1}` in the same order as English
- Keys starting with `_` are metadata

**Try a translation without rebuilding:** Settings > Locales > Export, edit the files under `locales/` beside the game (or `%AppData%\Valheaven\locales\`), then Reload locales.

**New language:** copy `en.json` to `xx.json`, fill it in, add it to the `EmbeddedResource` list in the `.csproj`, and register the code in `LocaleCodes.cs`. Translation-only PRs are great; keep them small (one language is ideal).

---

## Build

You'll need Windows x64, a .NET SDK (net472 build + net8 for validation), a Valheim install for references, and CMake + VS 2022 C++ (MSVC x64) for the native DLL.

Projects default to:

`D:\SteamLibrary\steamapps\common\Valheim`

Pass `-p:GamePath="..."` / `-GamePath` if yours is elsewhere.

**1. Managed menu**

```powershell
dotnet build ValheimAdminMenu/ValheimAdminMenu.csproj -c Release -p:GamePath="D:\SteamLibrary\steamapps\common\Valheim"
```

That drops `ValheavenModMenu.dll` + `0Harmony.dll` under `ValheimAdminMenu/bin/Release/net472/payload/`. Those get baked into `version.dll` next (ILRepack can't merge this Unity assembly cleanly).

**2. Native host**

```powershell
.\Native\VersionProxy\Build-VersionDll.ps1 -RepoRoot .
```

Produces `version.dll` at the repo root. More notes in [`Native/VersionProxy/README.md`](Native/VersionProxy/README.md).

**3. Optional checks**

```powershell
.\Build-And-Validate.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Valheim"
```

**4. Install**

```powershell
.\Install-Valheaven.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Valheim"
```

---

## Contributing

Branch from `main` and keep pull requests focused. Keep build outputs (`bin/`, `obj/`, DLLs, PDBs, and archives) out of commits.

Before you open a PR:

- Release build works against your Valheim path
- `Build-And-Validate.ps1` is nice to have green
- UI copy: update `en.json` first; say what's still English elsewhere
- Mention what you actually clicked in-game (Valheim version + tabs)

```
ValheimAdminMenu/     C# menu + patches
  Locales/            JSON string packs
Native/VersionProxy/  version.dll host
Validation/           offline checks
```

---

## Maintainer

[InfusedChooch](https://github.com/InfusedChooch) leads development and maintains Boneforge Edition.

Valheim is © Iron Gate AB / Coffee Stain.
