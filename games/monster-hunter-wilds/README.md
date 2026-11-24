# GHL QOL for Monster Hunter Wilds

This source snapshot comes from GHL QOL 0.0.23. The C++ menu and host adapters are in `native/src/`. The Lua menu pages and gameplay integrations are in `source/reframework/autorun/`.

## Build the native menu plug-in

Use Windows x64, Visual Studio 2022 C++ tools, CMake 3.24 or newer, and Python. Run these commands from this directory.

```powershell
python tools/prepare_native_deps.py
cmake -S native -B build -G "Visual Studio 17 2022" -A x64 -DBUILD_TESTING=OFF
cmake --build build --config Release --target GHLQOL
```

The `GHLQOL` target produces the native REFramework menu plug-in at `build/Release/GHLQOL.dll`. The complete in-game package also uses the separately sourced RefShell bundle and Buffer modules, layered-gear and Gogma preset data, and the original WpSeries Great Sword and GenSeries Parry Window engines. This hub provides the menu source and the native plug-in build.

## License

See [LICENSE](LICENSE) and the license headers in the source. AutoGuardGS includes its [own GPLv3 license copy](source/reframework/autorun/ParryMeister/AutoGuardGS/LICENSE.txt).
