import Foundation

enum TypoCorrectionReadingGenerator {
    private static let maxResults = 16
    private static let vowels: [Character] = ["a", "i", "u", "e", "o"]
    private static let romajiVowels = Set<Character>(["a", "i", "u", "e", "o"])

    private struct KanaToken {
        let kana: String
        let romaji: String
        let consonant: String
        let vowel: Character?
    }

    private static let baseKanaToRomaji: [Character: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
        "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
        "わ": "wa", "を": "wo", "ん": "n",
        "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "だ": "da", "ぢ": "di", "づ": "du", "で": "de", "ど": "do",
        "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ぁ": "xa", "ぃ": "xi", "ぅ": "xu", "ぇ": "xe", "ぉ": "xo",
        "ゃ": "xya", "ゅ": "xyu", "ょ": "xyo", "っ": "xtu"
    ]

    private static let yoonKanaToRomaji: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo",
        "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo",
        "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "じゃ": "ja", "じゅ": "ju", "じょ": "jo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo",
        "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo"
    ]

    private static let romajiToKanaPairs: [(String, String)] = [
        ("kya", "きゃ"), ("kyu", "きゅ"), ("kyo", "きょ"),
        ("sha", "しゃ"), ("shu", "しゅ"), ("sho", "しょ"),
        ("sya", "しゃ"), ("syu", "しゅ"), ("syo", "しょ"),
        ("cha", "ちゃ"), ("chu", "ちゅ"), ("cho", "ちょ"),
        ("tya", "ちゃ"), ("tyu", "ちゅ"), ("tyo", "ちょ"),
        ("nya", "にゃ"), ("nyu", "にゅ"), ("nyo", "にょ"),
        ("hya", "ひゃ"), ("hyu", "ひゅ"), ("hyo", "ひょ"),
        ("mya", "みゃ"), ("myu", "みゅ"), ("myo", "みょ"),
        ("rya", "りゃ"), ("ryu", "りゅ"), ("ryo", "りょ"),
        ("gya", "ぎゃ"), ("gyu", "ぎゅ"), ("gyo", "ぎょ"),
        ("ja", "じゃ"), ("ju", "じゅ"), ("jo", "じょ"),
        ("jya", "じゃ"), ("jyu", "じゅ"), ("jyo", "じょ"),
        ("zya", "じゃ"), ("zyu", "じゅ"), ("zyo", "じょ"),
        ("bya", "びゃ"), ("byu", "びゅ"), ("byo", "びょ"),
        ("pya", "ぴゃ"), ("pyu", "ぴゅ"), ("pyo", "ぴょ"),
        ("xtu", "っ"), ("ltsu", "っ"),
        ("shi", "し"), ("si", "し"), ("chi", "ち"), ("ti", "ち"),
        ("tsu", "つ"), ("tu", "つ"), ("fu", "ふ"), ("hu", "ふ"),
        ("ji", "じ"), ("zi", "じ"),
        ("ka", "か"), ("ki", "き"), ("ku", "く"), ("ke", "け"), ("ko", "こ"),
        ("sa", "さ"), ("su", "す"), ("se", "せ"), ("so", "そ"),
        ("ta", "た"), ("te", "て"), ("to", "と"),
        ("na", "な"), ("ni", "に"), ("nu", "ぬ"), ("ne", "ね"), ("no", "の"),
        ("ha", "は"), ("hi", "ひ"), ("he", "へ"), ("ho", "ほ"),
        ("ma", "ま"), ("mi", "み"), ("mu", "む"), ("me", "め"), ("mo", "も"),
        ("ya", "や"), ("yu", "ゆ"), ("yo", "よ"),
        ("ra", "ら"), ("ri", "り"), ("ru", "る"), ("re", "れ"), ("ro", "ろ"),
        ("wa", "わ"), ("wo", "を"),
        ("ga", "が"), ("gi", "ぎ"), ("gu", "ぐ"), ("ge", "げ"), ("go", "ご"),
        ("za", "ざ"), ("zu", "ず"), ("ze", "ぜ"), ("zo", "ぞ"),
        ("da", "だ"), ("di", "ぢ"), ("du", "づ"), ("de", "で"), ("do", "ど"),
        ("ba", "ば"), ("bi", "び"), ("bu", "ぶ"), ("be", "べ"), ("bo", "ぼ"),
        ("pa", "ぱ"), ("pi", "ぴ"), ("pu", "ぷ"), ("pe", "ぺ"), ("po", "ぽ"),
        ("xa", "ぁ"), ("xi", "ぃ"), ("xu", "ぅ"), ("xe", "ぇ"), ("xo", "ぉ"),
        ("xya", "ゃ"), ("xyu", "ゅ"), ("xyo", "ょ"),
        ("a", "あ"), ("i", "い"), ("u", "う"), ("e", "え"), ("o", "お")
    ]

    private static let qwertyAdjacentKeys: [Character: [Character]] = [
        "q": ["w", "a", "s"],
        "w": ["q", "e", "a", "s", "d"],
        "e": ["w", "r", "s", "d", "f"],
        "r": ["e", "t", "d", "f", "g"],
        "t": ["r", "y", "f", "g", "h"],
        "y": ["t", "u", "g", "h", "j"],
        "u": ["y", "i", "h", "j", "k"],
        "i": ["u", "o", "j", "k", "l"],
        "o": ["i", "p", "k", "l"],
        "p": ["o", "l"],
        "a": ["q", "w", "s", "z", "x"],
        "s": ["q", "w", "e", "a", "d", "z", "x", "c"],
        "d": ["w", "e", "r", "s", "f", "x", "c", "v"],
        "f": ["e", "r", "t", "d", "g", "c", "v", "b"],
        "g": ["r", "t", "y", "f", "h", "v", "b", "n"],
        "h": ["t", "y", "u", "g", "j", "b", "n", "m"],
        "j": ["y", "u", "i", "h", "k", "n", "m"],
        "k": ["u", "i", "o", "j", "l", "m"],
        "l": ["i", "o", "p", "k"],
        "z": ["a", "s", "x"],
        "x": ["a", "s", "d", "z", "c"],
        "c": ["s", "d", "f", "x", "v"],
        "v": ["d", "f", "g", "c", "b"],
        "b": ["f", "g", "h", "v", "n"],
        "n": ["g", "h", "j", "b", "m"],
        "m": ["h", "j", "k", "n"]
    ]

    private static let kanaVariantGroups: [[Character]] = [
        ["か", "が"], ["き", "ぎ"], ["く", "ぐ"], ["け", "げ"], ["こ", "ご"],
        ["さ", "ざ"], ["し", "じ"], ["す", "ず"], ["せ", "ぜ"], ["そ", "ぞ"],
        ["た", "だ"], ["ち", "ぢ"], ["つ", "づ"], ["て", "で"], ["と", "ど"],
        ["は", "ば", "ぱ"], ["ひ", "び", "ぴ"], ["ふ", "ぶ", "ぷ"], ["へ", "べ", "ぺ"], ["ほ", "ぼ", "ぽ"]
    ]

    private static let kanaSmallVariantGroups: [[Character]] = [
        ["あ", "ぁ"], ["い", "ぃ"], ["う", "ぅ"], ["え", "ぇ"], ["お", "ぉ"],
        ["つ", "っ"], ["や", "ゃ"], ["ゆ", "ゅ"], ["よ", "ょ"], ["わ", "ゎ"]
    ]

    private static let nSplitReplacements: [Character: String] = [
        "な": "んあ", "に": "んい", "ぬ": "んう", "ね": "んえ", "の": "んお",
        "や": "んや", "ゆ": "んゆ", "よ": "んよ"
    ]

    private static let consonantCompletionByVowel: [Character: [Character]] = [
        "あ": ["た", "か", "さ", "な", "ら", "ま", "は", "が", "だ"],
        "い": ["ち", "き", "し", "に", "り", "み", "ひ", "ぎ", "ぢ"],
        "う": ["つ", "く", "す", "ぬ", "る", "む", "ふ", "ぐ", "づ"],
        "え": ["て", "け", "せ", "ね", "れ", "め", "へ", "げ", "で"],
        "お": ["と", "こ", "そ", "の", "ろ", "も", "ほ", "ご", "ど"]
    ]

    private static let yoonBases: Set<Character> = [
        "き", "し", "ち", "に", "ひ", "み", "り", "ぎ", "じ", "び", "ぴ"
    ]
    private static let largeYoonCharacters: Set<Character> = ["や", "ゆ", "よ"]
    private static let smallYoonCharacters: Set<Character> = ["ゃ", "ゅ", "ょ"]

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

        let categories: [[String]] = [
            Array(alphabetVowelCompletionCandidates(for: reading).prefix(3)),
            Array(nInsertionCandidates(for: reading).prefix(2)),
            Array(nSegmentationCandidates(for: reading).prefix(3)),
            Array(romajiTranspositionCandidates(for: reading).prefix(3)),
            Array(smallTsuInsertionCandidates(for: reading).prefix(2)),
            Array(consonantCompletionCandidates(for: reading).prefix(3)),
            Array(romajiDeletionCandidates(for: reading).prefix(3)),
            Array(sameVowelSyllableTranspositionCandidates(for: reading).prefix(3)),
            Array(qwertyAdjacentReplacementCandidates(for: reading).prefix(3)),
            Array(yoonCollapseCandidates(for: reading).prefix(2)),
            Array(kanaVariantCandidates(for: reading).prefix(3)),
            Array(longSoundCandidates(for: reading).prefix(2))
        ]

        var round = 0
        while results.count < maxResults {
            var appendedThisRound = false
            for category in categories where round < category.count {
                if append(category[round]) {
                    appendedThisRound = true
                }
                if results.count >= maxResults {
                    break
                }
            }
            if !appendedThisRound {
                break
            }
            round += 1
        }

        return results
    }

    static func leftoverAlphabetCandidates(for reading: String) -> [String] {
        let chars = Array(reading)
        var results: [String] = []
        var seen = Set<String>([reading])

        func append(_ value: String, perRunCount: inout Int) {
            guard results.count < 8, perRunCount < 6, value != reading, isHiraganaOnly(value),
                  !seen.contains(value) else {
                return
            }
            seen.insert(value)
            results.append(value)
            perRunCount += 1
        }

        func replaced(_ range: Range<Int>, with replacement: String) -> String {
            var replaced = chars
            replaced.replaceSubrange(range, with: Array(replacement))
            return String(replaced)
        }

        var index = 0
        while index < chars.count && results.count < 8 {
            guard asciiAlphabet(chars[index]) != nil else {
                index += 1
                continue
            }
            let start = index
            var normalizedRun = ""
            while index < chars.count, let ascii = asciiAlphabet(chars[index]) {
                normalizedRun.append(ascii)
                index += 1
            }
            let runRange = start..<index
            var perRunCount = 0

            for vowel in vowels {
                if let kana = romajiToKana(normalizedRun + String(vowel)) {
                    append(replaced(runRange, with: kana), perRunCount: &perRunCount)
                }
            }

            if index < chars.count, let nextRomaji = hiraganaToRomaji(String(chars[index])) {
                let combined = normalizedRun + nextRomaji
                if let kana = romajiToKana(combined) {
                    append(replaced(start..<(index + 1), with: kana), perRunCount: &perRunCount)
                }
            }

            let runChars = Array(normalizedRun)
            for runIndex in runChars.indices {
                guard let adjacentKeys = qwertyAdjacentKeys[runChars[runIndex]] else {
                    continue
                }
                for adjacent in adjacentKeys {
                    var replacedRun = runChars
                    replacedRun[runIndex] = adjacent
                    if let kana = romajiToKana(String(replacedRun) + "a") {
                        append(replaced(runRange, with: kana), perRunCount: &perRunCount)
                    }
                }
            }

            append(replaced(runRange, with: ""), perRunCount: &perRunCount)
        }

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
                    var replaced = chars
                    replaced.replaceSubrange(index...index, with: Array(kana))
                    candidates.append(String(replaced))
                }
            }

            guard index + 1 < chars.count else {
                continue
            }
            let nextIndex = index + 1
            guard let nextRomaji = hiraganaToRomaji(String(chars[nextIndex])),
                  let nextVowel = nextRomaji.last else {
                continue
            }
            let nextChars = Array(nextRomaji)
            let possibleSecondConsonants = nextChars.dropLast().compactMap { char -> Character? in
                guard !romajiVowels.contains(char) else {
                    return nil
                }
                return char
            }
            for second in possibleSecondConsonants {
                let variants = [second] + (qwertyAdjacentKeys[second] ?? [])
                for variant in variants {
                    let combinedRomaji = String([ascii, variant, nextVowel])
                    if let kana = romajiToKana(combinedRomaji) {
                        var replaced = chars
                        replaced.replaceSubrange(index...nextIndex, with: Array(kana))
                        candidates.append(String(replaced))
                    }
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

    private static func nSegmentationCandidates(for reading: String) -> [String] {
        let chars = Array(reading)
        guard !chars.isEmpty else {
            return []
        }

        var candidates: [String] = []
        for index in chars.indices {
            if index + 1 < chars.count, let replacement = yoonNSegmentationReplacement(first: chars[index], second: chars[index + 1]) {
                var replaced = chars
                replaced.replaceSubrange(index...(index + 1), with: Array(replacement))
                candidates.append(String(replaced))
            }
            if let replacement = nSplitReplacements[chars[index]] {
                var replaced = chars
                replaced.replaceSubrange(index...index, with: Array(replacement))
                candidates.append(String(replaced))
            }
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

    private static func consonantCompletionCandidates(for reading: String) -> [String] {
        let chars = Array(reading)
        guard !chars.isEmpty else {
            return []
        }

        var candidates: [String] = []
        for index in chars.indices.reversed() {
            guard let replacements = consonantCompletionByVowel[chars[index]] else {
                continue
            }
            for replacement in replacements.prefix(4) {
                var replaced = chars
                replaced[index] = replacement
                candidates.append(String(replaced))
            }
        }
        return candidates
    }

    private static func romajiTranspositionCandidates(for reading: String) -> [String] {
        var candidates: [String] = []
        let variantChars = hiraganaToRomajiTypoVariants(reading).map(Array.init)
        let maxCount = variantChars.map(\.count).max() ?? 0
        guard maxCount >= 2 else {
            return []
        }

        let vowelSwapIndices = 0..<(maxCount - 1)
        for index in vowelSwapIndices {
            for chars in variantChars where index + 1 < chars.count && romajiVowels.contains(chars[index]) && romajiVowels.contains(chars[index + 1]) {
                var swapped = chars
                swapped.swapAt(index, index + 1)
                if let kana = romajiToKana(String(swapped)) {
                    candidates.append(kana)
                }
            }
        }

        for index in 0..<(maxCount - 1) {
            for chars in variantChars where index + 1 < chars.count && !(romajiVowels.contains(chars[index]) && romajiVowels.contains(chars[index + 1])) {
                var swapped = chars
                swapped.swapAt(index, index + 1)
                if let kana = romajiToKana(String(swapped)) {
                    candidates.append(kana)
                }
            }
        }
        return candidates
    }

    private static func romajiDeletionCandidates(for reading: String) -> [String] {
        var candidates: [String] = []
        for romaji in hiraganaToRomajiTypoVariants(reading) {
            let chars = Array(romaji)
            guard chars.count >= 2 else {
                continue
            }
            let deletionIndices = chars.indices.filter { index in
                (index > chars.startIndex && chars[index] == chars[index - 1])
                    || (index < chars.index(before: chars.endIndex) && chars[index] == chars[index + 1])
            } + chars.indices.filter { index in
                !((index > chars.startIndex && chars[index] == chars[index - 1])
                    || (index < chars.index(before: chars.endIndex) && chars[index] == chars[index + 1]))
            }
            for index in deletionIndices {
                var deleted = chars
                deleted.remove(at: index)
                if let kana = romajiToKana(String(deleted)) {
                    candidates.append(kana)
                }
            }
        }
        return candidates
    }

    private static func sameVowelSyllableTranspositionCandidates(for reading: String) -> [String] {
        guard let tokens = tokenizeKana(reading), tokens.count >= 2 else {
            return []
        }

        var candidates: [String] = []
        for left in 0..<(tokens.count - 1) {
            for right in (left + 1)..<tokens.count {
                guard let leftVowel = tokens[left].vowel,
                      leftVowel == tokens[right].vowel,
                      !tokens[left].consonant.isEmpty,
                      !tokens[right].consonant.isEmpty,
                      tokens[left].kana != tokens[right].kana else {
                    continue
                }
                var swapped = tokens
                swapped.swapAt(left, right)
                candidates.append(swapped.map(\.kana).joined())
            }
        }
        return candidates
    }

    private static func qwertyAdjacentReplacementCandidates(for reading: String) -> [String] {
        var candidates: [String] = []
        for romaji in hiraganaToRomajiTypoVariants(reading) {
            let chars = Array(romaji)
            guard !chars.isEmpty else {
                continue
            }
            let replacementIndices = chars.indices.filter { romajiVowels.contains(chars[$0]) }
                + chars.indices.filter { !romajiVowels.contains(chars[$0]) }
            for index in replacementIndices {
                guard let adjacentKeys = qwertyAdjacentKeys[chars[index]] else {
                    continue
                }
                for replacement in adjacentKeys {
                    guard romajiVowels.contains(chars[index]) == romajiVowels.contains(replacement) else {
                        continue
                    }
                    var replaced = chars
                    replaced[index] = replacement
                    if let kana = romajiToKana(String(replaced)) {
                        candidates.append(kana)
                    }
                }
            }
        }
        return candidates
    }

    private static func yoonCollapseCandidates(for reading: String) -> [String] {
        let chars = Array(reading)
        guard chars.count >= 2 else {
            return []
        }

        var candidates: [String] = []
        for index in 0..<(chars.count - 1) {
            if yoonBases.contains(chars[index]), largeYoonCharacters.contains(chars[index + 1]) {
                var replaced = chars
                replaced[index + 1] = smallYoon(chars[index + 1])
                candidates.append(String(replaced))
            }
            if yoonBases.contains(chars[index]), smallYoonCharacters.contains(chars[index + 1]) {
                var replaced = chars
                replaced.replaceSubrange(index...(index + 1), with: [chars[index], "い", largeYoon(chars[index + 1])])
                candidates.append(String(replaced))
            }
        }
        return candidates
    }

    private static func kanaVariantCandidates(for reading: String) -> [String] {
        let chars = Array(reading)
        guard !chars.isEmpty else {
            return []
        }

        var voicedVariantsByKana: [Character: [Character]] = [:]
        for group in kanaVariantGroups {
            for kana in group {
                voicedVariantsByKana[kana, default: []].append(contentsOf: group.filter { $0 != kana })
            }
        }

        var smallVariantsByKana: [Character: [Character]] = [:]
        for group in kanaSmallVariantGroups {
            for kana in group {
                smallVariantsByKana[kana, default: []].append(contentsOf: group.filter { $0 != kana })
            }
        }

        var candidates: [String] = []
        var firstVoicedReplacement: (index: Int, variant: Character)?
        for index in chars.indices {
            guard let variants = voicedVariantsByKana[chars[index]] else {
                continue
            }
            for variant in variants {
                var replaced = chars
                replaced[index] = variant
                candidates.append(String(replaced))
                if firstVoicedReplacement == nil {
                    firstVoicedReplacement = (index, variant)
                } else if let first = firstVoicedReplacement, first.index != index {
                    var doubleReplaced = chars
                    doubleReplaced[first.index] = first.variant
                    doubleReplaced[index] = variant
                    candidates.append(String(doubleReplaced))
                }
            }
        }

        for index in chars.indices {
            guard let variants = smallVariantsByKana[chars[index]] else {
                continue
            }
            for variant in variants {
                var replaced = chars
                replaced[index] = variant
                candidates.append(String(replaced))
            }
        }
        return candidates
    }

    private static func longSoundCandidates(for reading: String) -> [String] {
        let chars = Array(reading)
        guard !chars.isEmpty else {
            return []
        }

        var candidates: [String] = []
        for index in chars.indices {
            guard chars[index] == "う" || chars[index] == "ー" else {
                continue
            }
            var replaced = chars
            replaced[index] = chars[index] == "う" ? "ー" : "う"
            candidates.append(String(replaced))
        }
        return candidates
    }

    private static func hiraganaToRomaji(_ reading: String) -> String? {
        guard let tokens = tokenizeKana(reading) else {
            return nil
        }

        var romaji = ""
        for index in tokens.indices {
            if tokens[index].kana == "っ" {
                if index + 1 < tokens.count, let first = tokens[index + 1].romaji.first,
                   !romajiVowels.contains(first), first != "n" {
                    romaji.append(first)
                } else {
                    romaji += tokens[index].romaji
                }
                continue
            }
            if tokens[index].kana == "ん" {
                if index + 1 < tokens.count, let first = tokens[index + 1].romaji.first,
                   romajiVowels.contains(first) || first == "y" || first == "n" {
                    romaji += "nn"
                } else {
                    romaji += "n"
                }
                continue
            }
            romaji += tokens[index].romaji
        }
        return romaji
    }

    private static func hiraganaToRomajiTypoVariants(_ reading: String, limit: Int = 4) -> [String] {
        guard let primary = hiraganaToRomaji(reading), limit > 0 else {
            return []
        }

        let replacementPairs: [(String, String)] = [
            ("shi", "si"), ("chi", "ti"), ("tsu", "tu"), ("fu", "hu"), ("ji", "zi"),
            ("sha", "sya"), ("shu", "syu"), ("sho", "syo"),
            ("cha", "tya"), ("chu", "tyu"), ("cho", "tyo"),
            ("ja", "jya"), ("ju", "jyu"), ("jo", "jyo"),
            ("ja", "zya"), ("ju", "zyu"), ("jo", "zyo")
        ]

        var variants = [primary]
        var seen = Set(variants)
        for (from, to) in replacementPairs {
            var searchStart = primary.startIndex
            while let range = primary.range(of: from, range: searchStart..<primary.endIndex) {
                var variant = primary
                variant.replaceSubrange(range, with: to)
                if seen.insert(variant).inserted {
                    variants.append(variant)
                    if variants.count >= limit {
                        return variants
                    }
                }
                searchStart = range.upperBound
            }
        }
        return variants
    }

    private static func romajiToKana(_ romaji: String) -> String? {
        var result = ""
        var index = romaji.startIndex

        while index < romaji.endIndex {
            if romaji[index...].hasPrefix("nn") {
                result.append("ん")
                index = romaji.index(index, offsetBy: 2)
                continue
            }
            if romaji[index] == "n" {
                let next = romaji.index(after: index)
                if next == romaji.endIndex {
                    result.append("ん")
                    index = next
                    continue
                }
                let nextChar = romaji[next]
                if !romajiVowels.contains(nextChar) && nextChar != "y" {
                    result.append("ん")
                    index = next
                    continue
                }
            }
            if isSmallTsuPrefix(in: romaji, at: index) {
                result.append("っ")
                index = romaji.index(after: index)
                continue
            }

            var matched = false
            for (key, kana) in romajiToKanaPairs {
                guard romaji[index...].hasPrefix(key) else {
                    continue
                }
                result += kana
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

    private static func tokenizeKana(_ reading: String) -> [KanaToken]? {
        let chars = Array(reading)
        var tokens: [KanaToken] = []
        var index = 0

        while index < chars.count {
            if index + 1 < chars.count {
                let combined = String([chars[index], chars[index + 1]])
                if let romaji = yoonKanaToRomaji[combined] {
                    tokens.append(KanaToken(
                        kana: combined,
                        romaji: romaji,
                        consonant: consonantPart(of: romaji),
                        vowel: romaji.last
                    ))
                    index += 2
                    continue
                }
            }

            guard let romaji = baseKanaToRomaji[chars[index]] else {
                return nil
            }
            tokens.append(KanaToken(
                kana: String(chars[index]),
                romaji: romaji,
                consonant: consonantPart(of: romaji),
                vowel: romaji.last
            ))
            index += 1
        }
        return tokens
    }

    private static func consonantPart(of romaji: String) -> String {
        String(romaji.dropLast().filter { !romajiVowels.contains($0) })
    }

    private static func isSmallTsuPrefix(in romaji: String, at index: String.Index) -> Bool {
        let next = romaji.index(after: index)
        guard next < romaji.endIndex,
              romaji[index] == romaji[next],
              !romajiVowels.contains(romaji[index]),
              romaji[index] != "n" else {
            return false
        }
        return true
    }

    private static func yoonNSegmentationReplacement(first: Character, second: Character) -> String? {
        guard smallYoonCharacters.contains(second) else {
            return nil
        }
        switch first {
        case "に":
            return "ん" + String(largeYoon(second))
        default:
            return nil
        }
    }

    private static func smallYoon(_ char: Character) -> Character {
        switch char {
        case "や": return "ゃ"
        case "ゆ": return "ゅ"
        default: return "ょ"
        }
    }

    private static func largeYoon(_ char: Character) -> Character {
        switch char {
        case "ゃ": return "や"
        case "ゅ": return "ゆ"
        default: return "よ"
        }
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
            (scalar.value >= 0x3041 && scalar.value <= 0x3096) || scalar.value == 0x30FC
        }
    }
}

// テスト専用ヘルパ。internal のみで @_cdecl エクスポートを持たないため
// DLL の公開シンボルには影響しない。swift test と scratchpad の swiftc 直叩き
// (-DTYPO_CORRECTION_TEST) の両方から使うため #if では囲まない
extension TypoCorrectionReadingGenerator {
    static func testRoundTripReadings() -> [String] {
        let singles = baseKanaToRomaji.keys.map(String.init)
        let yoon = Array(yoonKanaToRomaji.keys)
        let geminated = Array(yoonKanaToRomaji.keys).filter { key in
            guard let romaji = yoonKanaToRomaji[key], let first = romaji.first else {
                return false
            }
            return !romajiVowels.contains(first) && first != "n"
        }.map { "っ" + $0 }
        + baseKanaToRomaji.keys.compactMap { kana -> String? in
            guard let romaji = baseKanaToRomaji[kana], let first = romaji.first,
                  !romajiVowels.contains(first), first != "n", kana != "っ" else {
                return nil
            }
            return "っ" + String(kana)
        }
        let nasalBoundaries = (singles + yoon).map { "ん" + $0 }
        return (singles + yoon + geminated + nasalBoundaries).sorted()
    }

    static func testRomaji(_ reading: String) -> String? { hiraganaToRomaji(reading) }

    static func testRoundTripFailures() -> [(String, String?, String?)] {
        testRoundTripReadings().compactMap { reading in
            let romajiVariants = hiraganaToRomajiTypoVariants(reading)
            if romajiVariants.contains(where: { romajiToKana($0) == reading }) {
                return nil
            }
            let romaji = romajiVariants.first
            let roundTripped = romaji.flatMap(romajiToKana)
            return (reading, romaji, roundTripped)
        }
    }
}
