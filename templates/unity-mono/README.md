# Unity Mono menu

Copy this folder and change `AssemblyName` and `Version` in `Menu.csproj`. Use a unique assembly name such as `MapleUnity`. It names the DLL, persistent scene object, and PlayerPrefs key. If one loader references multiple copies at compile time, give each copy its own C# namespace as well.

## Build and try it

Use the .NET SDK, .NET Framework 4.7.2 targeting pack, and the target game's Mono managed assemblies. The UI uses uGUI and legacy keyboard input. Supply the absolute path to the game's `*_Data/Managed` directory.

~~~powershell
dotnet build Menu.csproj -c Release "-p:UnityManagedDir=C:/Games/MyGame/MyGame_Data/Managed"
dotnet run --project checks/Lifecycle.csproj -c Release
~~~

The output is `bin/Release/net472/<AssemblyName>.dll`. The second command uses the .NET 8 SDK or later and a .NET 8 runtime to exercise the production entry point with stand-ins for Unity object creation, lifetime, and destruction.

Call `Boneforge.MenuStarter.Entry.Start()` from your loader on Unity's main thread when the player is initialized. Repeated calls reuse the persistent menu object. To enable **Read current area**, pass a callback such as `Entry.Start(() => SceneManager.GetActiveScene().name)` using `UnityEngine.SceneManagement`, or provide your game's own area name. Return an empty string while loading.

Press **F8** to open. Use **Left/Right** to switch pages and **Enter** to read the area or change **Show control hints**. Reopen across a scene change and restart the player to check the preference in a target game.

Building against Valheim's managed assemblies enables its chat input guard. Enter activates the open menu, and resumes opening chat once the menu closes.

## Add a page

In `MenuView.Awake`, add `pages.Add(new KeyValuePair<string, Action>("Journal", DrawJournal));` next to Settings. Implement `private void DrawJournal() => Draw("No entries yet.");` in the same class. The page becomes reachable with the same navigation keys.
