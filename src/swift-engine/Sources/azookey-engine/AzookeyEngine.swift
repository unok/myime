import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

// MARK: - Using KanaKanjiConverterModuleWithDefaultDictionary with patched AzooKey

// MARK: - Global State
// すべてのエクスポート関数は engineLock で排他する。
// Mozc 側 (ImmutableConverterInterface::Convert は const = スレッドセーフ前提) から
// 複数スレッドで呼ばれても状態が混線しないようにするため。
nonisolated(unsafe) private let engineLock = NSLock()
nonisolated(unsafe) private var converter: KanaKanjiConverter?
nonisolated(unsafe) private var typoConverter: KanaKanjiConverter?
nonisolated(unsafe) private var initCount = 0
nonisolated(unsafe) private var composingText = ComposingText()
nonisolated(unsafe) private var currentCandidates: [Candidate] = []
nonisolated(unsafe) private var currentTypoCandidates: [TypoCandidate] = []
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
    var typoCorrectionEnabled: Bool = false
}

private struct TypoCandidate {
    let text: String
    let value: PValue
    let correspondingCount: Int
    let correctedReading: String
}

/// カタカナ→ひらがな折り畳み(表記ゆれ判定用)
private func foldedToHiragana(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
        (0x30A1...0x30F6).contains(scalar.value)
            ? Unicode.Scalar(scalar.value - 0x60)! : scalar
    }))
}

/// 読みの表記ゆれ(全カタカナ・混在カナ)にすぎない候補か。
/// ひらがな恒等(text == reading)は「ひらがな表記が正解の語」があり得るため除外しない
private func isScriptVariantOfReading(_ text: String, reading: String) -> Bool {
    text != reading && foldedToHiragana(text) == reading
}

/// 素のラティスが過大評価しがちな数字・アルファベット混入候補の検出
private func containsAsciiLikeNoise(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        // ASCII 数字・英字と全角数字・英字
        (0x30...0x39).contains(scalar.value) || (0x41...0x5A).contains(scalar.value)
            || (0x61...0x7A).contains(scalar.value)
            || (0xFF10...0xFF19).contains(scalar.value) || (0xFF21...0xFF3A).contains(scalar.value)
            || (0xFF41...0xFF5A).contains(scalar.value)
    }
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

/// Get conversion options for typo correction pass (caller must hold engineLock)
private func getTypoOptions() -> ConvertRequestOptions {
    var options = getOptions(allowLearning: false)
    options.learningType = .nothing
    options.zenzaiMode = .off
    return options
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

    let dicdataStore: DicdataStore
    if config.dictionaryPath.isEmpty {
        dicdataStore = DicdataStore.withDefaultDictionary()
    } else {
        let dictURL = URL(fileURLWithPath: config.dictionaryPath)
        dicdataStore = DicdataStore(dictionaryURL: dictURL)
    }
    converter = KanaKanjiConverter(dicdataStore: dicdataStore)
    typoConverter = KanaKanjiConverter(dicdataStore: dicdataStore)
    composingText = ComposingText()
    currentCandidates = []
    currentTypoCandidates = []

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
    currentTypoCandidates = makeTypoCandidates(for: keyString, existingCandidates: currentCandidates)

    return candidatesJson()
}

/// Build typo-correction candidates via an isolated second converter (caller must hold engineLock).
private func makeTypoCandidates(for key: String, existingCandidates: [Candidate]) -> [TypoCandidate] {
    guard config.typoCorrectionEnabled, let typoConv = typoConverter else {
        return []
    }

    let existingTexts = Set(existingCandidates.map(\.text))
    var typoCandidates: [TypoCandidate] = []
    let typoOptions = getTypoOptions()
    let originalKeyCount = key.count

    // 長い読みでは未知語スコア(-14.5固定)と実変換の分離ができず、
    // 2パスのコストも読み数に比例するため、短い読みに限定する
    guard originalKeyCount <= 8 else {
        return []
    }

    for correctedReading in TypoCorrectionReadingGenerator.generateCandidates(for: key) {
        var text = ComposingText()
        text.insertAtCursorPosition(correctedReading, inputStyle: .direct)
        let result = typoConv.requestCandidates(text, options: typoOptions)

        // mainResults の並びは表記バリエーション(value=-190 の素通し系)が先頭に
        // 来ることがあるため、先頭ではなく value 最大の候補を選ぶ。
        // ひらがな表記が正解の語(こんにちは 等)があるため、補正読みと同一の
        // テキストは除外しない。数字・アルファベット混入(に→2 等の過大評価)は除外
        let best = result.mainResults
            .filter {
                // 補正読み全体をカバーする候補のみ(接頭辞断片を除外)
                $0.rubyCount == correctedReading.count
                    && !existingTexts.contains($0.text)
                    && !containsAsciiLikeNoise($0.text)
                    && !isScriptVariantOfReading($0.text, reading: correctedReading)
                    // 未知語素通し(-14.5 固定)の恒等候補を除外。
                    // 実在語のひらがな恒等(こんにちは 等)は value が明確に良いため残る
                    && !($0.text == correctedReading && $0.value <= -14)
                    // 絶対バー: 誤った補正読みの強引な変換(-25 前後)を除外する。
                    // 実在補正は読み1文字あたり -3.0 より明確に良い(実測 -1.4〜-2.7)
                    && $0.value > PValue(-3 * correctedReading.count)
            }
            .max { $0.value < $1.value }
        if let best {
            typoCandidates.append(TypoCandidate(
                text: best.text,
                value: best.value,
                correspondingCount: originalKeyCount,
                correctedReading: correctedReading
            ))
        }
    }

    var seenTexts = existingTexts
    var filteredCandidates: [TypoCandidate] = []
    let ranked = typoCandidates.sorted { $0.value > $1.value }
    // ベストから大きく劣る候補(誤った補正読みの強引な変換)は表示しない
    let valueCutoff = (ranked.first?.value).map { $0 - 4.0 }
    for candidate in ranked {
        if let valueCutoff, candidate.value < valueCutoff {
            break
        }
        guard !seenTexts.contains(candidate.text) else {
            continue
        }
        seenTexts.insert(candidate.text)
        filteredCandidates.append(candidate)
        if filteredCandidates.count == 3 {
            break
        }
    }

    return filteredCandidates
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
    currentTypoCandidates = []
}

@_silgen_name("GetComposedText")
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

@_silgen_name("GetCandidates")
public func getCandidates() -> UnsafePointer<CChar>? {
    engineLock.lock()
    defer { engineLock.unlock() }
    guard let conv = converter else { return nil }

    let result = conv.requestCandidates(composingText, options: getOptions())
    currentCandidates = result.mainResults
    currentTypoCandidates = []

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
    currentTypoCandidates = []
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

@_silgen_name("SetTypoCorrectionEnabled")
public func setTypoCorrectionEnabled(_ enabled: Bool) {
    engineLock.lock()
    defer { engineLock.unlock() }
    config.typoCorrectionEnabled = enabled
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
