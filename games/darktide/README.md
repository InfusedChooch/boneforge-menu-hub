# Warhammer 40,000: Darktide

This folder contains the two Darktide Mod Framework (DMF) mods maintained in the hub. The initial import on November 25, 2026 preserves the installed Lua files, manifests, and original Apache 2.0 licenses. Those files matched the corresponding source archives byte for byte.

| Mod | In-game name | Source archive revision |
| --- | --- | --- |
| [darktide-lua-esp](darktide-lua-esp/) | gir489's ESP. Draws enemy boxes, names, and health bars. | `db417906d5add0a295bc16fd91caa147d6f7656a` |
| [darktide-lua-gambits](darktide-lua-gambits/) | Priority Target Auto-Aim. Provides configurable targeting and combat assists. | `05e62fcc997b981ccf3318c1c718e107a579c4cc` |

### Game source reference

The [Darktide source fork](https://github.com/InfusedChooch/Darktide-Source-Code) is pinned as a Git submodule at `external/Darktide-Source-Code/`. The initial pin is the [1.13.4 script snapshot](https://github.com/InfusedChooch/Darktide-Source-Code/commit/e46b8926cfa3fa35503e4b80b15aab7a804314e4). This reference is used to compare script paths and signatures when diagnosing compatibility after a game update.

From the hub root, fetch the pinned checkout with:

```powershell
git submodule update --init -- games/darktide/external/Darktide-Source-Code
```

When updating the pin, record the Darktide patch that the new commit represents and rerun the checks below.

### Installation

1. Close Darktide. Use a working Darktide Mod Loader and Darktide Mod Framework installation.
2. Copy the two mod folders into the game's `mods` directory. Each folder's `.mod` file must sit directly inside it. If Vortex manages your installation, deploy updated copies through Vortex so a later deployment keeps your changes.
3. Enable `darktide-lua-esp` and `darktide-lua-gambits` in the load order. For a manual installation, add each folder name on its own line in `mods/mod_load_order.txt`. Preserve the existing entries. ESP registers internally as `espenis`; its load-order entry is `darktide-lua-esp`.
4. Launch Darktide and open DMF's Mod Options. Look for both in-game names listed above.

### After a game update

Run `luajit check.lua` from this directory. It checks both manifests, compiles their Lua entry points, and loads their settings and English display names.

Then check the updated game with DMF enabled. In the Psykhanium, toggle an ESP display option and confirm the overlay changes. For Gambits, select a target class, test its configured activation input, and confirm targeting stops on release. Check the Darktide console log for new Lua errors. Record the Steam build ID and which checks passed when updating either mod.
