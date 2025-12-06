import Foundation

/// Simple roman to kana converter
class SimpleKanaConverter {
    private static let romajiMap: [String: String] = [
        // Vowels
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
        
        // K-row
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        "kya": "きゃ", "kyi": "きぃ", "kyu": "きゅ", "kye": "きぇ", "kyo": "きょ",
        
        // G-row
        "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
        "gya": "ぎゃ", "gyi": "ぎぃ", "gyu": "ぎゅ", "gye": "ぎぇ", "gyo": "ぎょ",
        
        // S-row
        "sa": "さ", "si": "し", "shi": "し", "su": "す", "se": "せ", "so": "そ",
        "sha": "しゃ", "shu": "しゅ", "she": "しぇ", "sho": "しょ",
        "sya": "しゃ", "syi": "しぃ", "syu": "しゅ", "sye": "しぇ", "syo": "しょ",
        
        // Z-row
        "za": "ざ", "zi": "じ", "ji": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
        "ja": "じゃ", "ju": "じゅ", "je": "じぇ", "jo": "じょ",
        "zya": "じゃ", "zyi": "じぃ", "zyu": "じゅ", "zye": "じぇ", "zyo": "じょ",
        
        // T-row
        "ta": "た", "ti": "ち", "chi": "ち", "tu": "つ", "tsu": "つ", "te": "て", "to": "と",
        "cha": "ちゃ", "chu": "ちゅ", "che": "ちぇ", "cho": "ちょ",
        "tya": "ちゃ", "tyi": "ちぃ", "tyu": "ちゅ", "tye": "ちぇ", "tyo": "ちょ",
        
        // D-row
        "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
        "dya": "ぢゃ", "dyi": "ぢぃ", "dyu": "ぢゅ", "dye": "ぢぇ", "dyo": "ぢょ",
        
        // N-row
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
        "nya": "にゃ", "nyi": "にぃ", "nyu": "にゅ", "nye": "にぇ", "nyo": "にょ",
        
        // H-row
        "ha": "は", "hi": "ひ", "fu": "ふ", "hu": "ふ", "he": "へ", "ho": "ほ",
        "hya": "ひゃ", "hyi": "ひぃ", "hyu": "ひゅ", "hye": "ひぇ", "hyo": "ひょ",
        
        // B-row
        "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
        "bya": "びゃ", "byi": "びぃ", "byu": "びゅ", "bye": "びぇ", "byo": "びょ",
        
        // P-row
        "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
        "pya": "ぴゃ", "pyi": "ぴぃ", "pyu": "ぴゅ", "pye": "ぴぇ", "pyo": "ぴょ",
        
        // M-row
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
        "mya": "みゃ", "myi": "みぃ", "myu": "みゅ", "mye": "みぇ", "myo": "みょ",
        
        // Y-row
        "ya": "や", "yu": "ゆ", "yo": "よ",
        
        // R-row
        "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
        "rya": "りゃ", "ryi": "りぃ", "ryu": "りゅ", "rye": "りぇ", "ryo": "りょ",
        
        // W-row
        "wa": "わ", "wi": "ゐ", "we": "ゑ", "wo": "を",
        
        // N
        "n": "ん", "nn": "ん",
        
        // Small TSU (double consonant)
        "kk": "っk", "ss": "っs", "tt": "っt", "cc": "っc",
        "pp": "っp", "mm": "っm", "bb": "っb", "dd": "っd",
        "gg": "っg", "zz": "っz", "rr": "っr", "hh": "っh",
        "jj": "っj", "ff": "っf", "ww": "っw", "yy": "っy",
        
        // Special
        "xtu": "っ", "xtsu": "っ", "ltu": "っ", "ltsu": "っ",
        "xa": "ぁ", "xi": "ぃ", "xu": "ぅ", "xe": "ぇ", "xo": "ぉ",
        "la": "ぁ", "li": "ぃ", "lu": "ぅ", "le": "ぇ", "lo": "ぉ",
        "xya": "ゃ", "xyu": "ゅ", "xyo": "ょ",
        "lya": "ゃ", "lyu": "ゅ", "lyo": "ょ",
        "xwa": "ゎ", "lwa": "ゎ"
    ]
    
    static func convert(_ input: String) -> String {
        var result = ""
        var buffer = ""
        let lowercased = input.lowercased()
        
        for char in lowercased {
            buffer.append(char)
            
            // Check if buffer matches any pattern
            var matched = false
            var longestMatch = ""
            var longestMatchKana = ""
            
            // Find the longest matching pattern
            for i in 1...buffer.count {
                let endIndex = buffer.index(buffer.startIndex, offsetBy: i)
                let substring = String(buffer[buffer.startIndex..<endIndex])
                
                if let kana = romajiMap[substring] {
                    longestMatch = substring
                    longestMatchKana = kana
                    matched = true
                }
            }
            
            if matched {
                // Check if we might get a longer match with the next character
                var canContinue = false
                for (key, _) in romajiMap {
                    if key.hasPrefix(buffer) && key.count > buffer.count {
                        canContinue = true
                        break
                    }
                }
                
                if !canContinue {
                    // No longer matches possible, commit the match
                    result += longestMatchKana
                    let remainingStart = buffer.index(buffer.startIndex, offsetBy: longestMatch.count)
                    buffer = String(buffer[remainingStart...])
                }
            } else {
                // No match found
                // Check if buffer could be the start of a valid pattern
                var couldMatch = false
                for (key, _) in romajiMap {
                    if key.hasPrefix(buffer) {
                        couldMatch = true
                        break
                    }
                }
                
                if !couldMatch && !buffer.isEmpty {
                    // No possible match, output first character as-is
                    result += String(buffer.first!)
                    buffer.removeFirst()
                }
            }
        }
        
        // Handle remaining buffer
        result += buffer
        
        return result
    }
}