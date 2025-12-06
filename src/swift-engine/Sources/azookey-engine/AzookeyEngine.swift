import Foundation

/// Stub implementation for testing without AzooKeyKanaKanjiConverter
/// TODO: Replace with real implementation after resolving Windows path length issues

// MARK: - Stub Types

struct ComposingText {
    private var text: String = ""
    
    mutating func insertAtCursorPosition(_ text: String, inputStyle: InputStyle) {
        self.text += text
    }
    
    mutating func deleteBackwardFromCursorPosition(count: Int) {
        if count <= text.count {
            text.removeLast(count)
        }
    }
    
    mutating func moveCursorFromCursorPosition(count: Int) {
        // Stub implementation
    }
    
    func getText() -> String {
        return text
    }
}

enum InputStyle {
    case roman2kana
    case direct
}

struct Candidate {
    let text: String
}

struct ConvertRequestOptions {
    enum ZenzaiMode {
        case off
        case on(weight: URL, inferenceLimit: Int)
    }
    
    enum KeyboardLanguage {
        case ja_JP
        case en_US
    }
    
    enum LearningType {
        case nothing
        case inputAndOutput
    }
    
    let requireJapanesePrediction: Bool
    let requireEnglishPrediction: Bool
    let keyboardLanguage: KeyboardLanguage
    let learningType: LearningType
    let memoryDirectoryURL: URL?
    let zenzaiMode: ZenzaiMode
}

struct ConversionResult {
    let mainResults: [Candidate]
}

class KanaKanjiConverter {
    static func withDefaultDictionary() -> KanaKanjiConverter {
        return KanaKanjiConverter()
    }
    
    init() {}
    
    init(dictionaryDirectoryURL: URL) throws {
        // Stub
    }
    
    func requestCandidates(_ composingText: ComposingText, options: ConvertRequestOptions) -> ConversionResult {
        // Simple stub conversion - just return hiragana
        let text = composingText.getText()
        let candidates = [
            Candidate(text: text),
            Candidate(text: "変換テスト: " + text)
        ]
        return ConversionResult(mainResults: candidates)
    }
    
    func setCompletedData(_ candidate: Candidate) {
        // Stub
    }
}

// MARK: - Engine Implementation (using stubs)

/// Global converter instance
// Note: nonisolated(unsafe) is used for global mutable state accessed from exported C functions
nonisolated(unsafe) private var converter: KanaKanjiConverter?
nonisolated(unsafe) private var composingText = ComposingText()
nonisolated(unsafe) private var currentCandidates: [Candidate] = []
nonisolated(unsafe) private var config = EngineConfig()

/// Engine configuration
struct EngineConfig {
    var dictionaryPath: String = ""
    var memoryPath: String = ""
    var zenzaiEnabled: Bool = true
    var zenzaiInferenceLimit: Int = 10
    var zenzaiWeightPath: String = ""
}

/// Get conversion options
private func getOptions() -> ConvertRequestOptions {
    var zenzaiMode: ConvertRequestOptions.ZenzaiMode = .off

    if config.zenzaiEnabled, !config.zenzaiWeightPath.isEmpty {
        let weightURL = URL(fileURLWithPath: config.zenzaiWeightPath)
        zenzaiMode = .on(weight: weightURL, inferenceLimit: config.zenzaiInferenceLimit)
    }

    let memoryURL = config.memoryPath.isEmpty ? nil : URL(fileURLWithPath: config.memoryPath)

    return ConvertRequestOptions(
        requireJapanesePrediction: true,
        requireEnglishPrediction: false,
        keyboardLanguage: .ja_JP,
        learningType: memoryURL != nil ? .inputAndOutput : .nothing,
        memoryDirectoryURL: memoryURL,
        zenzaiMode: zenzaiMode
    )
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

@_silgen_name("Initialize")
public func initialize(_ dictionaryPath: UnsafePointer<CChar>?, _ memoryPath: UnsafePointer<CChar>?) {
    if let dictPath = dictionaryPath {
        config.dictionaryPath = String(cString: dictPath)
    }
    if let memPath = memoryPath {
        config.memoryPath = String(cString: memPath)
    }

    // Initialize converter with dictionary
    if config.dictionaryPath.isEmpty {
        converter = KanaKanjiConverter.withDefaultDictionary()
    } else {
        let dictURL = URL(fileURLWithPath: config.dictionaryPath)
        converter = try? KanaKanjiConverter(dictionaryDirectoryURL: dictURL)
    }

    composingText = ComposingText()
    currentCandidates = []
}

@_silgen_name("Shutdown")
public func shutdown() {
    converter = nil
    composingText = ComposingText()
    currentCandidates = []
}

@_silgen_name("AppendText")
public func appendText(_ input: UnsafePointer<CChar>?) {
    guard let input = input else { return }
    let inputString = String(cString: input)
    composingText.insertAtCursorPosition(inputString, inputStyle: .roman2kana)
}

@_silgen_name("RemoveText")
public func removeText(_ count: Int32) {
    for _ in 0..<count {
        composingText.deleteBackwardFromCursorPosition(count: 1)
    }
}

@_silgen_name("MoveCursor")
public func moveCursor(_ offset: Int32) {
    if offset > 0 {
        for _ in 0..<offset {
            composingText.moveCursorFromCursorPosition(count: 1)
        }
    } else if offset < 0 {
        for _ in 0..<(-offset) {
            composingText.moveCursorFromCursorPosition(count: -1)
        }
    }
}

@_silgen_name("ClearText")
public func clearText() {
    composingText = ComposingText()
    currentCandidates = []
}

@_silgen_name("GetComposedText")
public func getComposedText() -> UnsafePointer<CChar>? {
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
    guard let conv = converter else { return nil }

    let result = conv.requestCandidates(composingText, options: getOptions())
    currentCandidates = result.mainResults

    // Return candidates as JSON array
    let candidateTexts = currentCandidates.map { $0.text }

    guard let jsonData = try? JSONSerialization.data(withJSONObject: candidateTexts),
          let jsonString = String(data: jsonData, encoding: .utf8) else {
        return UnsafePointer(_strdup("[]"))
    }

    return UnsafePointer(_strdup(jsonString))
}

@_silgen_name("SelectCandidate")
public func selectCandidate(_ index: Int32) {
    guard index >= 0, index < currentCandidates.count else { return }

    let selected = currentCandidates[Int(index)]

    // Apply the selected candidate
    if let conv = converter {
        conv.setCompletedData(selected)
    }

    // Clear composing text after selection
    composingText = ComposingText()
    currentCandidates = []
}

@_silgen_name("ShrinkText")
public func shrinkText() {
    // Stub
}

@_silgen_name("ExpandText")
public func expandText() {
    // Stub
}

@_silgen_name("SetContext")
public func setContext(_ precedingText: UnsafePointer<CChar>?) {
    // Stub
}

@_silgen_name("SetZenzaiEnabled")
public func setZenzaiEnabled(_ enabled: Bool) {
    config.zenzaiEnabled = enabled
}

@_silgen_name("SetZenzaiInferenceLimit")
public func setZenzaiInferenceLimit(_ limit: Int32) {
    config.zenzaiInferenceLimit = Int(limit)
}

@_silgen_name("FreeString")
public func freeString(_ str: UnsafePointer<CChar>?) {
    guard let str = str else { return }
    free(UnsafeMutablePointer(mutating: str))
}