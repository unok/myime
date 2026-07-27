import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

// MARK: - Using KanaKanjiConverterModuleWithDefaultDictionary with patched AzooKey

// MARK: - Global State
// すべてのエクスポート関数は engineLock で排他する。
// Mozc 側 (ImmutableConverterInterface::Convert は const = スレッドセーフ前提) から
// 複数スレッドで呼ばれても状態が混線しないようにするため。
nonisolated(unsafe) private let engineLock = NSLock()
nonisolated(unsafe) private var converter: KanaKanjiConverter?
nonisolated(unsafe) private var initCount = 0
nonisolated(unsafe) private var composingText = ComposingText()
nonisolated(unsafe) private var currentCandidates: [Candidate] = []
nonisolated(unsafe) private var config = EngineConfig()
nonisolated(unsafe) private var zenzaiWarmUpStarted = false
// TextReplacer (絵文字辞書の読み込みを伴う) は高コストなので変換毎に作らずキャッシュする
nonisolated(unsafe) private var cachedTextReplacer: TextReplacer?

/// Engine configuration
struct EngineConfig {
    var dictionaryPath: String = ""
    var memoryPath: String = ""
    var zenzaiEnabled: Bool = false
    var zenzaiUseGpu: Bool = false
    var zenzaiInferenceLimit: Int = 10
    var zenzaiWeightPath: String = ""
}

/// Get conversion options (caller must hold engineLock)
/// - Parameter allowLearning: false なら学習を無効化する (シークレットモード等)
private func getOptions(allowLearning: Bool = true) -> ConvertRequestOptions {
    var zenzaiMode: ConvertRequestOptions.ZenzaiMode = .off

    if config.zenzaiEnabled, !config.zenzaiWeightPath.isEmpty {
        let weightURL = URL(fileURLWithPath: config.zenzaiWeightPath)
        zenzaiMode = .on(weight: weightURL, inferenceLimit: config.zenzaiInferenceLimit, personalizationMode: nil, useGpu: config.zenzaiUseGpu)
    }

    let memoryURL = config.memoryPath.isEmpty ? nil : URL(fileURLWithPath: config.memoryPath)
    let learningEnabled = (memoryURL != nil) && allowLearning

    let textReplacer: TextReplacer
    if let cached = cachedTextReplacer {
        textReplacer = cached
    } else {
        textReplacer = TextReplacer.withDefaultEmojiDictionary()
        cachedTextReplacer = textReplacer
    }

    return ConvertRequestOptions(
        requireJapanesePrediction: true,
        requireEnglishPrediction: false,
        keyboardLanguage: .ja_JP,
        learningType: learningEnabled ? .inputAndOutput : .nothing,
        memoryDirectoryURL: memoryURL ?? URL(fileURLWithPath: NSTemporaryDirectory()),
        sharedContainerURL: memoryURL ?? URL(fileURLWithPath: NSTemporaryDirectory()),
        textReplacer: textReplacer,
        specialCandidateProviders: nil,
        zenzaiMode: zenzaiMode,
        metadata: nil
    )
}

/// Build the candidates JSON for the current `currentCandidates` (caller must hold engineLock)
private func candidatesJson() -> UnsafePointer<CChar>? {
    // correspondingCount is the number of hiragana characters this candidate covers
    let candidateObjects = currentCandidates.map { candidate -> [String: Any] in
        return [
            "text": candidate.text,
            "correspondingCount": candidate.rubyCount
        ]
    }

    guard let jsonData = try? JSONSerialization.data(withJSONObject: candidateObjects),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
        return UnsafePointer(_strdup("[]"))
    }

    return UnsafePointer(_strdup(jsonString))
}

// MARK: - Exported Functions

@_silgen_name("LoadConfig")
public func loadConfig(_ configPath: UnsafePointer<CChar>?) {
    guard let configPath = configPath else { return }
    let path = String(cString: configPath)

    // Load config from JSON file
    guard let data = FileManager.default.contents(atPath: path),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return
    }

    engineLock.lock()
    defer { engineLock.unlock() }

    if let dictPath = json["dictionaryPath"] as? String {
        config.dictionaryPath = dictPath
    }
    if let memPath = json["memoryPath"] as? String {
        config.memoryPath = memPath
    }
    if let zenzaiEnabled = json["zenzaiEnabled"] as? Bool {
        config.zenzaiEnabled = zenzaiEnabled
    }
    if let zenzaiLimit = json["zenzaiInferenceLimit"] as? Int {
        config.zenzaiInferenceLimit = zenzaiLimit
    }
    if let zenzaiWeight = json["zenzaiWeightPath"] as? String {
        config.zenzaiWeightPath = zenzaiWeight
    }
}

/// Initialize the engine. Returns 1 on success, 0 on failure.
/// 参照カウント方式: Mozc 側はコンバータインスタンスごとに Initialize/Shutdown を
/// 呼ぶが、エンジン状態はプロセスグローバル単一のため、Engine::ReloadModules で
/// 新旧インスタンスが入れ替わる際に旧側の Shutdown が新側を壊さないようにする。
@_silgen_name("Initialize")
public func initialize(_ dictionaryPath: UnsafePointer<CChar>?, _ memoryPath: UnsafePointer<CChar>?) -> Int32 {
    engineLock.lock()
    defer { engineLock.unlock() }

    // 既に初期化済みなら設定の上書き・検証は行わず参照カウントだけ増やす。
    // (ReloadModules 等の多重 Initialize で、正常稼働中のエンジンが
    //  新しい引数の検証失敗により誤って「失敗」扱いになるのを防ぐ)
    if converter != nil {
        initCount += 1
        return 1
    }

    if let dictPath = dictionaryPath {
        config.dictionaryPath = String(cString: dictPath)
    }
    if let memPath = memoryPath {
        config.memoryPath = String(cString: memPath)
    }

    // カスタム辞書パス指定時は存在を検証して失敗を呼び出し元に伝える
    if !config.dictionaryPath.isEmpty,
       !FileManager.default.fileExists(atPath: config.dictionaryPath) {
        return 0
    }
    // 学習ディレクトリが指定されているのに作成できない場合は学習なしで続行
    if !config.memoryPath.isEmpty {
        try? FileManager.default.createDirectory(
            atPath: config.memoryPath, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: config.memoryPath) {
            config.memoryPath = ""
        }
    }

    if config.dictionaryPath.isEmpty {
        converter = KanaKanjiConverter.withDefaultDictionary()
    } else {
        let dictURL = URL(fileURLWithPath: config.dictionaryPath)
        let dicdataStore = DicdataStore(dictionaryURL: dictURL)
        converter = KanaKanjiConverter(dicdataStore: dicdataStore)
    }
    composingText = ComposingText()
    currentCandidates = []

    initCount += 1
    let initialized = converter != nil
    scheduleZenzaiWarmUpIfNeeded()
    return initialized ? 1 : 0
}

/// Schedule GPU warm-up once after all Zenzai settings have reached Swift.
/// Caller must hold engineLock.
private func scheduleZenzaiWarmUpIfNeeded() {
    guard !zenzaiWarmUpStarted,
          initCount > 0,
          converter != nil,
          config.zenzaiEnabled,
          config.zenzaiUseGpu,
          !config.zenzaiWeightPath.isEmpty else {
        return
    }
    zenzaiWarmUpStarted = true
    Thread {
        warmUpZenzai()
    }.start()
}

private func warmUpZenzai() {
    engineLock.lock()
    defer { engineLock.unlock() }

    guard initCount > 0,
          config.zenzaiEnabled,
          config.zenzaiUseGpu,
          !config.zenzaiWeightPath.isEmpty,
          let conv = converter else {
        return
    }

    var text = ComposingText()
    text.insertAtCursorPosition("あ", inputStyle: .direct)
    _ = conv.requestCandidates(text, options: getOptions(allowLearning: false))
}

@_silgen_name("Shutdown")
public func shutdown() {
    engineLock.lock()
    defer { engineLock.unlock() }

    initCount = max(0, initCount - 1)
    if initCount == 0 {
        converter = nil
        composingText = ComposingText()
        currentCandidates = []
        cachedTextReplacer = nil
        zenzaiWarmUpStarted = false
    }
}

/// 単発変換API: key (UTF-8ひらがな) の候補リストを JSON で返す。
/// ClearText → AppendText → GetCandidates の3呼び出しと違い、1呼び出しで
/// 完結するため呼び出し間に他スレッドの操作が割り込まない。
/// allowLearning=0 でこのリクエストの学習を無効化 (シークレットモード)。
@_silgen_name("ConvertText")
public func convertText(_ key: UnsafePointer<CChar>?, _ allowLearning: Int32) -> UnsafePointer<CChar>? {
    guard let key = key else { return nil }
    let keyString = String(cString: key)

    engineLock.lock()
    defer { engineLock.unlock() }

    guard let conv = converter else { return nil }

    var text = ComposingText()
    // Use .direct for hiragana input from Mozc (not roman2kana)
    text.insertAtCursorPosition(keyString, inputStyle: .direct)

    let result = conv.requestCandidates(text, options: getOptions(allowLearning: allowLearning != 0))
    composingText = text
    currentCandidates = result.mainResults

    return candidatesJson()
}

@_silgen_name("AppendText")
public func appendText(_ input: UnsafePointer<CChar>?) {
    guard let input = input else { return }
    let inputString = String(cString: input)
    engineLock.lock()
    defer { engineLock.unlock() }
    // Use .direct for hiragana input from Mozc (not roman2kana)
    composingText.insertAtCursorPosition(inputString, inputStyle: .direct)
}

@_silgen_name("RemoveText")
public func removeText(_ count: Int32) {
    // 負数や0で Range 生成の fatalError を起こさないよう防御（C ABI 越しの外部入力）
    guard count > 0 else { return }
    engineLock.lock()
    defer { engineLock.unlock() }
    composingText.deleteBackwardFromCursorPosition(count: Int(count))
}

@_silgen_name("MoveCursor")
public func moveCursor(_ offset: Int32) {
    engineLock.lock()
    defer { engineLock.unlock() }
    if offset != 0 {
        _ = composingText.moveCursorFromCursorPosition(count: Int(offset))
    }
}

@_silgen_name("ClearText")
public func clearText() {
    engineLock.lock()
    defer { engineLock.unlock() }
    composingText = ComposingText()
    currentCandidates = []
}

@_silgen_name("GetComposedText")
public func getComposedText() -> UnsafePointer<CChar>? {
    engineLock.lock()
    defer { engineLock.unlock() }
    guard let conv = converter else { return nil }

    let result = conv.requestCandidates(composingText, options: getOptions())
    currentCandidates = result.mainResults

    // Return best candidate
    guard let first = currentCandidates.first else {
        return UnsafePointer(_strdup(""))
    }

    return UnsafePointer(_strdup(first.text))
}

@_silgen_name("GetCandidates")
public func getCandidates() -> UnsafePointer<CChar>? {
    engineLock.lock()
    defer { engineLock.unlock() }
    guard let conv = converter else { return nil }

    let result = conv.requestCandidates(composingText, options: getOptions())
    currentCandidates = result.mainResults

    return candidatesJson()
}

@_silgen_name("SelectCandidate")
public func selectCandidate(_ index: Int32) {
    engineLock.lock()
    defer { engineLock.unlock() }
    guard index >= 0, index < currentCandidates.count else { return }

    let selected = currentCandidates[Int(index)]

    // Apply the selected candidate (feeds user learning when enabled)
    if let conv = converter {
        conv.setCompletedData(selected)
    }

    // Clear composing text after selection
    composingText = ComposingText()
    currentCandidates = []
}

@_silgen_name("ShrinkText")
public func shrinkText() {
    engineLock.lock()
    defer { engineLock.unlock() }
    composingText.deleteForwardFromCursorPosition(count: 1)
}

@_silgen_name("SetZenzaiEnabled")
public func setZenzaiEnabled(_ enabled: Bool) {
    engineLock.lock()
    defer { engineLock.unlock() }
    config.zenzaiEnabled = enabled
    scheduleZenzaiWarmUpIfNeeded()
}

@_silgen_name("SetZenzaiUseGpu")
public func setZenzaiUseGpu(_ enabled: Bool) {
    engineLock.lock()
    defer { engineLock.unlock() }
    config.zenzaiUseGpu = enabled
    scheduleZenzaiWarmUpIfNeeded()
}

@_silgen_name("SetZenzaiInferenceLimit")
public func setZenzaiInferenceLimit(_ limit: Int32) {
    engineLock.lock()
    defer { engineLock.unlock() }
    config.zenzaiInferenceLimit = Int(limit)
}

@_silgen_name("SetZenzaiWeightPath")
public func setZenzaiWeightPath(_ path: UnsafePointer<CChar>?) {
    guard let path = path else { return }
    engineLock.lock()
    defer { engineLock.unlock() }
    config.zenzaiWeightPath = String(cString: path)
    scheduleZenzaiWarmUpIfNeeded()
}

@_silgen_name("GetZenzaiStatus")
public func getZenzaiStatus() -> UnsafePointer<CChar>? {
    engineLock.lock()
    defer { engineLock.unlock() }
    var status: [String: Any] = [
        "enabled": config.zenzaiEnabled,
        "useGpu": config.zenzaiUseGpu,
        "weightPath": config.zenzaiWeightPath,
        "inferenceLimit": config.zenzaiInferenceLimit
    ]

    // Check if Zenzai is actually active
    if config.zenzaiEnabled && !config.zenzaiWeightPath.isEmpty {
        // Check if model file exists
        let fileExists = FileManager.default.fileExists(atPath: config.zenzaiWeightPath)
        status["modelExists"] = fileExists
        status["active"] = fileExists
    } else {
        status["modelExists"] = false
        status["active"] = false
    }

    guard let jsonData = try? JSONSerialization.data(withJSONObject: status),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
        return UnsafePointer(_strdup("{\"error\": \"Failed to serialize status\"}"))
    }

    return UnsafePointer(_strdup(jsonString))
}

@_silgen_name("FreeString")
public func freeString(_ str: UnsafePointer<CChar>?) {
    guard let str = str else { return }
    free(UnsafeMutablePointer(mutating: str))
}
