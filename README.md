# Boneforge Menu Hub

Source and releases for PC game menus. InfusedChooch maintains this hub.

| Game | Project | Get started |
| --- | --- | --- |
| Valheim | Valheaven \| Boneforge Edition | [Download](https://github.com/InfusedChooch/boneforge-valheaven/releases/tag/v4.0.0) · [Source](ValheimAdminMenu/) · [Build](#build) |
| Monster Hunter Wilds | GHL QOL | [Source and native plug-in build](games/monster-hunter-wilds/README.md) |
| No Man's Sky | Open Skies | [Pinned project source](games/no-mans-sky) · [Project README](https://github.com/InfusedChooch/open-skies/blob/221c42570e62978ffb20a4285f8706bd135138fb/README.md) |

From a Git checkout of this hub, retrieve Open Skies and its pinned dependencies with:

```powershell
git submodule update --init --recursive -- games/no-mans-sky
```

## Valheaven | Boneforge Edition

A Windows mod menu for Valheim with building, crafting, and world tools. It loads from `version.dll` alongside `valheim.exe` and runs without BepInEx.

- **Version** 4.0.0
- **Verified on** Valheim 1.0.21 on Windows through the title screen and menu.
- **Open menu** Press **F8** by default. Change the key in Settings.

### License

Boneforge Edition is available under the [GNU General Public License v3.0](LICENSE).

This is an unofficial Valheim mod. Iron Gate Studio and Coffee Stain Publishing are unaffiliated with the project. The mod is available free of charge and comes without warranty.

### Changelog

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

### What you get

A full overlay menu: character cheats and QoL, building / crafting helpers, item spawner + editor, farming, world tools (weather, terrain, structure copy/paste + blueprints), teleport bookmarks, camera stuff, ESP, events, and hotkey binds.

Settings, bookmarks, blueprints, and a log land next to the game folder. If that folder isn't writable, they go under `%AppData%\Valheaven\` instead.

---

### Install

1. Download the [Windows ZIP](https://github.com/InfusedChooch/boneforge-valheaven/releases/tag/v4.0.0) or build `version.dll` using the [build steps](#build).
2. Extract or copy `version.dll` next to `valheim.exe`. If you built from source, you can also use the install script:

```powershell
.\Install-Valheaven.ps1 -GamePath "D:\SteamLibrary\steamapps\common\Valheim"
```

3. Launch Valheim and hit **F8**.

Don't touch `winhttp.dll` / Doorstop for this mod.

To uninstall, delete `version.dll`. Optional leftovers: `Valheaven.settings.json`, `Valheaven.bookmarks.json`, `Valheaven.blueprints.json`, `Valheaven.log`, and a `blueprints\` folder.

---

### Localization

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

### Build

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

### Contributing

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

### Maintainer

[InfusedChooch](https://github.com/InfusedChooch) leads development and maintains Boneforge Edition.

Valheim is © Iron Gate AB / Coffee Stain.
