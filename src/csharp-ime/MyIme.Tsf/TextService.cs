using System.Runtime.InteropServices;
using MyIme.Core;
using MyIme.Tsf.Interop;

namespace MyIme.Tsf;

/// <summary>
/// Main Text Service implementation for the IME
/// </summary>
[ComVisible(true)]
[Guid(Guids.TextService)]
[ClassInterface(ClassInterfaceType.None)]
public sealed class TextService : ITfTextInputProcessorEx, ITfKeyEventSink, ITfThreadMgrEventSink, IDisposable
{
    private ITfThreadMgr? _threadMgr;
    private uint _clientId;
    private ITfKeystrokeMgr? _keystrokeMgr;
    private uint _threadMgrEventSinkCookie;
    private KanaKanjiConverter? _converter;
    private bool _disposed;

    private ComposingState _composingState = new();

    public TextService()
    {
        _converter = new KanaKanjiConverter();
    }

    #region ITfTextInputProcessor

    public void Activate(ITfThreadMgr threadMgr, uint clientId)
    {
        ActivateEx(threadMgr, clientId, 0);
    }

    public void Deactivate()
    {
        // Unadvise key event sink
        _keystrokeMgr?.UnadviseKeyEventSink(_clientId);
        _keystrokeMgr = null;

        _threadMgr = null;
        _clientId = 0;

        _converter?.Dispose();
        _converter = null;
    }

    #endregion

    #region ITfTextInputProcessorEx

    public void ActivateEx(ITfThreadMgr threadMgr, uint clientId, uint flags)
    {
        _threadMgr = threadMgr;
        _clientId = clientId;

        // Initialize converter
        _converter?.Initialize();

        // Get keystroke manager and advise key event sink
        if (_threadMgr is ITfKeystrokeMgr keystrokeMgr)
        {
            _keystrokeMgr = keystrokeMgr;
            _keystrokeMgr.AdviseKeyEventSink(_clientId, this, true);
        }
    }

    #endregion

    #region ITfKeyEventSink

    public int OnSetFocus(bool foreground)
    {
        return 0; // S_OK
    }

    public int OnTestKeyDown(ITfContext context, nint wParam, nint lParam, out bool eaten)
    {
        eaten = ShouldEatKey((int)wParam);
        return 0;
    }

    public int OnTestKeyUp(ITfContext context, nint wParam, nint lParam, out bool eaten)
    {
        eaten = false;
        return 0;
    }

    public int OnKeyDown(ITfContext context, nint wParam, nint lParam, out bool eaten)
    {
        eaten = HandleKeyDown(context, (int)wParam);
        return 0;
    }

    public int OnKeyUp(ITfContext context, nint wParam, nint lParam, out bool eaten)
    {
        eaten = false;
        return 0;
    }

    public int OnPreservedKey(ITfContext context, ref Guid rguid, out bool eaten)
    {
        eaten = false;
        return 0;
    }

    #endregion

    #region ITfThreadMgrEventSink

    public void OnInitDocumentMgr(ITfDocumentMgr documentMgr)
    {
    }

    public void OnUninitDocumentMgr(ITfDocumentMgr documentMgr)
    {
    }

    public void OnSetFocus(ITfDocumentMgr documentMgr, ITfDocumentMgr prevDocumentMgr)
    {
    }

    public void OnPushContext(ITfContext context)
    {
    }

    public void OnPopContext(ITfContext context)
    {
    }

    #endregion

    #region Key Handling

    private bool ShouldEatKey(int vKey)
    {
        // Eat keys when composing
        if (_composingState.IsComposing)
        {
            return vKey switch
            {
                // Alphanumeric keys
                >= 0x41 and <= 0x5A => true, // A-Z
                >= 0x30 and <= 0x39 => true, // 0-9
                0x08 => true, // Backspace
                0x0D => true, // Enter
                0x1B => true, // Escape
                0x20 => true, // Space
                0x25 => true, // Left
                0x27 => true, // Right
                0x26 => true, // Up
                0x28 => true, // Down
                _ => false
            };
        }

        // Start composing on alphabetic key
        return vKey >= 0x41 && vKey <= 0x5A;
    }

    private bool HandleKeyDown(ITfContext context, int vKey)
    {
        if (_converter == null)
            return false;

        switch (vKey)
        {
            // Alphabetic keys (A-Z)
            case >= 0x41 and <= 0x5A:
                var ch = (char)vKey;
                // Convert to lowercase
                ch = char.ToLower(ch);
                _converter.AppendText(ch.ToString());
                _composingState.IsComposing = true;
                UpdateComposition(context);
                return true;

            // Backspace
            case 0x08:
                if (_composingState.IsComposing)
                {
                    _converter.RemoveText(1);
                    UpdateComposition(context);
                    return true;
                }
                return false;

            // Enter - commit composition
            case 0x0D:
                if (_composingState.IsComposing)
                {
                    CommitComposition(context);
                    return true;
                }
                return false;

            // Escape - cancel composition
            case 0x1B:
                if (_composingState.IsComposing)
                {
                    CancelComposition();
                    return true;
                }
                return false;

            // Space - convert
            case 0x20:
                if (_composingState.IsComposing)
                {
                    // Get candidates and show
                    var candidates = _converter.GetCandidates();
                    if (candidates.Count > 0)
                    {
                        _composingState.Candidates = candidates;
                        _composingState.SelectedCandidateIndex = 0;
                        UpdateComposition(context);
                    }
                    return true;
                }
                return false;

            // Arrow keys - navigate candidates
            case 0x28: // Down
                if (_composingState.HasCandidates)
                {
                    _composingState.SelectedCandidateIndex =
                        Math.Min(_composingState.SelectedCandidateIndex + 1,
                                 _composingState.Candidates!.Count - 1);
                    UpdateComposition(context);
                    return true;
                }
                return false;

            case 0x26: // Up
                if (_composingState.HasCandidates)
                {
                    _composingState.SelectedCandidateIndex =
                        Math.Max(_composingState.SelectedCandidateIndex - 1, 0);
                    UpdateComposition(context);
                    return true;
                }
                return false;

            default:
                return false;
        }
    }

    private void UpdateComposition(ITfContext context)
    {
        // Request edit session to update composition
        var editSession = new CompositionEditSession(this, context, _converter!, _composingState);
        context.RequestEditSession(_clientId, editSession, TsfConstants.TF_ES_READWRITE | TsfConstants.TF_ES_SYNC, out _);
    }

    private void CommitComposition(ITfContext context)
    {
        // Select current candidate if any
        if (_composingState.HasCandidates)
        {
            _converter?.SelectCandidate(_composingState.SelectedCandidateIndex);
        }

        // Commit the text
        var text = _composingState.HasCandidates
            ? _composingState.Candidates![_composingState.SelectedCandidateIndex]
            : _converter?.GetComposedText();

        if (!string.IsNullOrEmpty(text))
        {
            var editSession = new CommitEditSession(context, text);
            context.RequestEditSession(_clientId, editSession, TsfConstants.TF_ES_READWRITE | TsfConstants.TF_ES_SYNC, out _);
        }

        // Reset state
        _converter?.ClearText();
        _composingState.Reset();
    }

    private void CancelComposition()
    {
        _converter?.ClearText();
        _composingState.Reset();
    }

    #endregion

    public void Dispose()
    {
        if (_disposed)
            return;

        Deactivate();
        _disposed = true;
    }
}

/// <summary>
/// State for current composition
/// </summary>
internal class ComposingState
{
    public bool IsComposing { get; set; }
    public IReadOnlyList<string>? Candidates { get; set; }
    public int SelectedCandidateIndex { get; set; }
    public bool HasCandidates => Candidates != null && Candidates.Count > 0;

    public void Reset()
    {
        IsComposing = false;
        Candidates = null;
        SelectedCandidateIndex = 0;
    }
}

/// <summary>
/// Edit session for updating composition
/// </summary>
internal class CompositionEditSession : ITfEditSession
{
    private readonly TextService _textService;
    private readonly ITfContext _context;
    private readonly KanaKanjiConverter _converter;
    private readonly ComposingState _state;

    public CompositionEditSession(TextService textService, ITfContext context, KanaKanjiConverter converter, ComposingState state)
    {
        _textService = textService;
        _context = context;
        _converter = converter;
        _state = state;
    }

    public int DoEditSession(uint editCookie)
    {
        // Get composition text
        var composedText = _state.HasCandidates
            ? _state.Candidates![_state.SelectedCandidateIndex]
            : _converter.GetComposedText();

        // Update composition display
        // TODO: Implement composition display update

        return 0; // S_OK
    }
}

/// <summary>
/// Edit session for committing text
/// </summary>
internal class CommitEditSession : ITfEditSession
{
    private readonly ITfContext _context;
    private readonly string _text;

    public CommitEditSession(ITfContext context, string text)
    {
        _context = context;
        _text = text;
    }

    public int DoEditSession(uint editCookie)
    {
        // Get selection
        var selection = new TfSelection[1];
        _context.GetSelection(editCookie, 0, 1, selection, out var fetched);

        if (fetched > 0 && selection[0].Range != null)
        {
            // Set the text
            selection[0].Range.SetText(editCookie, 0, _text.ToCharArray(), _text.Length);
        }

        return 0; // S_OK
    }
}
