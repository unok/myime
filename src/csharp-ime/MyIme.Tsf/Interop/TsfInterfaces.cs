using System.Runtime.InteropServices;

namespace MyIme.Tsf.Interop;

// ITfTextInputProcessor
[ComImport]
[Guid("AA80E80E-2021-11D2-93E0-0060B067B86E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfTextInputProcessor
{
    void Activate(ITfThreadMgr threadMgr, uint clientId);
    void Deactivate();
}

// ITfTextInputProcessorEx
[ComImport]
[Guid("76EF6B4B-DA0C-4F09-88DA-A6F5F7C8E5A9")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfTextInputProcessorEx : ITfTextInputProcessor
{
    new void Activate(ITfThreadMgr threadMgr, uint clientId);
    new void Deactivate();
    void ActivateEx(ITfThreadMgr threadMgr, uint clientId, uint flags);
}

// ITfThreadMgr
[ComImport]
[Guid("AA80E801-2021-11D2-93E0-0060B067B86E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfThreadMgr
{
    void Activate(out uint clientId);
    void Deactivate();
    void CreateDocumentMgr(out ITfDocumentMgr documentMgr);
    void EnumDocumentMgrs(out object enumDocumentMgrs);
    void GetFocus(out ITfDocumentMgr documentMgr);
    void SetFocus(ITfDocumentMgr documentMgr);
    void AssociateFocus(nint hwnd, ITfDocumentMgr newDocMgr, out ITfDocumentMgr prevDocMgr);
    void IsThreadFocus([MarshalAs(UnmanagedType.Bool)] out bool isFocus);
    void GetFunctionProvider(ref Guid clsid, out object funcProvider);
    void EnumFunctionProviders(out object enumFuncProviders);
    void GetGlobalCompartment(out object compartmentMgr);
}

// ITfDocumentMgr
[ComImport]
[Guid("AA80E7F4-2021-11D2-93E0-0060B067B86E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfDocumentMgr
{
    void CreateContext(uint clientId, uint flags, [MarshalAs(UnmanagedType.IUnknown)] object appSink, out ITfContext context, out uint ecTextStore);
    void Push(ITfContext context);
    void Pop(uint flags);
    void GetTop(out ITfContext context);
    void GetBase(out ITfContext context);
    void EnumContexts(out object enumContexts);
}

// ITfContext
[ComImport]
[Guid("AA80E7FD-2021-11D2-93E0-0060B067B86E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfContext
{
    void RequestEditSession(uint clientId, ITfEditSession editSession, uint flags, out int result);
    void InWriteSession(uint clientId, [MarshalAs(UnmanagedType.Bool)] out bool inWriteSession);
    void GetSelection(uint editCookie, uint index, uint count, [Out] TfSelection[] selection, out uint fetched);
    void SetSelection(uint editCookie, uint count, [In] TfSelection[] selection);
    void GetStart(uint editCookie, out ITfRange range);
    void GetEnd(uint editCookie, out ITfRange range);
    void GetActiveView(out ITfContextView view);
    void EnumViews(out object enumViews);
    void GetStatus(out TsStatus status);
    void GetProperty(ref Guid propGuid, out ITfProperty property);
    void GetAppProperty(ref Guid propGuid, out object property);
    void TrackProperties([In] ref Guid[] properties, uint numProperties, [In] ref Guid[] appProperties, uint numAppProperties, out object propertyRange);
    void EnumProperties(out object enumProperties);
    void GetDocumentMgr(out ITfDocumentMgr documentMgr);
    void CreateRangeBackup(uint editCookie, ITfRange range, out object rangeBackup);
}

// ITfEditSession
[ComImport]
[Guid("AA80E803-2021-11D2-93E0-0060B067B86E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfEditSession
{
    [PreserveSig]
    int DoEditSession(uint editCookie);
}

// ITfRange
[ComImport]
[Guid("AA80E7FF-2021-11D2-93E0-0060B067B86E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfRange
{
    void QueryInterface(ref Guid riid, out nint ppvObj);
    uint AddRef();
    uint Release();
    void GetText(uint editCookie, uint flags, [Out] char[] buffer, uint bufferLen, out uint textLen);
    void SetText(uint editCookie, uint flags, [In] char[] text, int len);
    void GetFormattedText(uint editCookie, out object dataObject);
    void GetEmbedded(uint editCookie, ref Guid rguidService, ref Guid riid, out nint ppunk);
    void InsertEmbedded(uint editCookie, uint flags, object dataObject);
    void ShiftStart(uint editCookie, int count, out int actualCount, nint halt);
    void ShiftEnd(uint editCookie, int count, out int actualCount, nint halt);
    void ShiftStartToRange(uint editCookie, ITfRange range, TfAnchor anchor);
    void ShiftEndToRange(uint editCookie, ITfRange range, TfAnchor anchor);
    void ShiftStartRegion(uint editCookie, TfShiftDir dir, [MarshalAs(UnmanagedType.Bool)] out bool noRegion);
    void ShiftEndRegion(uint editCookie, TfShiftDir dir, [MarshalAs(UnmanagedType.Bool)] out bool noRegion);
    void IsEmpty(uint editCookie, [MarshalAs(UnmanagedType.Bool)] out bool isEmpty);
    void Collapse(uint editCookie, TfAnchor anchor);
    void IsEqualStart(uint editCookie, ITfRange range, TfAnchor anchor, [MarshalAs(UnmanagedType.Bool)] out bool isEqual);
    void IsEqualEnd(uint editCookie, ITfRange range, TfAnchor anchor, [MarshalAs(UnmanagedType.Bool)] out bool isEqual);
    void CompareStart(uint editCookie, ITfRange range, TfAnchor anchor, out int result);
    void CompareEnd(uint editCookie, ITfRange range, TfAnchor anchor, out int result);
    void AdjustForInsert(uint editCookie, uint count, [MarshalAs(UnmanagedType.Bool)] out bool insertOk);
    void GetGravity(out TfGravity start, out TfGravity end);
    void SetGravity(uint editCookie, TfGravity start, TfGravity end);
    void Clone(out ITfRange clone);
    void GetContext(out ITfContext context);
}

// ITfContextView
[ComImport]
[Guid("2433BF8E-0F9B-435C-BA2C-180611978C30")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfContextView
{
    void QueryInterface(ref Guid riid, out nint ppvObj);
    uint AddRef();
    uint Release();
    void GetRangeFromPoint(uint editCookie, ref Point point, uint flags, out ITfRange range);
    void GetTextExt(uint editCookie, ITfRange range, out Rect rect, [MarshalAs(UnmanagedType.Bool)] out bool clipped);
    void GetScreenExt(out Rect rect);
    void GetWnd(out nint hwnd);
}

// ITfProperty
[ComImport]
[Guid("E2449660-9542-11D2-BF46-00105A2799B5")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfProperty
{
    void QueryInterface(ref Guid riid, out nint ppvObj);
    uint AddRef();
    uint Release();
}

// ITfKeyEventSink
[ComImport]
[Guid("AA80E7F5-2021-11D2-93E0-0060B067B86E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfKeyEventSink
{
    [PreserveSig]
    int OnSetFocus([MarshalAs(UnmanagedType.Bool)] bool foreground);

    [PreserveSig]
    int OnTestKeyDown(ITfContext context, nint wParam, nint lParam, [MarshalAs(UnmanagedType.Bool)] out bool eaten);

    [PreserveSig]
    int OnTestKeyUp(ITfContext context, nint wParam, nint lParam, [MarshalAs(UnmanagedType.Bool)] out bool eaten);

    [PreserveSig]
    int OnKeyDown(ITfContext context, nint wParam, nint lParam, [MarshalAs(UnmanagedType.Bool)] out bool eaten);

    [PreserveSig]
    int OnKeyUp(ITfContext context, nint wParam, nint lParam, [MarshalAs(UnmanagedType.Bool)] out bool eaten);

    [PreserveSig]
    int OnPreservedKey(ITfContext context, ref Guid rguid, [MarshalAs(UnmanagedType.Bool)] out bool eaten);
}

// ITfKeystrokeMgr
[ComImport]
[Guid("AA80E7F0-2021-11D2-93E0-0060B067B86E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfKeystrokeMgr
{
    void AdviseKeyEventSink(uint clientId, ITfKeyEventSink sink, [MarshalAs(UnmanagedType.Bool)] bool foreground);
    void UnadviseKeyEventSink(uint clientId);
    void GetForeground(ref Guid clsid);
    void TestKeyDown(nint wParam, nint lParam, [MarshalAs(UnmanagedType.Bool)] out bool eaten);
    void TestKeyUp(nint wParam, nint lParam, [MarshalAs(UnmanagedType.Bool)] out bool eaten);
    void KeyDown(nint wParam, nint lParam, [MarshalAs(UnmanagedType.Bool)] out bool eaten);
    void KeyUp(nint wParam, nint lParam, [MarshalAs(UnmanagedType.Bool)] out bool eaten);
    void GetPreservedKey(ITfContext context, ref TfPreservedKey preservedKey, out Guid guid);
    void IsPreservedKey(ref Guid guid, ref TfPreservedKey preservedKey, [MarshalAs(UnmanagedType.Bool)] out bool isPreserved);
    void PreserveKey(uint clientId, ref Guid guid, ref TfPreservedKey preservedKey, [MarshalAs(UnmanagedType.LPWStr)] string description, uint descLen);
    void UnpreserveKey(ref Guid guid, ref TfPreservedKey preservedKey);
    void SetPreservedKeyDescription(ref Guid guid, [MarshalAs(UnmanagedType.LPWStr)] string description, uint descLen);
    void GetPreservedKeyDescription(ref Guid guid, [MarshalAs(UnmanagedType.BStr)] out string description);
    void SimulatePreservedKey(ITfContext context, ref Guid guid, [MarshalAs(UnmanagedType.Bool)] out bool eaten);
}

// ITfThreadMgrEventSink
[ComImport]
[Guid("AA80E80F-2021-11D2-93E0-0060B067B86E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfThreadMgrEventSink
{
    void OnInitDocumentMgr(ITfDocumentMgr documentMgr);
    void OnUninitDocumentMgr(ITfDocumentMgr documentMgr);
    void OnSetFocus(ITfDocumentMgr documentMgr, ITfDocumentMgr prevDocumentMgr);
    void OnPushContext(ITfContext context);
    void OnPopContext(ITfContext context);
}

// Enums and Structures
public enum TfAnchor
{
    Start = 0,
    End = 1
}

public enum TfShiftDir
{
    Backward = 0,
    Forward = 1
}

public enum TfGravity
{
    Backward = 0,
    Forward = 1
}

[StructLayout(LayoutKind.Sequential)]
public struct TfSelection
{
    public ITfRange Range;
    public TfSelectionStyle Style;
}

[StructLayout(LayoutKind.Sequential)]
public struct TfSelectionStyle
{
    public TfActiveSelEnd ActiveEnd;
    [MarshalAs(UnmanagedType.Bool)]
    public bool Interim;
}

public enum TfActiveSelEnd
{
    None = 0,
    Start = 1,
    End = 2
}

[StructLayout(LayoutKind.Sequential)]
public struct TsStatus
{
    public uint DynamicFlags;
    public uint StaticFlags;
}

[StructLayout(LayoutKind.Sequential)]
public struct TfPreservedKey
{
    public uint VirtualKey;
    public uint Modifiers;
}

[StructLayout(LayoutKind.Sequential)]
public struct Point
{
    public int X;
    public int Y;
}

[StructLayout(LayoutKind.Sequential)]
public struct Rect
{
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

// ITfContextComposition
[ComImport]
[Guid("D40C8AAE-AC92-4FC7-9A11-0EE0E23AA39B")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfContextComposition
{
    void StartComposition(uint editCookie, ITfRange range, ITfCompositionSink sink, out ITfComposition composition);
    void EnumCompositions(out object enumCompositions);
    void FindComposition(uint editCookie, ITfRange testRange, out object enumCompositions);
    void TakeOwnership(uint editCookie, ITfComposition composition, ITfCompositionSink sink, out ITfComposition newComposition);
}

// ITfComposition
[ComImport]
[Guid("20168D64-5A8F-4A5A-B7BD-CFA29F4D0FD9")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfComposition
{
    void GetRange(out ITfRange range);
    void ShiftStart(uint editCookie, ITfRange newStart);
    void ShiftEnd(uint editCookie, ITfRange newEnd);
    void EndComposition(uint editCookie);
}

// ITfCompositionSink
[ComImport]
[Guid("A781718C-579A-4B15-A280-32B8577ACC5E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfCompositionSink
{
    [PreserveSig]
    int OnCompositionTerminated(uint editCookie, ITfComposition composition);
}

// ITfInsertAtSelection
[ComImport]
[Guid("55CE16BA-3014-41C1-9CEB-FADE1446AC6C")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface ITfInsertAtSelection
{
    void InsertTextAtSelection(uint editCookie, uint flags, [In] char[] text, int len, out ITfRange range);
    void InsertEmbeddedAtSelection(uint editCookie, uint flags, object dataObject, out ITfRange range);
}

// Constants
public static class TsfConstants
{
    public const uint TF_CLIENTID_NULL = 0;
    public const uint TF_ES_ASYNCDONTCARE = 0x0;
    public const uint TF_ES_SYNC = 0x1;
    public const uint TF_ES_READ = 0x2;
    public const uint TF_ES_READWRITE = 0x6;
    public const uint TF_ES_ASYNC = 0x8;

    public const uint TF_IAS_NOQUERY = 0x1;
    public const uint TF_IAS_QUERYONLY = 0x2;
    public const uint TF_IAS_NO_DEFAULT_COMPOSITION = 0x80000000;
}
