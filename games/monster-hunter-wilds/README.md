# GHL QOL for Monster Hunter Wilds

This source snapshot comes from GHL QOL 0.0.23. The C++ menu and host adapters are in `native/src/`. The Lua menu pages and gameplay integrations are in `source/reframework/autorun/`.

## Install the native plug-in

Download the [Windows plug-in preview](https://github.com/InfusedChooch/boneforge-valheaven/releases/tag/wilds-native-v0.0.23) and follow its [setup guide](INSTALL.txt). It adds the native UI to an existing compatible GHL QOL Lua setup.

## Build the native menu plug-in

Use Windows x64, Visual Studio 2022 C++ tools, CMake 3.24 or newer, and Python. Run these commands from this directory.

```powershell
python tools/prepare_native_deps.py
cmake -S native -B build -G "Visual Studio 17 2022" -A x64 -DBUILD_TESTING=OFF
cmake --build build --config Release --target GHLQOL
```

The `GHLQOL` target produces the native REFramework menu plug-in at `build/Release/GHLQOL.dll`. The complete in-game package also uses the separately sourced RefShell bundle and Buffer modules, layered-gear and Gogma preset data, and the original WpSeries Great Sword and GenSeries Parry Window engines. This hub provides the menu source and the native plug-in build.

## Build the external-host package locally

If you already have the complete local GHL QOL content, set `GHLQOL_CONTENT_ROOT` to the project directory containing `source/` and `native/payloads/`. The build verifies the engine inputs against that project's provenance manifest.

```powershell
$contentRoot = 'C:/path/to/your/GHLQOL'
cmake -S native -B build-external -G "Visual Studio 17 2022" -A x64 -DBUILD_TESTING=OFF "-DGHLQOL_CONTENT_ROOT=$contentRoot"
cmake --build build-external --config Release --target GHLQOLRoot
```

The full local package appears at `build-external/Release/version.dll` and requires an existing compatible host. Its separately supplied content stays in your local project directory.

## License

See [LICENSE](LICENSE) and the license headers in the source. AutoGuardGS includes its [own GPLv3 license copy](source/reframework/autorun/ParryMeister/AutoGuardGS/LICENSE.txt).
