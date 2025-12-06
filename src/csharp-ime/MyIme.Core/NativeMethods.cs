using System.Runtime.InteropServices;

namespace MyIme.Core;

/// <summary>
/// P/Invoke bindings for the Swift azookey-engine DLL
/// </summary>
public static partial class NativeMethods
{
    private const string DllName = "azookey-engine";

    #region Configuration and Initialization

    /// <summary>
    /// Load configuration from a JSON file
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "LoadConfig", StringMarshalling = StringMarshalling.Utf8)]
    public static partial void LoadConfig(string? configPath);

    /// <summary>
    /// Initialize the converter with dictionary and memory paths
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "Initialize", StringMarshalling = StringMarshalling.Utf8)]
    public static partial void Initialize(string? dictionaryPath, string? memoryPath);

    /// <summary>
    /// Shutdown and cleanup the converter
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "Shutdown")]
    public static partial void Shutdown();

    #endregion

    #region Text Composition

    /// <summary>
    /// Append text to the composing buffer
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "AppendText", StringMarshalling = StringMarshalling.Utf8)]
    public static partial void AppendText(string? input);

    /// <summary>
    /// Remove characters from the composing buffer
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "RemoveText")]
    public static partial void RemoveText(int count);

    /// <summary>
    /// Move cursor position
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "MoveCursor")]
    public static partial void MoveCursor(int offset);

    /// <summary>
    /// Clear all composing text
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "ClearText")]
    public static partial void ClearText();

    #endregion

    #region Conversion

    /// <summary>
    /// Get the best composed text result
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "GetComposedText")]
    private static partial nint GetComposedTextNative();

    /// <summary>
    /// Get all conversion candidates as JSON array
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "GetCandidates")]
    private static partial nint GetCandidatesNative();

    /// <summary>
    /// Select a candidate by index
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "SelectCandidate")]
    public static partial void SelectCandidate(int index);

    /// <summary>
    /// Shrink the current conversion segment
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "ShrinkText")]
    public static partial void ShrinkText();

    /// <summary>
    /// Expand the current conversion segment
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "ExpandText")]
    public static partial void ExpandText();

    #endregion

    #region Context

    /// <summary>
    /// Set preceding text for context-aware conversion
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "SetContext", StringMarshalling = StringMarshalling.Utf8)]
    public static partial void SetContext(string? precedingText);

    #endregion

    #region Zenzai Settings

    /// <summary>
    /// Enable or disable Zenzai AI conversion
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "SetZenzaiEnabled")]
    public static partial void SetZenzaiEnabled([MarshalAs(UnmanagedType.Bool)] bool enabled);

    /// <summary>
    /// Set the inference limit for Zenzai
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "SetZenzaiInferenceLimit")]
    public static partial void SetZenzaiInferenceLimit(int limit);

    #endregion

    #region Memory Management

    /// <summary>
    /// Free a string allocated by the Swift DLL
    /// </summary>
    [LibraryImport(DllName, EntryPoint = "FreeString")]
    private static partial void FreeString(nint str);

    #endregion

    #region Managed Wrappers

    /// <summary>
    /// Get the best composed text result (managed wrapper)
    /// </summary>
    public static string? GetComposedText()
    {
        var ptr = GetComposedTextNative();
        if (ptr == nint.Zero)
            return null;

        try
        {
            return Marshal.PtrToStringUTF8(ptr);
        }
        finally
        {
            FreeString(ptr);
        }
    }

    /// <summary>
    /// Get all conversion candidates as JSON array (managed wrapper)
    /// </summary>
    public static string? GetCandidates()
    {
        var ptr = GetCandidatesNative();
        if (ptr == nint.Zero)
            return null;

        try
        {
            return Marshal.PtrToStringUTF8(ptr);
        }
        finally
        {
            FreeString(ptr);
        }
    }

    #endregion
}
