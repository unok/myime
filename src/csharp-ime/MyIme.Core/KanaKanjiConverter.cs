using System.Text.Json;

namespace MyIme.Core;

/// <summary>
/// High-level wrapper for the AzooKey Kana-Kanji converter
/// </summary>
public sealed class KanaKanjiConverter : IDisposable
{
    private bool _isInitialized;
    private bool _disposed;

    /// <summary>
    /// Configuration for the converter
    /// </summary>
    public ConverterConfig Config { get; }

    public KanaKanjiConverter(ConverterConfig? config = null)
    {
        Config = config ?? new ConverterConfig();
    }

    /// <summary>
    /// Initialize the converter
    /// </summary>
    public void Initialize()
    {
        ThrowIfDisposed();

        if (_isInitialized)
            return;

        if (!string.IsNullOrEmpty(Config.ConfigPath))
        {
            NativeMethods.LoadConfig(Config.ConfigPath);
        }

        NativeMethods.Initialize(Config.DictionaryPath, Config.MemoryPath);

        if (Config.ZenzaiEnabled.HasValue)
        {
            NativeMethods.SetZenzaiEnabled(Config.ZenzaiEnabled.Value);
        }

        if (Config.ZenzaiInferenceLimit.HasValue)
        {
            NativeMethods.SetZenzaiInferenceLimit(Config.ZenzaiInferenceLimit.Value);
        }

        _isInitialized = true;
    }

    /// <summary>
    /// Append text to the composing buffer
    /// </summary>
    public void AppendText(string input)
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.AppendText(input);
    }

    /// <summary>
    /// Remove characters from the composing buffer
    /// </summary>
    public void RemoveText(int count = 1)
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.RemoveText(count);
    }

    /// <summary>
    /// Move cursor position
    /// </summary>
    public void MoveCursor(int offset)
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.MoveCursor(offset);
    }

    /// <summary>
    /// Clear all composing text
    /// </summary>
    public void ClearText()
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.ClearText();
    }

    /// <summary>
    /// Get the best composed text result
    /// </summary>
    public string? GetComposedText()
    {
        ThrowIfDisposed();
        EnsureInitialized();
        return NativeMethods.GetComposedText();
    }

    /// <summary>
    /// Get all conversion candidates
    /// </summary>
    public IReadOnlyList<string> GetCandidates()
    {
        ThrowIfDisposed();
        EnsureInitialized();

        var json = NativeMethods.GetCandidates();
        if (string.IsNullOrEmpty(json))
            return Array.Empty<string>();

        try
        {
            return JsonSerializer.Deserialize<List<string>>(json) ?? new List<string>();
        }
        catch (JsonException)
        {
            return Array.Empty<string>();
        }
    }

    /// <summary>
    /// Select a candidate by index
    /// </summary>
    public void SelectCandidate(int index)
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.SelectCandidate(index);
    }

    /// <summary>
    /// Shrink the current conversion segment
    /// </summary>
    public void ShrinkSegment()
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.ShrinkText();
    }

    /// <summary>
    /// Expand the current conversion segment
    /// </summary>
    public void ExpandSegment()
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.ExpandText();
    }

    /// <summary>
    /// Set preceding text for context-aware conversion
    /// </summary>
    public void SetContext(string? precedingText)
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.SetContext(precedingText);
    }

    /// <summary>
    /// Enable or disable Zenzai AI conversion
    /// </summary>
    public void SetZenzaiEnabled(bool enabled)
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.SetZenzaiEnabled(enabled);
    }

    /// <summary>
    /// Set the inference limit for Zenzai
    /// </summary>
    public void SetZenzaiInferenceLimit(int limit)
    {
        ThrowIfDisposed();
        EnsureInitialized();
        NativeMethods.SetZenzaiInferenceLimit(limit);
    }

    private void EnsureInitialized()
    {
        if (!_isInitialized)
        {
            Initialize();
        }
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    public void Dispose()
    {
        if (_disposed)
            return;

        if (_isInitialized)
        {
            NativeMethods.Shutdown();
            _isInitialized = false;
        }

        _disposed = true;
    }
}

/// <summary>
/// Configuration for the KanaKanjiConverter
/// </summary>
public class ConverterConfig
{
    /// <summary>
    /// Path to JSON configuration file
    /// </summary>
    public string? ConfigPath { get; set; }

    /// <summary>
    /// Path to dictionary directory
    /// </summary>
    public string? DictionaryPath { get; set; }

    /// <summary>
    /// Path to memory/learning data directory
    /// </summary>
    public string? MemoryPath { get; set; }

    /// <summary>
    /// Enable Zenzai AI conversion
    /// </summary>
    public bool? ZenzaiEnabled { get; set; }

    /// <summary>
    /// Inference limit for Zenzai
    /// </summary>
    public int? ZenzaiInferenceLimit { get; set; }
}
