# Boneforge Menu Hub

Boneforge's workspace for PC game mods and modding tools. Game projects live under `games/` and shared tools under `tools/`. InfusedChooch maintains the hub.

| Game | Project | Download or install |
| --- | --- | --- |
| Valheim | [Valheaven Boneforge Edition](games/valheim/) | [Valheaven 4.0.2](https://github.com/InfusedChooch/boneforge-menu-hub/releases/tag/v4.0.2) |
| Monster Hunter Wilds | [Boneforge Wilds](games/monster-hunter-wilds/) | [Public Lua menu 0.1.0 for REFramework](https://github.com/InfusedChooch/boneforge-menu-hub/releases/tag/wilds-public-v0.1.0) |
| No Man's Sky | [Open Skies](games/no-mans-sky/) | [Open Skies 1.0.5](https://github.com/InfusedChooch/boneforge-menu-hub/releases/tag/open-skies-v1.0.5) |
| Warhammer 40,000: Darktide | [Lua ESP and Gambits](games/darktide/) | [Install from source](games/darktide/#installation) |
| Warhammer: Vermintide 2 | [Game script reference](games/vermintide-2/) | [Initialize the submodule](games/vermintide-2/#get-the-reference) |

## Tools

- [Manifold Engine](tools/manifold-engine/) includes a portable Windows x64 build for opening and testing Cheat Engine tables.
- [GHL CE/DMA](tools/ghl-ce-dma/) contains the pinned source package for the GHL edition of Cheat Engine and its DMA plugin. Make tool changes in this checkout and push them to the tool's own repository.

## Get the source

```powershell
git clone --recurse-submodules https://github.com/InfusedChooch/boneforge-menu-hub.git
```

For an existing checkout, initialize the pinned tools, libraries, and game script references with `git submodule update --init --recursive`. Each project folder has its own setup instructions.
