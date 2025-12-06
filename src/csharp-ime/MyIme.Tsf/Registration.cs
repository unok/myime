using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace MyIme.Tsf;

/// <summary>
/// Handles COM and TSF registration for the IME
/// </summary>
public static class Registration
{
    private const string ImeName = "MyIme Japanese";
    private const string ImeDescription = "MyIme - Japanese Input Method";
    private const ushort LangIdJapanese = 0x0411;

    /// <summary>
    /// Register the IME with Windows
    /// </summary>
    public static void Register()
    {
        RegisterComServer();
        RegisterTextService();
    }

    /// <summary>
    /// Unregister the IME from Windows
    /// </summary>
    public static void Unregister()
    {
        UnregisterTextService();
        UnregisterComServer();
    }

    private static void RegisterComServer()
    {
        var clsid = new Guid(Guids.TextService);
        var typeLibPath = typeof(TextService).Assembly.Location;

        // HKEY_CLASSES_ROOT\CLSID\{guid}
        using var clsidKey = Registry.ClassesRoot.CreateSubKey($@"CLSID\{{{clsid}}}");
        clsidKey?.SetValue(null, ImeDescription);

        // InprocServer32
        using var inprocKey = clsidKey?.CreateSubKey("InprocServer32");
        inprocKey?.SetValue(null, typeLibPath);
        inprocKey?.SetValue("ThreadingModel", "Apartment");
    }

    private static void UnregisterComServer()
    {
        var clsid = new Guid(Guids.TextService);
        try
        {
            Registry.ClassesRoot.DeleteSubKeyTree($@"CLSID\{{{clsid}}}", false);
        }
        catch
        {
            // Ignore errors during unregistration
        }
    }

    private static void RegisterTextService()
    {
        var clsid = new Guid(Guids.TextService);
        var profileGuid = new Guid(Guids.Profile);

        // Register with TSF
        var categoryMgr = CreateCategoryMgr();
        var profileMgr = CreateInputProcessorProfiles();

        try
        {
            // Register CLSID
            profileMgr?.Register(ref clsid);

            // Add language profile
            profileMgr?.AddLanguageProfile(
                ref clsid,
                LangIdJapanese,
                ref profileGuid,
                ImeName,
                (uint)ImeName.Length,
                null, // Icon file
                0,    // Icon index
                0     // Icon resource
            );

            // Register categories
            var tipKeyboard = TsfCategories.TipKeyboard;
            categoryMgr?.RegisterCategory(ref clsid, ref tipKeyboard, ref clsid);
        }
        finally
        {
            if (categoryMgr != null)
                Marshal.ReleaseComObject(categoryMgr);
            if (profileMgr != null)
                Marshal.ReleaseComObject(profileMgr);
        }
    }

    private static void UnregisterTextService()
    {
        var clsid = new Guid(Guids.TextService);

        var profileMgr = CreateInputProcessorProfiles();
        try
        {
            profileMgr?.Unregister(ref clsid);
        }
        finally
        {
            if (profileMgr != null)
                Marshal.ReleaseComObject(profileMgr);
        }
    }

    private static ITfCategoryMgr? CreateCategoryMgr()
    {
        var clsid = new Guid("A4B544A1-438D-4B41-9325-869523E2D6C7");
        var iid = typeof(ITfCategoryMgr).GUID;

        if (CoCreateInstance(ref clsid, nint.Zero, 1, ref iid, out var obj) == 0)
        {
            return obj as ITfCategoryMgr;
        }

        return null;
    }

    private static ITfInputProcessorProfiles? CreateInputProcessorProfiles()
    {
        var clsid = new Guid("33C53A50-F456-4884-B049-85FD643ECFED");
        var iid = typeof(ITfInputProcessorProfiles).GUID;

        if (CoCreateInstance(ref clsid, nint.Zero, 1, ref iid, out var obj) == 0)
        {
            return obj as ITfInputProcessorProfiles;
        }

        return null;
    }

    [DllImport("ole32.dll")]
    private static extern int CoCreateInstance(
        ref Guid rclsid,
        nint pUnkOuter,
        uint dwClsContext,
        ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out object ppv);
}

// ITfCategoryMgr
[ComImport]
[Guid("C3ACEFB5-F69D-4905-938F-FCADCF4BE830")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfCategoryMgr
{
    void RegisterCategory(ref Guid rclsid, ref Guid rcatid, ref Guid rguid);
    void UnregisterCategory(ref Guid rclsid, ref Guid rcatid, ref Guid rguid);
    void EnumCategoriesInItem(ref Guid rguid, out object ppEnum);
    void EnumItemsInCategory(ref Guid rcatid, out object ppEnum);
    void FindClosestCategory(ref Guid rguid, out Guid pcatid, [In] ref Guid[] ppcatidList, uint ulCount);
    void RegisterGUIDDescription(ref Guid rclsid, ref Guid rguid, [MarshalAs(UnmanagedType.LPWStr)] string pchDesc, uint cch);
    void UnregisterGUIDDescription(ref Guid rclsid, ref Guid rguid);
    void GetGUIDDescription(ref Guid rguid, [MarshalAs(UnmanagedType.BStr)] out string pbstrDesc);
    void RegisterGUIDDWORD(ref Guid rclsid, ref Guid rguid, uint dw);
    void UnregisterGUIDDWORD(ref Guid rclsid, ref Guid rguid);
    void GetGUIDDWORD(ref Guid rguid, out uint pdw);
    void RegisterGUID(ref Guid rguid, out uint pguidatom);
    void GetGUID(uint guidatom, out Guid pguid);
    void IsEqualTfGuidAtom(uint guidatom, ref Guid rguid, [MarshalAs(UnmanagedType.Bool)] out bool pfEqual);
}

// ITfInputProcessorProfiles
[ComImport]
[Guid("1F02B6C5-7842-4EE6-8A0B-9A24183A95CA")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfInputProcessorProfiles
{
    void Register(ref Guid rclsid);
    void Unregister(ref Guid rclsid);
    void AddLanguageProfile(
        ref Guid rclsid,
        ushort langid,
        ref Guid guidProfile,
        [MarshalAs(UnmanagedType.LPWStr)] string pchDesc,
        uint cchDesc,
        [MarshalAs(UnmanagedType.LPWStr)] string? pchIconFile,
        uint cchFile,
        uint uIconIndex);
    void RemoveLanguageProfile(ref Guid rclsid, ushort langid, ref Guid guidProfile);
    void EnumInputProcessorInfo(out object ppEnum);
    void GetDefaultLanguageProfile(ushort langid, ref Guid catid, out Guid pclsid, out Guid pguidProfile);
    void SetDefaultLanguageProfile(ushort langid, ref Guid rclsid, ref Guid guidProfiles);
    void ActivateLanguageProfile(ref Guid rclsid, ushort langid, ref Guid guidProfiles);
    void GetActiveLanguageProfile(ref Guid rclsid, out ushort plangid, out Guid pguidProfile);
    void GetLanguageProfileDescription(ref Guid rclsid, ushort langid, ref Guid guidProfile, [MarshalAs(UnmanagedType.BStr)] out string pbstrProfile);
    void GetCurrentLanguage(out ushort plangid);
    void ChangeCurrentLanguage(ushort langid);
    void GetLanguageList(out nint ppLangId, out uint pulCount);
    void EnumLanguageProfiles(ushort langid, out object ppEnum);
    void EnableLanguageProfile(ref Guid rclsid, ushort langid, ref Guid guidProfile, [MarshalAs(UnmanagedType.Bool)] bool fEnable);
    void IsEnabledLanguageProfile(ref Guid rclsid, ushort langid, ref Guid guidProfile, [MarshalAs(UnmanagedType.Bool)] out bool pfEnable);
    void EnableLanguageProfileByDefault(ref Guid rclsid, ushort langid, ref Guid guidProfile, [MarshalAs(UnmanagedType.Bool)] bool fEnable);
    void SubstituteKeyboardLayout(ref Guid rclsid, ushort langid, ref Guid guidProfile, nint hKL);
}
