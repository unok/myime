import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

// MARK: - Using KanaKanjiConverterModuleWithDefaultDictionary with patched AzooKey v0.11.1

// MARK: - Global State
// Note: nonisolated(unsafe) is used for global mutable state accessed from exported C functions
nonisolated(unsafe) private var converter: KanaKanjiConverter?
nonisolated(unsafe) private var composingText = ComposingText()
nonisolated(unsafe) private var currentCandidates: [Candidate] = []
nonisolated(unsafe) private var config = EngineConfig()

/// Engine configuration
struct EngineConfig {
    var dictionaryPath: String = ""
    var memoryPath: String = ""
    var zenzaiEnabled: Bool = false
    var zenzaiInferenceLimit: Int = 10
    var zenzaiWeightPath: String = ""
}

/// Get conversion options
private func getOptions() -> ConvertRequestOptions {
    var zenzaiMode: ConvertRequestOptions.ZenzaiMode = .off

    if config.zenzaiEnabled, !config.zenzaiWeightPath.isEmpty {
        let weightURL = URL(fileURLWithPath: config.zenzaiWeightPath)
        zenzaiMode = .on(weight: weightURL, inferenceLimit: config.zenzaiInferenceLimit, personalizationMode: nil)
    }

    let memoryURL = config.memoryPath.isEmpty ? nil : URL(fileURLWithPath: config.memoryPath)

    return ConvertRequestOptions(
        requireJapanesePrediction: true,
        requireEnglishPrediction: false,
        keyboardLanguage: .ja_JP,
        learningType: memoryURL != nil ? .inputAndOutput : .nothing,
        memoryDirectoryURL: memoryURL ?? URL(fileURLWithPath: NSTemporaryDirectory()),
        sharedContainerURL: memoryURL ?? URL(fileURLWithPath: NSTemporaryDirectory()),
        textReplacer: TextReplacer.withDefaultEmojiDictionary(),
        specialCandidateProviders: nil,
        zenzaiMode: zenzaiMode,
        metadata: nil
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
        let dicdataStore = DicdataStore(dictionaryURL: dictURL)
        converter = KanaKanjiConverter(dicdataStore: dicdataStore)
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
            _ = composingText.moveCursorFromCursorPosition(count: 1)
        }
    } else if offset < 0 {
        for _ in 0..<(-offset) {
            _ = composingText.moveCursorFromCursorPosition(count: -1)
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
    composingText.deleteForwardFromCursorPosition(count: 1)
}

@_silgen_name("ExpandText")
public func expandText() {
    // Not implemented in current version
}

@_silgen_name("SetContext")
public func setContext(_ precedingText: UnsafePointer<CChar>?) {
    // Context support not implemented yet
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

// MARK: - Test API wrapper functions

@_cdecl("azookey_create")
public func azookey_create(_ configJson: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let configJson = configJson else { return nil }
    
    let jsonString = String(cString: configJson)
    
    // Parse JSON configuration
    guard let jsonData = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        return nil
    }
    
    // Update configuration
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
    
    // Initialize converter
    initialize(nil, nil)
    
    // Return a dummy handle (not nil to indicate success)
    return UnsafeMutableRawPointer(bitPattern: 1)
}

@_cdecl("azookey_destroy")
public func azookey_destroy(_ engine: UnsafeMutableRawPointer?) {
    shutdown()
}

@_cdecl("azookey_convert")
public func azookey_convert(_ engine: UnsafeMutableRawPointer?, _ input: UnsafePointer<CChar>?) -> UnsafePointer<CChar>? {
    guard let input = input else { return nil }
    
    // Clear existing text and append new input
    clearText()
    appendText(input)
    
    // Get conversion result
    return getComposedText()
}

@_cdecl("azookey_free_string")
public func azookey_free_string(_ str: UnsafePointer<CChar>?) {
    freeString(str)
}