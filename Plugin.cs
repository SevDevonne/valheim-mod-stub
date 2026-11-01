using BepInEx;
using BepInEx.Logging;
using HarmonyLib;

namespace Valerius
{
    [BepInPlugin(ModIdentity.Guid, ModIdentity.Name, ModIdentity.Version)]
    public class Plugin : BaseUnityPlugin
    {
        internal static ManualLogSource Log;

        private void Awake()
        {
            Log = Logger;
            new Harmony(ModIdentity.Guid).PatchAll();
            Log.LogInfo($"{ModIdentity.Name} {ModIdentity.Version} loaded.");
        }
    }
}
