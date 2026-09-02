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
nonisolated(unsafe) private var currentTypoCandidates: [TypoCandidate] = []
nonisolated(unsafe) private var config = EngineConfig()
nonisolated(unsafe) private var learningDisabledReason: String?
nonisolated(unsafe) private var initializeError: String?

/// TypoCorrectionPass など他ファイルからの読み取り用スナップショット。
/// 書き込みはこのファイルの FFI セッター経由に限定する(engineLock 保持下)
func currentConfig() -> EngineConfig {
    config
}
nonisolated(unsafe) private var zenzaiWarmUpStarted = false
// TextReplacer (絵文字辞書の読み込みを伴う) は高コストなので変換毎に作らずキャッシュする
nonisolated(unsafe) private var cachedTextReplacer: TextReplacer?

private struct DynamicUserDictionaryEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case reading
        case word
        case pos
    }

    let reading: String
    let word: String
    let pos: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reading = try container.decodeIfPresent(String.self, forKey: .reading) ?? ""
        word = try container.decodeIfPresent(String.self, forKey: .word) ?? ""
        pos = try container.decodeIfPresent(String.self, forKey: .pos) ?? "noun"
    }
}

private struct DynamicUserDictionaryPos {
    let cid: Int
    let mid: Int
    let value: PValue
}

private enum DynamicUserDictionaryCID {
    // AzooKey's bundled dictionary uses the IPADIC connection-ID layout.
    static let adjective = 19       // 形容詞,自立,...,基本形
    static let interjection = 3     // 感動詞
    static let adverb = 1281        // 副詞,一般
    static let sahenNoun = 1283     // 名詞,サ変接続
}

/// Maps the stable categories sent by Mozc to AzooKey dictionary attributes.
/// Categories for which AzooKey does not expose a dedicated CID use the
/// general-noun CID so that the entry remains usable across dictionary updates.
private func dynamicUserDictionaryPos(for category: String) -> DynamicUserDictionaryPos {
    let general = DynamicUserDictionaryPos(
        cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: -5)
    switch category {
    case "proper_noun":
        return .init(cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
    case "personal_name":
        return .init(cid: CIDData.人名一般.cid, mid: MIDData.一般.mid, value: -5)
    case "family_name":
        return .init(cid: CIDData.人名姓.cid, mid: MIDData.人名姓.mid, value: -5)
    case "first_name":
        return .init(cid: CIDData.人名名.cid, mid: MIDData.人名名.mid, value: -5)
    case "place_name":
        return .init(cid: CIDData.地名一般.cid, mid: MIDData.一般.mid, value: -5)
    case "organization":
        return .init(cid: CIDData.固有名詞組織.cid, mid: MIDData.組織.mid, value: -5)
    case "sahen_noun":
        return .init(cid: DynamicUserDictionaryCID.sahenNoun, mid: MIDData.一般.mid, value: -5)
    case "adjective":
        return .init(cid: DynamicUserDictionaryCID.adjective, mid: MIDData.一般.mid, value: -5)
    case "adverb":
        return .init(cid: DynamicUserDictionaryCID.adverb, mid: MIDData.一般.mid, value: -5)
    case "interjection":
        return .init(cid: DynamicUserDictionaryCID.interjection, mid: MIDData.一般.mid, value: -5)
    case "symbol":
        return .init(cid: CIDData.記号.cid, mid: MIDData.一般.mid, value: -8)
    case "noun":
        return general
    default:
        return general
    }
}

func decodeDynamicUserDictionary(_ json: String) throws -> [DicdataElement] {
    let entries = try JSONDecoder().decode(
        [DynamicUserDictionaryEntry].self, from: Data(json.utf8))
    return entries.compactMap { entry in
        guard !entry.reading.isEmpty, !entry.word.isEmpty else { return nil }
        let pos = dynamicUserDictionaryPos(for: entry.pos)
        return DicdataElement(
            word: entry.word,
            ruby: entry.reading.toKatakana(),
            cid: pos.cid,
            mid: pos.mid,
            value: pos.value)
    }
}

/// Engine configuration
struct EngineConfig {
    var dictionaryPath: String = ""
    var memoryPath: String = ""
    var zenzaiEnabled: Bool = false
    var zenzaiUseGpu: Bool = false
    var zenzaiInferenceLimit: Int = 10
    var zenzaiWeightPath: String = ""
    var typoCorrectionEnabled: Bool = false
    var typoCorrectionUseAi: Bool = false
}

/// Get conversion options (caller must hold engineLock)
/// - Parameter allowLearning: false なら学習を無効化する (シークレットモード等)
func getOptions(allowLearning: Bool = true) -> ConvertRequestOptions {
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
        // upstream の PredictionMode 化（旧 Bool の true/false と同じ挙動: 日本語予測は候補に混ぜ、英語予測は生成しない）
        requireJapanesePrediction: .autoMix,
        requireEnglishPrediction: .disabled,
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
    // correspondingCount is the number of hiragana characters this candidate covers.
    // Normal candidates report their own rubyCount; typo-corrected candidates instead
    // report the ORIGINAL key length so that selecting one replaces the whole segment
    // (the corrected reading's rubyCount may differ from the typed key).
    var candidateObjects = currentCandidates.map { candidate -> [String: Any] in
        return [
            "text": candidate.text,
            "correspondingCount": candidate.rubyCount
        ]
    }
    candidateObjects.append(contentsOf: currentTypoCandidates.map { candidate -> [String: Any] in
        return [
            "text": candidate.text,
            "correspondingCount": candidate.correspondingCount,
            "typoCorrected": true,
            "correctedReading": candidate.correctedReading
        ]
    })

    guard let jsonData = try? JSONSerialization.data(withJSONObject: candidateObjects),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
        return UnsafePointer(_strdup("[]"))
    }

    return UnsafePointer(_strdup(jsonString))
}

// MARK: - Exported Functions

/// Initialize the engine. Returns 1 on success, 0 on failure.
/// 参照カウント方式: Mozc 側はコンバータインスタンスごとに Initialize/Shutdown を
/// 呼ぶが、エンジン状態はプロセスグローバル単一のため、Engine::ReloadModules で
/// 新旧インスタンスが入れ替わる際に旧側の Shutdown が新側を壊さないようにする。
@_cdecl("Initialize")
public func initialize(_ dictionaryPath: UnsafePointer<CChar>?, _ memoryPath: UnsafePointer<CChar>?) -> Int32 {
    engineLock.lock()
    defer { engineLock.unlock() }

    // 既に初期化済みなら設定の上書き・検証は行わず参照カウントだけ増やす。
    // (ReloadModules 等の多重 Initialize で、正常稼働中のエンジンが
    //  新しい引数の検証失敗により誤って「失敗」扱いになるのを防ぐ)
    if converter != nil {
        initCount += 1
        initializeError = nil
        return 1
    }

    if let dictPath = dictionaryPath {
        config.dictionaryPath = String(cString: dictPath)
    }
    if let memPath = memoryPath {
        config.memoryPath = String(cString: memPath)
    }
    learningDisabledReason = nil

    // カスタム辞書パス指定時は存在を検証して失敗を呼び出し元に伝える
    if !config.dictionaryPath.isEmpty,
       !FileManager.default.fileExists(atPath: config.dictionaryPath) {
        initializeError = "dictionary path not found: \(config.dictionaryPath)"
        return 0
    }
    // 学習ディレクトリが指定されているのに作成できない場合は学習なしで続行
    if !config.memoryPath.isEmpty {
        let requestedMemoryPath = config.memoryPath
        do {
            try FileManager.default.createDirectory(
                atPath: requestedMemoryPath, withIntermediateDirectories: true)
            var isDirectory: ObjCBool = false
            let memoryDirectoryExists = FileManager.default.fileExists(
                atPath: requestedMemoryPath, isDirectory: &isDirectory)
            if !memoryDirectoryExists || !isDirectory.boolValue {
                learningDisabledReason = "memory directory unavailable: \(requestedMemoryPath)"
                config.memoryPath = ""
            }
        } catch {
            learningDisabledReason = "memory directory unavailable: \(requestedMemoryPath)"
            config.memoryPath = ""
        }
    }

    let dicdataStore: DicdataStore
    if config.dictionaryPath.isEmpty {
        dicdataStore = DicdataStore.withDefaultDictionary()
    } else {
        let dictURL = URL(fileURLWithPath: config.dictionaryPath)
        dicdataStore = DicdataStore(dictionaryURL: dictURL)
    }
    converter = KanaKanjiConverter(dicdataStore: dicdataStore)
    typoConverter = KanaKanjiConverter(dicdataStore: dicdataStore)
    guard converter != nil else {
        typoConverter = nil
        initializeError = "converter creation failed"
        return 0
    }
    composingText = ComposingText()
    currentCandidates = []
    currentTypoCandidates = []

    initCount += 1
    initializeError = nil
    scheduleZenzaiWarmUpIfNeeded()
    return 1
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

@_cdecl("Shutdown")
public func shutdown() {
    engineLock.lock()
    defer { engineLock.unlock() }

    initCount = max(0, initCount - 1)
    if initCount == 0 {
        converter = nil
        typoConverter = nil
        composingText = ComposingText()
        currentCandidates = []
        currentTypoCandidates = []
        cachedTextReplacer = nil
        zenzaiWarmUpStarted = false
    }
}

/// 単発変換API: key (UTF-8ひらがな) の候補リストを JSON で返す。
/// ClearText → AppendText → GetCandidates の3呼び出しと違い、1呼び出しで
/// 完結するため呼び出し間に他スレッドの操作が割り込まない。
/// allowLearning=0 でこのリクエストの学習を無効化 (シークレットモード)。
@_cdecl("ConvertText")
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
    currentTypoCandidates = makeTypoCandidates(for: keyString, existingCandidates: currentCandidates)

    return candidatesJson()
}

@_cdecl("AppendText")
public func appendText(_ input: UnsafePointer<CChar>?) {
    guard let input = input else { return }
    let inputString = String(cString: input)
    engineLock.lock()
    defer { engineLock.unlock() }
    // Use .direct for hiragana input from Mozc (not roman2kana)
    composingText.insertAtCursorPosition(inputString, inputStyle: .direct)
}

@_cdecl("RemoveText")
public func removeText(_ count: Int32) {
    // 負数や0で Range 生成の fatalError を起こさないよう防御（C ABI 越しの外部入力）
    guard count > 0 else { return }
    engineLock.lock()
    defer { engineLock.unlock() }
    composingText.deleteBackwardFromCursorPosition(count: Int(count))
}

@_cdecl("MoveCursor")
public func moveCursor(_ offset: Int32) {
    engineLock.lock()
    defer { engineLock.unlock() }
    if offset != 0 {
        _ = composingText.moveCursorFromCursorPosition(count: Int(offset))
    }
}

@_cdecl("ClearText")
public func clearText() {
    engineLock.lock()
    defer { engineLock.unlock() }
    composingText = ComposingText()
    currentCandidates = []
    currentTypoCandidates = []
}

@_cdecl("GetComposedText")
public func getComposedText() -> UnsafePointer<CChar>? {
    engineLock.lock()
    defer { engineLock.unlock() }
    guard let conv = converter else { return nil }

    let result = conv.requestCandidates(composingText, options: getOptions())
    currentCandidates = result.mainResults
    currentTypoCandidates = []

    // Return best candidate
    guard let first = currentCandidates.first else {
        return UnsafePointer(_strdup(""))
    }

    return UnsafePointer(_strdup(first.text))
}

@_cdecl("GetCandidates")
public func getCandidates() -> UnsafePointer<CChar>? {
    engineLock.lock()
    defer { engineLock.unlock() }
    guard let conv = converter else { return nil }

    let result = conv.requestCandidates(composingText, options: getOptions())
    currentCandidates = result.mainResults
    currentTypoCandidates = []

    return candidatesJson()
}

@_cdecl("SelectCandidate")
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
    currentTypoCandidates = []
}

@_cdecl("ShrinkText")
public func shrinkText() {
    engineLock.lock()
    defer { engineLock.unlock() }
    composingText.deleteForwardFromCursorPosition(count: 1)
}

@_cdecl("SetZenzaiEnabled")
public func setZenzaiEnabled(_ enabled: Bool) {
    engineLock.lock()
    defer { engineLock.unlock() }
    config.zenzaiEnabled = enabled
    scheduleZenzaiWarmUpIfNeeded()
}

@_cdecl("SetZenzaiUseGpu")
public func setZenzaiUseGpu(_ enabled: Bool) {
    engineLock.lock()
    defer { engineLock.unlock() }
    config.zenzaiUseGpu = enabled
    scheduleZenzaiWarmUpIfNeeded()
}

@_cdecl("SetZenzaiInferenceLimit")
public func setZenzaiInferenceLimit(_ limit: Int32) {
    engineLock.lock()
    defer { engineLock.unlock() }
    config.zenzaiInferenceLimit = Int(limit)
}

@_cdecl("SetZenzaiWeightPath")
public func setZenzaiWeightPath(_ path: UnsafePointer<CChar>?) {
    guard let path = path else { return }
    engineLock.lock()
    defer { engineLock.unlock() }
    config.zenzaiWeightPath = String(cString: path)
    scheduleZenzaiWarmUpIfNeeded()
}

@_cdecl("SetTypoCorrectionBudget")
public func setTypoCorrectionBudget(_ budget: Int32) {
    engineLock.lock()
    defer { engineLock.unlock() }
    typoConversionBudget = budget > 0 ? Int(budget) : defaultTypoConversionBudget
}

@_cdecl("SetTypoCorrectionEnabled")
public func setTypoCorrectionEnabled(_ enabled: Bool) {
    engineLock.lock()
    defer { engineLock.unlock() }
    config.typoCorrectionEnabled = enabled
}

@_cdecl("SetTypoCorrectionUseAi")
public func setTypoCorrectionUseAi(_ enabled: Bool) {
    engineLock.lock()
    defer { engineLock.unlock() }
    config.typoCorrectionUseAi = enabled
}

/// Replaces the in-memory dynamic user dictionary with the complete Mozc
/// user dictionary encoded as UTF-8 JSON. Returns 1 on success.
@_cdecl("SetUserDictionary")
public func setUserDictionary(_ json: UnsafePointer<CChar>?) -> Int32 {
    guard let json else { return 0 }
    guard let dicdata = try? decodeDynamicUserDictionary(String(cString: json)) else {
        return 0
    }

    engineLock.lock()
    defer { engineLock.unlock() }
    guard let converter else { return 0 }
    converter.importDynamicUserDictionary(dicdata)
    typoConverter?.importDynamicUserDictionary(dicdata)
    return 1
}

@_cdecl("GetZenzaiStatus")
public func getZenzaiStatus() -> UnsafePointer<CChar>? {
    engineLock.lock()
    defer { engineLock.unlock() }
    var status: [String: Any] = [
        "enabled": config.zenzaiEnabled,
        "useGpu": config.zenzaiUseGpu,
        "weightPath": config.zenzaiWeightPath,
        "inferenceLimit": config.zenzaiInferenceLimit,
        "learningActive": !config.memoryPath.isEmpty
    ]
    if let learningDisabledReason {
        status["learningDisabledReason"] = learningDisabledReason
    }
    if let initializeError {
        status["initializeError"] = initializeError
    }

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

@_cdecl("FreeString")
public func freeString(_ str: UnsafePointer<CChar>?) {
    guard let str = str else { return }
    free(UnsafeMutablePointer(mutating: str))
}
