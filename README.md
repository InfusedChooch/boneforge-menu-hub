# Boneforge Menu Hub

Source, builds, and installation guides for three PC game menus. InfusedChooch maintains the hub.

| Game | Project | Windows download |
| --- | --- | --- |
| Valheim | [Valheaven Boneforge Edition](games/valheim/) | [Valheaven 4.0.0](https://github.com/InfusedChooch/boneforge-valheaven/releases/tag/v4.0.0) |
| Monster Hunter Wilds | [GHL QOL](games/monster-hunter-wilds/) | [Native plug-in preview](https://github.com/InfusedChooch/boneforge-valheaven/releases/tag/wilds-native-v0.0.23) |
| No Man's Sky | [Open Skies](games/no-mans-sky/) | [Open Skies 1.0.5](https://github.com/InfusedChooch/boneforge-valheaven/releases/tag/open-skies-v1.0.5) |

## Get the source

```powershell
git clone --recurse-submodules https://github.com/InfusedChooch/boneforge-valheaven.git
```

For an existing checkout, initialize the pinned third-party libraries with `git submodule update --init --recursive`. Each game folder has its own build and installation instructions.
