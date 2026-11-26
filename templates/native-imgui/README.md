# Native ImGui menu

Copy this folder to a new project. Edit the name and version on the `project(...)` line of `CMakeLists.txt`. Use a unique identifier such as `MaplePreview`. It names the preview executable, menu window, and preference key.

## Build and try it

Use Windows x64, Visual Studio 2022 with Desktop development with C++, and CMake 3.24+. Point `IMGUI_DIR` at a Dear ImGui checkout at revision `f1cc2ae15e53a861a874c3034aae6798fde194ab`. To obtain the sources once, run `git clone https://github.com/ocornut/imgui.git` in your dependency directory, then `git -C imgui checkout --detach f1cc2ae15e53a861a874c3034aae6798fde194ab`.

~~~powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64 "-DIMGUI_DIR=C:/deps/imgui"
cmake --build build --config Release
.\build\Release\BoneforgePreview.exe
~~~

Use the new executable name after renaming. Click **Settings**, turn off **Show control hints**, then close the window and relaunch. The hint under Overview disappears. F8 hides or reopens the menu. The preview stores the preference under `HKCU\Software\Boneforge\Menus\<project>`.

## Connect a host

`Menu.h` takes two callbacks. Supply `currentArea` to return the area name, or an empty string while waiting for a session. Supply `saveDetails` to persist the preference and report success. Pass the loaded value to the constructor. Call `menu.draw()` between the host's ImGui frame start and render calls. The host forwards input, owns its renderer, and decides when the game receives keyboard and mouse events.

Register another tab before the first frame with `menu.addPage("Journal", [] { ImGui::TextUnformatted("No entries yet."); });`. The preview exercises the unavailable adapter path until a host supplies an area.

The preview's window and DX11 setup derives from Dear ImGui's Win32 example. Retain the included license files with copies. [Upstream integration guide](https://github.com/ocornut/imgui/wiki/Getting-Started)
