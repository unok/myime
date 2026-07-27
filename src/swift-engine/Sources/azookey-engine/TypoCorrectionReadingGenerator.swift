import Foundation

enum TypoCorrectionReadingGenerator {
    private static let maxResults = 6
    private static let vowels: [Character] = ["a", "i", "u", "e", "o"]

    private static let kanaToRomaji: [Character: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "si", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "ti", "つ": "tu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "hu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "wo", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "zi", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "di", "づ": "du", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ぁ": "xa", "ぃ": "xi", "ぅ": "xu", "ぇ": "xe", "ぉ": "xo",
        "ゃ": "xya", "ゅ": "xyu", "ょ": "xyo", "っ": "xtu"
    ]

    private static let romajiToKanaPairs: [(String, Character)] = [
        ("xya", "ゃ"), ("xyu", "ゅ"), ("xyo", "ょ"),
        ("xtu", "っ"), ("ltsu", "っ"),
        ("ka", "か"), ("ki", "き"), ("ku", "く"), ("ke", "け"), ("ko", "こ"),
        ("sa", "さ"), ("si", "し"), ("su", "す"), ("se", "せ"), ("so", "そ"),
        ("ta", "た"), ("ti", "ち"), ("tu", "つ"), ("te", "て"), ("to", "と"),
        ("na", "な"), ("ni", "に"), ("nu", "ぬ"), ("ne", "ね"), ("no", "の"),
        ("ha", "は"), ("hi", "ひ"), ("hu", "ふ"), ("he", "へ"), ("ho", "ほ"),
        ("ma", "ま"), ("mi", "み"), ("mu", "む"), ("me", "め"), ("mo", "も"),
        ("ya", "や"), ("yu", "ゆ"), ("yo", "よ"),
        ("ra", "ら"), ("ri", "り"), ("ru", "る"), ("re", "れ"), ("ro", "ろ"),
        ("wa", "わ"), ("wo", "を"),
        ("ga", "が"), ("gi", "ぎ"), ("gu", "ぐ"), ("ge", "げ"), ("go", "ご"),
        ("za", "ざ"), ("zi", "じ"), ("zu", "ず"), ("ze", "ぜ"), ("zo", "ぞ"),
        ("da", "だ"), ("di", "ぢ"), ("du", "づ"), ("de", "で"), ("do", "ど"),
        ("ba", "ば"), ("bi", "び"), ("bu", "ぶ"), ("be", "べ"), ("bo", "ぼ"),
        ("pa", "ぱ"), ("pi", "ぴ"), ("pu", "ぷ"), ("pe", "ぺ"), ("po", "ぽ"),
        ("xa", "ぁ"), ("xi", "ぃ"), ("xu", "ぅ"), ("xe", "ぇ"), ("xo", "ぉ"),
        ("a", "あ"), ("i", "い"), ("u", "う"), ("e", "え"), ("o", "お"), ("n", "ん")
    ]

    static func generateCandidates(for reading: String) -> [String] {
        var results: [String] = []
        var seen = Set<String>([reading])

        func append(_ value: String) -> Bool {
            guard results.count < maxResults, value != reading, isHiraganaOnly(value),
                  !seen.contains(value) else {
                return false
            }
            seen.insert(value)
            results.append(value)
            return true
        }

        func append<S: Sequence>(_ candidates: S, limit: Int? = nil) where S.Element == String {
            var appended = 0
            for candidate in candidates {
                guard results.count < maxResults else {
                    return
                }
                if append(candidate) {
                    appended += 1
                    if let limit, appended >= limit {
                        return
                    }
                }
            }
        }

        append(alphabetVowelCompletionCandidates(for: reading))
        append(romajiTranspositionCandidates(for: reading), limit: 3)
        append(nInsertionCandidates(for: reading), limit: 2)
        append(smallTsuInsertionCandidates(for: reading), limit: 2)

        return results
    }

    private static func alphabetVowelCompletionCandidates(for reading: String) -> [String] {
        let chars = Array(reading)
        var candidates: [String] = []

        for index in chars.indices {
            guard let ascii = asciiAlphabet(chars[index]) else {
                continue
            }
            for vowel in vowels {
                if let kana = romajiToKana(String([ascii, vowel])) {
                    // kana は「あい」のような複数文字になり得るため
                    // Character 変換ではなく部分置換で扱う
                    var replaced = chars
                    replaced.replaceSubrange(index...index, with: Array(kana))
                    candidates.append(String(replaced))
                }
            }
        }
        return candidates
    }

    private static func nInsertionCandidates(for reading: String) -> [String] {
        let chars = Array(reading)
        guard !chars.isEmpty else {
            return []
        }

        var candidates: [String] = []
        for index in 1...chars.count {
            var withN = chars
            withN.insert("ん", at: index)
            candidates.append(String(withN))
        }
        return candidates
    }

    private static func smallTsuInsertionCandidates(for reading: String) -> [String] {
        let chars = Array(reading)
        guard !chars.isEmpty else {
            return []
        }

        var candidates: [String] = []
        for index in 1...chars.count {
            var withSmallTsu = chars
            withSmallTsu.insert("っ", at: index)
            candidates.append(String(withSmallTsu))
        }
        return candidates
    }

    private static func romajiTranspositionCandidates(for reading: String) -> [String] {
        guard let romaji = hiraganaToRomaji(reading) else {
            return []
        }
        let chars = Array(romaji)
        guard chars.count >= 2 else {
            return []
        }

        var candidates: [String] = []
        for index in 0..<(chars.count - 1) {
            var swapped = chars
            swapped.swapAt(index, index + 1)
            if let kana = romajiToKana(String(swapped)) {
                candidates.append(kana)
            }
        }
        return candidates
    }

    private static func hiraganaToRomaji(_ reading: String) -> String? {
        var romaji = ""
        for char in reading {
            guard let converted = kanaToRomaji[char] else {
                return nil
            }
            romaji += converted
        }
        return romaji
    }

    private static func romajiToKana(_ romaji: String) -> String? {
        var result = ""
        var index = romaji.startIndex

        while index < romaji.endIndex {
            var matched = false
            for (key, kana) in romajiToKanaPairs {
                guard romaji[index...].hasPrefix(key) else {
                    continue
                }
                result.append(kana)
                index = romaji.index(index, offsetBy: key.count)
                matched = true
                break
            }
            if !matched {
                return nil
            }
        }
        return result
    }

    private static func asciiAlphabet(_ char: Character) -> Character? {
        guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 else {
            return nil
        }
        let value = scalar.value
        if value >= 0x41 && value <= 0x5A {
            return Character(UnicodeScalar(value + 0x20)!)
        }
        if value >= 0x61 && value <= 0x7A {
            return char
        }
        if value >= 0xFF21 && value <= 0xFF3A {
            return Character(UnicodeScalar(value - 0xFF21 + 0x61)!)
        }
        if value >= 0xFF41 && value <= 0xFF5A {
            return Character(UnicodeScalar(value - 0xFF41 + 0x61)!)
        }
        return nil
    }

    private static func isHiraganaOnly(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x3041 && scalar.value <= 0x3096
        }
    }
}
