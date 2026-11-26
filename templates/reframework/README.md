# REFramework menu

Copy this directory and edit the project name and version in `CMakeLists.txt`. Use a unique identifier such as `MapleRE`. CMake applies it to the DLL, Lua filename, Lua bridge table and settings filename.

## Build and test

Use Windows x64, Visual Studio 2022 with Desktop development with C++, and CMake 3.24+. The reference SDK revision is `e6c8c59264ec5053a09e1a8530262fd4f36804d1` of praydog/REFramework. For the sample build, run `git clone https://github.com/praydog/REFramework.git` in your dependency directory, then `git -C REFramework checkout --detach e6c8c59264ec5053a09e1a8530262fd4f36804d1`.

~~~powershell
$ref = 'C:/deps/REFramework'
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 "-DREF_INCLUDE_DIR=$ref/include" "-DREF_LUA_DIR=$ref/dependencies/lua/src"
cmake --build build --config Release
ctest --test-dir build -C Release --output-on-failure
cmake --install build --config Release --prefix stage
~~~

The test host loads the built DLL, checks callback registration and recreates the Lua state. It exercises the generated script with simulated UI input. The staging command produces matching `reframework/plugins/<project>.dll` and `reframework/autorun/<project>.lua` files.

For in-game use, build against the SDK and Lua sources **matching your installed REFramework host and its Lua build configuration**. The plug-in API version check covers callback compatibility. Linking the matching Lua implementation is also required because the DLL calls into a host-owned Lua state. Copy the staged package beside the game executable when ready to test.

## Extend the menu

Open **Script Generated UI**, expand the project name, and select **Overview**. It shows the native bridge version, adapter status, and why the area feature is unavailable. The bridge table is created for each Lua state. In `Plugin.cpp`, make `currentArea` push the current area's name with `lua_pushstring` when available, or keep returning Lua nil while waiting for a session.

In **Settings**, change **Show control hints** and reload scripts. REFramework saves the value in its data directory as `<project>.json`. Add a page in `Menu.lua.in` by appending `{"Journal", function() imgui.text("No entries yet.") end}` to `pages`, then rebuild and stage the pair. Keep the included license notices in distributions. [REFramework UI callback reference](https://cursey.github.io/reframework-book/api/re.html#reon_draw_uifunction)
