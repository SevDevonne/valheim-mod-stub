# Valerius Mod Stub

## 1. Configure

Edit **`ModConfig.props`** — set the mod name, GUID, version, description and local paths. **Only this file needs changing** when setting up a new mod or updating its version.
 Keep the name `Plugin.cs` unchanged - its namespace is generated from `ModName` at build time.

## 2. Build

```powershell
dotnet clean -c Debug    # Remove files deployed to plugins folder
dotnet build -c Debug    # Deploy to configured Valheim plugins folder

dotnet build -c Release  # Create Thunderstore ZIP in ../Releases
```
