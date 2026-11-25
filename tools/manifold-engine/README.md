# Manifold Engine

[Download the portable Windows x64 ZIP](Manifold-Engine-e9b5e8de-win-x64.zip) to open and test Cheat Engine tables (`.CT`). Extract the entire ZIP into a writable folder, start `Manifold-Engine.exe`, and press **Ctrl+O** to open a table. Use **Ctrl+Shift+S** to save a copy. You can open and save a table without attaching to a process.

Open tables from the hub's shared `tables/` folder with **Ctrl+O**.

## Build identity

| Item | Value |
| --- | --- |
| Source | [InfusedChooch/Manifold-Engine at e9b5e8de](https://github.com/InfusedChooch/Manifold-Engine/tree/e9b5e8de67e4b6e575a361bec3a56aed894e82ba), forked from [Leunsel/Manifold-Engine](https://github.com/Leunsel/Manifold-Engine) |
| ZIP SHA-256 | `3ba64780048e6f7cd57d04581b626c4dfcb6d287084f6329a453e234daefb41b` |
| Licenses | The archive includes the project's MIT license and third-party notices. |

## Rebuild

Use a Visual Studio 2022 Developer PowerShell with the Desktop development with C++ workload, the C++ Clang compiler for Windows, MSBuild support for LLVM, Python 3, and the .NET SDK. From the hub root, run each command after the preceding one succeeds.

```powershell
git submodule update --init -- tools/manifold-engine/source
Set-Location tools/manifold-engine/source
msbuild Manifold-Engine.sln /m /p:Configuration=Release /p:Platform=x64
.\Build\x64\Release\Manifold-Engine.Tests.exe
$revision = git rev-parse --short=8 HEAD
$output = Join-Path $env:TEMP ("manifold-package-" + [guid]::NewGuid())
.\Tools\Package-Release.ps1 -Version $revision -Destination $output
Get-FileHash (Join-Path $output "Manifold-Engine-$revision-win-x64.zip") -Algorithm SHA256
```

The packager writes the portable ZIP and a separate debug-symbol ZIP into `$output`. The hub distributes the portable ZIP. Its checksum above identifies the exact archive supplied here.
