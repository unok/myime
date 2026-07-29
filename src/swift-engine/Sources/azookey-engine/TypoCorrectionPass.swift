// タイポ補正2パスの設計は docs/architecture.md の typo correction セクションに記述する。
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

nonisolated(unsafe) var typoConverter: KanaKanjiConverter?

/// 2パス変換の上限(読み1件あたり実測 5〜10ms)。
/// 変換(スペース)時は全パターンを試し、打鍵毎のサジェストでは
/// 入力の詰まりを避けるため件数を絞る。mozc 側が種別に応じて設定する
let defaultTypoConversionBudget = 7
nonisolated(unsafe) var typoConversionBudget = defaultTypoConversionBudget
/// AI付き2パス変換は推論コストが高いため、体感確認用に少数へ絞る。
private let typoConversionBudgetWithAi = 7
private let leftoverAlphabetTypoConversionBudget = 8
/// 採用候補がこの数に達したら以降の読みは変換しない
private let maxTypoCandidates = 3

struct TypoCandidate {
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

/// ローマ字→かな変換に失敗して読みへ残った ASCII/全角アルファベットの検出
private func containsAlphabet(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
            || (0xFF21...0xFF3A).contains(scalar.value) || (0xFF41...0xFF5A).contains(scalar.value)
    }
}

/// Get conversion options for typo correction pass (caller must hold engineLock)
private func getTypoOptions() -> ConvertRequestOptions {
    var options = getOptions(allowLearning: false)
    options.learningType = .nothing
    if !config.typoCorrectionUseAi || !config.zenzaiEnabled || config.zenzaiWeightPath.isEmpty {
        options.zenzaiMode = .off
    }
    return options
}

/// Build typo-correction candidates via an isolated second converter (caller must hold engineLock).
func makeTypoCandidates(for key: String, existingCandidates: [Candidate]) -> [TypoCandidate] {
    guard config.typoCorrectionEnabled, let typoConv = typoConverter else {
        return []
    }

    let existingTexts = Set(existingCandidates.map(\.text))
    var typoCandidates: [TypoCandidate] = []
    let typoOptions = getTypoOptions()
    let originalKeyCount = key.count
    let hasLeftoverAlphabet = containsAlphabet(key)

    // 痕跡なし系は誤り位置が不明な総当たりなので、低予算では短い読みに限定する。
    // 長い読みでは正解が生成順の後ろに回りやすく、予算がないと届く前に打ち切られる。
    // アルファベット残留系は残留ランが誤り位置を指すため、読み全体の長さでは制限しない。
    guard hasLeftoverAlphabet || typoConversionBudget >= 30 || originalKeyCount <= 8 else {
        return []
    }

    // 補正読み1件あたり変換1回のコストがかかる(実測 5〜10ms/件)。
    // 打鍵毎のサジェストで払う以上、生成された読みを全部変換せず、
    // 精度の高い順(生成器の並び)に変換して十分な数が採れたら打ち切る
    var convertedCount = 0
    let correctedReadings = hasLeftoverAlphabet
        ? TypoCorrectionReadingGenerator.leftoverAlphabetCandidates(for: key)
        : TypoCorrectionReadingGenerator.generateCandidates(for: key)
    let baseConversionBudget = hasLeftoverAlphabet ? leftoverAlphabetTypoConversionBudget : typoConversionBudget
    // AI 有効時に予算を絞ると候補読みが足りず品質が落ちる(実測: きょうお→京都 が消えた)。
    // コストは mozc 側が「変換時のみ AI 有効」にすることで抑える
    let conversionBudget = baseConversionBudget
    for correctedReading in correctedReadings {
        if convertedCount >= conversionBudget || (!hasLeftoverAlphabet && typoCandidates.count >= maxTypoCandidates) {
            break
        }
        convertedCount += 1
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
                    // アルファベット残留系は局所かな化の成立自体が証拠なので恒等候補も許容する
                    && (hasLeftoverAlphabet || !($0.text == correctedReading && $0.value <= -14))
                    // 絶対バー: 誤った補正読みの強引な変換を除外する。
                    // 実在補正は読み1文字あたり実測 -1.4〜-2.7 に収まるため、
                    // 余裕を持たせて 1文字あたり -6.0 を下限とする
                    && $0.value > PValue(-6 * correctedReading.count)
            }
            .max { $0.value < $1.value }
        // ひらがな素通しより漢字変換を優先する。
        // 残留系では素通しも許容しているため、そのままだと
        // 「わたしはがくせいでした」のようにひらがなのまま出てしまう
        // (実測で確認)。ただし「です」のようにひらがなが正解の場合も
        // あるので、非素通しが無いときだけ素通しを使う
        let bestConverted = result.mainResults
            .filter {
                $0.text != correctedReading
                    && $0.rubyCount == correctedReading.count
                    && !existingTexts.contains($0.text)
                    && !containsAsciiLikeNoise($0.text)
                    && !isScriptVariantOfReading($0.text, reading: correctedReading)
                    && $0.value > PValue(-6 * correctedReading.count)
            }
            .max { $0.value < $1.value }
        // 漢字優先は残留系のみ。痕跡なし系では「こんにちは」のように
        // ひらがなが正解のことがあり、優先すると壊れる(実測で確認)
        let chosen = hasLeftoverAlphabet ? (bestConverted ?? best) : best
        if let best = chosen {
            typoCandidates.append(TypoCandidate(
                text: best.text,
                value: best.value,
                correspondingCount: originalKeyCount,
                correctedReading: correctedReading
            ))
        }
    }

    if hasLeftoverAlphabet {
        var seenTexts = existingTexts
        var filteredCandidates: [TypoCandidate] = []
        for candidate in typoCandidates.sorted(by: { $0.value > $1.value }) {
            guard !seenTexts.contains(candidate.text) else {
                continue
            }
            seenTexts.insert(candidate.text)
            filteredCandidates.append(candidate)
            if filteredCandidates.count == maxTypoCandidates {
                break
            }
        }
        return filteredCandidates
    }

    // 絶対値だけでは「本屋(-11.5、出したい)」と「あたし(-11.1、誤検出)」を
    // 分離できない。ユーザーが打った通りの変換(1パス目)の最良値と比べ、
    // それより明確に劣る補正は出さない: 正しく打てている入力では
    // 1パス目が良い候補を出すので、補正候補は自然に抑制される。
    // 値は読みが長いほど小さくなるため、必ず1モーラあたりに正規化して比較する
    // (生の値で比べると、ん/っ 挿入で長くなる補正が一律に負ける)
    let literalBestPerMora = existingCandidates
        .map { Double($0.value) / Double(max(1, $0.rubyCount)) }
        .max()
    var seenTexts = existingTexts
    var filteredCandidates: [TypoCandidate] = []
    let ranked = typoCandidates.sorted { $0.value > $1.value }
    // ベストから大きく劣る候補(誤った補正読みの強引な変換)は表示しない
    let valueCutoff = (ranked.first?.value).map { $0 - 4.0 }
    for candidate in ranked {
        if let valueCutoff, candidate.value < valueCutoff {
            break
        }
        let candidatePerMora = Double(candidate.value) / Double(max(1, candidate.correctedReading.count))
        // 実測校正: 真の補正は差分 +1.48 〜 -1.66、明らかなゴミは -2.17 以下。
        // 「わたし→あたし」(w 脱落)のように差分 -1.42 の妥当な補正もあるため、
        // 取りこぼしを避ける側に倒して -2.0 を採用する(末尾表示なのでノイズ許容)
        if let literalBestPerMora, candidatePerMora < literalBestPerMora - 2.0 {
            continue
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
