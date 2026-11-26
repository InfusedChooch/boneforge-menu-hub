# Warhammer 40,000: Darktide

This folder contains two imported Darktide Mod Framework (DMF) mods and the Boneforge Observer diagnostic mod. The initial import on November 25, 2026 preserves the installed Lua files, manifests, and original Apache 2.0 licenses. Those files matched the corresponding source archives byte for byte.

| Mod | In-game name | Source archive revision |
| --- | --- | --- |
| [darktide-lua-esp](darktide-lua-esp/) | gir489's ESP. Draws enemy boxes, names, and health bars. | `db417906d5add0a295bc16fd91caa147d6f7656a` |
| [darktide-lua-gambits](darktide-lua-gambits/) | Priority Target Auto-Aim. Provides configurable targeting and combat assists. | `05e62fcc997b981ccf3318c1c718e107a579c4cc` |

### Boneforge Observer

Install [boneforge-observer](boneforge-observer/) in the game's `mods` folder and enable `boneforge-observer` in the load order. In DMF, enable Info logging and choose the values to record under **Boneforge Observer**. Open a menu that shows a wallet or your operative's talent tree. Open the newest log under `%APPDATA%\Fatshark\Darktide\console_logs` and search for `display baseline` or `display change`.

Observer compares wallet readings across the shared wallet widget, inventory and crafting menus. A new session or operative starts a fresh baseline. A change line gives the currency, new value, previous value, signed difference and source screen. Talent points are tracked separately for each view and layout.

For a one-item check, open your inventory and record the credits baseline and the quoted item value. After selling once, look for `currency notice` and the next credits reading. A notice reports what the UI announced. Only a wallet reading establishes the new displayed balance. If the selling screen does not refresh its wallet, reopen inventory. For errors, search the same log for `UI alert` and DMF's `[ERROR]` entries.

With wallet logging enabled, successful purchases at Requisition and Brunt's Armoury produce numbered `armoury purchase` entries. Match the item, quoted credit price and last displayed balance to the wallet refresh with the same number. Rapid purchases can share a final balance. If the shop closes before the refresh, the receipt marks the reading unavailable.

With talent logging enabled, `talent allocated` and `talent refunded` entries record node names, old and new ranks and the signed change in points spent. These describe edits visible in your own talent tree. Opening the tree or changing presets establishes a baseline.

### Game source reference

The [Darktide source fork](https://github.com/InfusedChooch/Darktide-Source-Code) is pinned as a Git submodule at `external/Darktide-Source-Code/`. The initial pin is the [1.13.4 script snapshot](https://github.com/InfusedChooch/Darktide-Source-Code/commit/e46b8926cfa3fa35503e4b80b15aab7a804314e4). This reference is used to compare script paths and signatures when diagnosing compatibility after a game update.

From the hub root, fetch the pinned checkout with:

```powershell
git submodule update --init -- games/darktide/external/Darktide-Source-Code
```

When updating the pin, record the Darktide patch that the new commit represents and rerun the checks below.

### Installation

1. Close Darktide. Use a working Darktide Mod Loader and Darktide Mod Framework installation.
2. Copy the mod folders you want into the game's `mods` directory. Each folder's `.mod` file must sit directly inside it. If Vortex manages your installation, deploy updated copies through Vortex so a later deployment keeps your changes.
3. Enable `darktide-lua-esp` and `darktide-lua-gambits` in the load order. For a manual installation, add each folder name on its own line in `mods/mod_load_order.txt`. Preserve the existing entries. ESP registers internally as `espenis`; its load-order entry is `darktide-lua-esp`.
4. Launch Darktide and open DMF's Mod Options. Look for both in-game names listed above.

### After a game update

Run `luajit check.lua` from this directory. It checks the manifests, compiles their Lua entry points, and loads their settings and English display names.

Then check the updated game with DMF enabled. In the Psykhanium, toggle an ESP display option and confirm the overlay changes. For Gambits, select a target class, test its configured activation input, and confirm targeting stops on release. Check the Darktide console log for new Lua errors. Record the Steam build ID and which checks passed when updating either mod.
