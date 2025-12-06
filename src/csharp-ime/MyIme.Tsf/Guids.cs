namespace MyIme.Tsf;

/// <summary>
/// GUIDs used for TSF registration
/// </summary>
public static class Guids
{
    /// <summary>
    /// CLSID for the Text Service
    /// Generate new GUIDs for your IME using: [System.Guid]::NewGuid()
    /// </summary>
    public const string TextService = "A1B2C3D4-1234-5678-9ABC-DEF012345678";

    /// <summary>
    /// Profile GUID for the Text Service
    /// </summary>
    public const string Profile = "B2C3D4E5-2345-6789-ABCD-EF0123456789";

    /// <summary>
    /// Display attribute provider GUID
    /// </summary>
    public const string DisplayAttributeProvider = "C3D4E5F6-3456-789A-BCDE-F01234567890";

    /// <summary>
    /// GUID for composing display attribute
    /// </summary>
    public const string DisplayAttributeComposing = "D4E5F6A7-4567-89AB-CDEF-012345678901";

    /// <summary>
    /// GUID for converted display attribute
    /// </summary>
    public const string DisplayAttributeConverted = "E5F6A7B8-5678-9ABC-DEF0-123456789012";
}

/// <summary>
/// TSF Category GUIDs
/// </summary>
public static class TsfCategories
{
    public static readonly Guid TipKeyboard = new("34745C63-B2F0-4784-8B67-5E12C8701A31");
    public static readonly Guid TipNoKeyboard = new("4C0F4E31-F0AB-4ED3-8F08-8EB16E1E7CA3");
    public static readonly Guid CategoryDisplayAttributeProvider = new("046B8C80-1647-40F7-9B21-B93B81AABC1B");
}
