// タイポ補正2パスの設計は docs/architecture.md の typo correction セクションに記述する。
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

nonisolated(unsafe) var typoConverter: KanaKanjiConverter?

/// 2パス変換の上限(読み1件あたり実測 5〜10ms)。
/// 変換(スペース)時は全パターンを試し、打鍵毎のサジェストでは
/// 入力の詰まりを避けるため件数を絞る。mozc 側が種別に応じて設定する
let defaultTypoConversionBudget = 7
nonisolated(unsafe) var typoConversionBudget = defaultTypoConversionBudget
private let leftoverAlphabetTypoConversionBudget = 8
/// 採用候補がこの数に達したら以降の読みは変換しない
private let maxTypoCandidates = 3
/// 位置推定・長文総当たり経路で要求する「1パス目最良からの最低改善幅」
/// (モーラ正規化後)。実測: 真の補正は +15 前後改善するが、ゴミは
/// 置換型(まと→的)で +2.5、削除型はモーラ換算後 +1.5 程度に留まる
private let typoImprovementMargin: PValue = 4.0

struct TypoCandidate {
    let text: String
    let value: PValue
    let correspondingCount: Int
    let correctedReading: String
}

/// 閾値の再校正用の診断出力。環境変数 AZOOKEY_TYPO_DEBUG が設定されている時だけ stderr に出す。
private let typoDebugEnabled = ProcessInfo.processInfo.environment["AZOOKEY_TYPO_DEBUG"] != nil
private func typoDebugLog(_ message: @autoclosure () -> String) {
    guard typoDebugEnabled else { return }
    FileHandle.standardError.write(Data((message() + "\n").utf8))
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

private func isScoredReadingElement(_ ruby: String) -> Bool {
    let foldedRuby = foldedToHiragana(ruby)
    // 長音「ー」(U+30FC)は読みの一部として頻出するため対象に含める
    return !foldedRuby.isEmpty && foldedRuby.unicodeScalars.allSatisfy { scalar in
        (0x3041...0x3096).contains(scalar.value) || scalar.value == 0x30FC
    }
}

/// 位置推定と改善バーに使う「1パス目の全文最良候補」。
/// 読みの恒等・表記ゆれは未知語素通し(value=-14 前後の固定値)として実変換より
/// 高い value を持つため、素の value 最大で選ぶと常にこれが勝ち、単一要素 data で
/// 位置推定が成立しなくなる(実測: ワタシハガコウニイキマシタ v=-14.0 が
/// 私は画稿に行きました v=-44.6 を差し置いて選ばれ、長文補正が全滅した)。
/// 実変換のみに絞ってから value 最大を選ぶ
internal func bestScoredCoveringCandidate(in candidates: [Candidate], key: String) -> Candidate? {
    candidates
        .filter {
            $0.rubyCount == key.count
                && $0.text != key
                && !isScriptVariantOfReading($0.text, reading: key)
                && !containsAsciiLikeNoise($0.text)
        }
        .max { $0.value < $1.value }
}

internal func inferredTypoCorrectionRange(in key: String, data: [DicdataElement]) -> Range<Int>? {
    let foldedKey = foldedToHiragana(key)
    var foldedRuby = ""
    var currentPosition = 0
    var worstRange: Range<Int>?
    var worstValuePerMora: Double?

    for element in data {
        let foldedElementRuby = foldedToHiragana(element.ruby)
        let start = currentPosition
        currentPosition += foldedElementRuby.count
        foldedRuby.append(foldedElementRuby)

        guard foldedKey.hasPrefix(foldedRuby) else {
            return nil
        }
        guard isScoredReadingElement(element.ruby) else {
            continue
        }

        let valuePerMora = Double(element.value()) / Double(max(1, foldedElementRuby.count))
        if worstValuePerMora == nil || valuePerMora < worstValuePerMora! {
            worstValuePerMora = valuePerMora
            worstRange = start..<currentPosition
        }
    }

    guard foldedRuby == foldedKey else {
        return nil
    }
    // 疑いの絶対閾値: 実在語の1文字あたり value は実測 -1.4〜-2.7 に収まり、
    // タイポ由来の強引な語(画稿=-4.7 等)は明確に下回る。閾値なしだと
    // 正しい文でも相対的に最悪な語を疑ってしまい誤検出の元になる
    // (実測: おはようございますみなさん の ミナサン=-2.07 を疑って ん挿入ゴミが出た)
    // 健全な文でも 窓(マド)=-4.47/文字 のように -4.0 を下回る要素はあり、
    // 真のタイポ(画稿=-4.71/文字)と閾値では分離できない。閾値は発火頻度
    // (無駄な変換コスト)を抑える粗いゲートに留め、誤検出の最終防衛は
    // 改善バー(モーラ正規化+マージン)が担う
    guard let worst = worstValuePerMora, worst <= -4.0 else {
        return nil
    }
    return worstRange
}

private func localizedTypoCorrectionReadings(for key: String, suspectedRange: Range<Int>) -> [String] {
    let characters = Array(key)
    let spanStart = max(0, suspectedRange.lowerBound - 1)
    let spanEnd = min(characters.count, suspectedRange.upperBound + 1)
    let span = String(characters[spanStart..<spanEnd])
    var seen = Set<String>([key])
    var readings: [String] = []

    for correctedSpan in TypoCorrectionReadingGenerator.generateCandidates(for: span) {
        var correctedCharacters = characters
        correctedCharacters.replaceSubrange(spanStart..<spanEnd, with: Array(correctedSpan))
        let correctedReading = String(correctedCharacters)
        guard correctedReading != key, !seen.contains(correctedReading) else {
            continue
        }
        seen.insert(correctedReading)
        readings.append(correctedReading)
    }

    return readings
}

/// Get conversion options for typo correction pass (caller must hold engineLock)
private func getTypoOptions() -> ConvertRequestOptions {
    let config = currentConfig()
    var options = getOptions(allowLearning: false)
    options.learningType = .nothing
    if !config.typoCorrectionUseAi || !config.zenzaiEnabled || config.zenzaiWeightPath.isEmpty {
        options.zenzaiMode = .off
    }
    return options
}

/// Build typo-correction candidates via an isolated second converter (caller must hold engineLock).
func makeTypoCandidates(for key: String, existingCandidates: [Candidate]) -> [TypoCandidate] {
    let config = currentConfig()
    guard config.typoCorrectionEnabled, let typoConv = typoConverter else {
        return []
    }

    let existingTexts = Set(existingCandidates.map(\.text))
    var typoCandidates: [TypoCandidate] = []
    let typoOptions = getTypoOptions()
    let originalKeyCount = key.count
    let hasLeftoverAlphabet = containsAlphabet(key)
    let shouldTryPositionedCorrection = !hasLeftoverAlphabet && originalKeyCount >= 9
    let bestCoveringCandidateForWhole: Candidate?
    if !hasLeftoverAlphabet && originalKeyCount >= 9 {
        bestCoveringCandidateForWhole = bestScoredCoveringCandidate(in: existingCandidates, key: key)
    } else {
        bestCoveringCandidateForWhole = nil
    }
    let localCorrectionReadings: [String]?
    let literalWholeBestValue = bestCoveringCandidateForWhole?.value
    if shouldTryPositionedCorrection,
       let bestCoveringCandidate = bestCoveringCandidateForWhole {
        if let suspectedRange = inferredTypoCorrectionRange(in: key, data: bestCoveringCandidate.data) {
            localCorrectionReadings = localizedTypoCorrectionReadings(for: key, suspectedRange: suspectedRange)
        } else {
            localCorrectionReadings = nil
        }
    } else {
        localCorrectionReadings = nil
    }

    // 痕跡なし系は誤り位置が不明な総当たりなので、低予算では短い読みに限定する。
    // 長い読みでは正解が生成順の後ろに回りやすく、予算がないと届く前に打ち切られる。
    // アルファベット残留系は残留ランが誤り位置を指すため、読み全体の長さでは制限しない。
    // 位置推定が成立した場合のみ長文を許す。推定失敗(疑い語なし・分割不一致)で
    // 総当たりに落ちると、低予算の長文でゴミと空振りコストだけが残る
    guard localCorrectionReadings != nil || hasLeftoverAlphabet || typoConversionBudget >= 30 || originalKeyCount <= 8 else {
        return []
    }

    // 補正読み1件あたり変換1回のコストがかかる(実測 5〜10ms/件)。
    // 打鍵毎のサジェストで払う以上、生成された読みを全部変換せず、
    // 精度の高い順(生成器の並び)に変換して十分な数が採れたら打ち切る
    var convertedCount = 0
    let correctedReadings = localCorrectionReadings ?? (hasLeftoverAlphabet
        ? TypoCorrectionReadingGenerator.leftoverAlphabetCandidates(for: key)
        : TypoCorrectionReadingGenerator.generateCandidates(for: key))
    let baseConversionBudget = hasLeftoverAlphabet ? leftoverAlphabetTypoConversionBudget : typoConversionBudget
    // AI 有効時に予算を絞ると候補読みが足りず品質が落ちる(実測: きょうお→京都 が消えた)。
    // コストは mozc 側が「変換時のみ AI 有効」にすることで抑える。
    // 位置推定経路の読みは高々16件で、途中打ち切りは劣った候補の採用に直結する
    // (実測: 予算12で本命の っ挿入 に届かず ん挿入 由来の「眼孔」が出た)ため全件変換する
    let conversionBudget = localCorrectionReadings.map { max(baseConversionBudget, $0.count) } ?? baseConversionBudget
    func convertTypoReadings(_ readings: [String], requiringImprovementOver minimumValue: PValue? = nil) {
        for correctedReading in readings {
            if convertedCount >= conversionBudget
                || (!hasLeftoverAlphabet && minimumValue == nil && typoCandidates.count >= maxTypoCandidates) {
                break
            }
            convertedCount += 1
            // 読み長の異なる補正(ん/っ挿入で+1、余分文字削除で-1)を生値で比べると
            // 短い読みほど構造的に有利になる(実測: お削除の「中が好きました」が
            // +4.8 の見かけ改善)。literal 最良の1モーラあたり値×補正読み長で
            // 「同じ読み長ならこの程度」に換算してから改善を要求する
            let improvementBar = minimumValue.map {
                $0 / PValue(originalKeyCount) * PValue(correctedReading.count) + typoImprovementMargin
            }
            var text = ComposingText()
            text.insertAtCursorPosition(correctedReading, inputStyle: .direct)
            let result = typoConv.requestCandidates(text, options: typoOptions)
            typoDebugLog("[typo] key=\(key) reading=\(correctedReading) bar=\(improvementBar.map { String(describing: $0) } ?? "nil") top=" + result.mainResults.prefix(6).map { "\($0.text)/\($0.rubyCount)/\($0.value)" }.joined(separator: " "))

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
                        // 位置推定経路では「1パス目の全文最良より厳密に良い」ことを要求。
                        // 本物のタイポ修正は壊れた語がスコアを下げている分だけ全文が
                        // 改善する(実測: 画稿 -29.7 → 学校 で大幅改善)。長文では
                        // -6/文字の絶対バーが甘くなりすぎ、ゴミが maxTypoCandidates の
                        // 枠を食い潰して本命に届かなくなる(実測で確認)
                        && (improvementBar == nil || $0.value > improvementBar!)
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
                        && (improvementBar == nil || $0.value > improvementBar!)
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
    }

    // 長文(9文字以上)では位置推定・総当たりを問わず1パス目最良からの明確な改善を要求する。
    // 予算60の総当たりで ん挿入の実在語化(診療/勤王)や先頭ん挿入がバーなしで素通しした(実測)。
    // 短い読み(8文字以下)は従来の1モーラ正規化マージン方式を維持(本屋 -11.5 等は生値比較だと負ける)
    convertTypoReadings(
        correctedReadings,
        requiringImprovementOver: originalKeyCount >= 9 ? literalWholeBestValue : nil)

    if let localCorrectionReadings, typoCandidates.isEmpty, convertedCount < conversionBudget {
        let fallbackReadings = TypoCorrectionReadingGenerator.generateCandidates(for: key)
            .filter { !localCorrectionReadings.contains($0) }
        convertTypoReadings(
            fallbackReadings,
            requiringImprovementOver: originalKeyCount >= 9 ? literalWholeBestValue : nil)
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
    // 予測候補(入力より長い読み)は比較対象から外す。AzooKeyKanaKanjiConverter の
    // 2026-08 世代で予測候補の value が変換候補と別スケール(-19 → -2 程度)になり、
    // 混ぜると本屋(-11.8/3)や京都(-10.8/4)が一律に落ちる(実測)。
    // 接頭辞断片(が/1 等)は変換候補と同じスケールで、-2.0 のマージンは断片込みで
    // 校正されている(入力全体をカバーする候補だけにすると がっこう→顎骨 が誤検出)ため残す
    let literalBestPerMora = existingCandidates
        .filter { $0.rubyCount <= originalKeyCount }
        .map { Double($0.value) / Double(max(1, $0.rubyCount)) }
        .max()
    var seenTexts = existingTexts
    var filteredCandidates: [TypoCandidate] = []
    let ranked = typoCandidates.sorted { $0.value > $1.value }
    // ベストから大きく劣る候補(誤った補正読みの強引な変換)は表示しない
    let valueCutoff = (ranked.first?.value).map { $0 - 4.0 }
    typoDebugLog("[typo] key=\(key) literalBestPerMora=\(literalBestPerMora.map { String($0) } ?? "nil") literalTop=" + existingCandidates.sorted { Double($0.value) / Double(max(1, $0.rubyCount)) > Double($1.value) / Double(max(1, $1.rubyCount)) }.prefix(4).map { "\($0.text)/\($0.rubyCount)/\($0.value)" }.joined(separator: " ") + " ranked=" + ranked.map { "\($0.text)/\($0.correctedReading)/\($0.value)" }.joined(separator: " "))
    for candidate in ranked {
        if let valueCutoff, candidate.value < valueCutoff {
            break
        }
        let candidatePerMora = Double(candidate.value) / Double(max(1, candidate.correctedReading.count))
        // 実測校正: 真の補正は差分 +1.48 〜 -1.66、明らかなゴミは -2.17 以下。
        // 「わたし→あたし」(w 脱落)のように差分 -1.42 の妥当な補正もあるため、
        // 取りこぼしを避ける側に倒して -2.0 を採用していた(末尾表示なのでノイズ許容)。
        // 辞書 v3.1 では基準側の断片(が/1)が -1.48 → -1.79 に下がり、
        // がっこう→顎骨(差分 -1.95)が -2.0 を通り抜けたため -1.8 に詰める
        // (真の補正の最悪 -1.66 との余裕 0.14、顎骨との余裕 0.15)
        if let literalBestPerMora, candidatePerMora < literalBestPerMora - 1.8 {
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
