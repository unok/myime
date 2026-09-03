// タイポ補正2パスの設計は docs/architecture.md の typo correction セクションに記述する。
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
#if os(Windows)
import WinSDK
#endif

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

/// 短文タイポ補正の再校正値。予算60の実測では2文字の誤検出は長さゲートで消えた一方、
/// 正しい3〜4文字語の全文 literal は -3.08〜-4.48/mora（昨日、家族、リンゴ、未完等）に
/// 分布した。入力全体を単語1個で変換できれば原則 solid とし、-5.0/mora 未満の極端に
/// 弱い literal（がこう→画稿 -5.3）だけ fragment に戻す。solid 時は literal を 2.0/mora
/// 以上上回る補正だけ採用する（掃引: 真陽性 7/7 を保ったまま3文字以上122件で
/// 誤検出0（2文字以下は最小入力長で除外）。改善幅 1.0 では みかん→民間 +1.64 が残る）。
private let shortTypoMarginPerMora = -1.8
private let solidLiteralPerMora = -5.0
private let solidLiteralImprovement = 2.0
private let minimumTypoInputLength = 3

struct TypoCandidate {
    let text: String
    let value: PValue
    let correspondingCount: Int
    let correctedReading: String
    let lastCid: Int?
    let conjugationForm: String?

    init(
        text: String,
        value: PValue,
        correspondingCount: Int,
        correctedReading: String,
        lastCid: Int? = nil,
        conjugationForm: String? = nil
    ) {
        self.text = text
        self.value = value
        self.correspondingCount = correspondingCount
        self.correctedReading = correctedReading
        self.lastCid = lastCid
        self.conjugationForm = conjugationForm
    }
}

private let nonterminalConjugationForms: Set<String> = [
    "未然形", "未然ウ接続", "未然特殊", "未然ヌ接続", "未然レル接続",
    "連用形", "連用タ接続", "連用テ接続", "連用デ接続", "連用ニ接続", "連用ゴザイ接続",
    "体言接続", "体言接続特殊", "体言接続特殊２", "ガル接続",
    // 縮約形は単独で文末に立たないため、仮定形は残して仮定縮約だけを落とす。
    "仮定縮約１", "仮定縮約２"
]

internal struct TypoCandidateMorphology: Equatable {
    let cid: Int
    let conjugationType: String
    let conjugationForm: String
    let isNonterminal: Bool
}

/// 最終要素の右CIDを優先し、IPADIC表に無い場合だけ左CIDへフォールバックする。
/// 文語・*型は一律除外。形容詞・アウオ段,文語基本形 は活用型が現代型なのでここには来ない。
/// 上二・下二・四段は文語・*型ではなく、現状どおり活用型による一律除外の対象外。
internal func typoCandidateMorphology(data: [DicdataElement]) -> TypoCandidateMorphology? {
    guard let last = data.last else { return nil }
    let cidAndFeature: (Int, String)?
    if let feature = IpadicCidTable.cidToFeature[last.rcid] {
        cidAndFeature = (last.rcid, feature)
    } else if let feature = IpadicCidTable.cidToFeature[last.lcid] {
        cidAndFeature = (last.lcid, feature)
    } else {
        cidAndFeature = nil
    }
    guard let (cid, feature) = cidAndFeature else { return nil }
    let fields = feature.split(separator: ",", omittingEmptySubsequences: false)
    guard fields.count >= 6 else { return nil }
    let conjugationType = String(fields[4])
    let conjugationForm = String(fields[5])
    let isLiteraryNonterminal = conjugationType.hasPrefix("文語・")
    return TypoCandidateMorphology(
        cid: cid,
        conjugationType: conjugationType,
        conjugationForm: conjugationForm,
        isNonterminal: nonterminalConjugationForms.contains(conjugationForm) || isLiteraryNonterminal
    )
}

internal func shouldFilterNonterminalTypoCandidate(
    data: [DicdataElement],
    hasLeftoverAlphabet: Bool
) -> Bool {
    !hasLeftoverAlphabet && (typoCandidateMorphology(data: data)?.isNonterminal ?? false)
}

/// 閾値の再校正用の診断出力。環境変数 AZOOKEY_TYPO_DEBUG が設定されている時だけ出す。
private let typoDebugEnabled = ProcessInfo.processInfo.environment["AZOOKEY_TYPO_DEBUG"] != nil
private func typoDebugLog(_ message: @autoclosure () -> String) {
    guard typoDebugEnabled else { return }
    let line = message() + "\n"
#if os(Windows)
    line.withCString(encodedAs: UTF16.self) { OutputDebugStringW($0) }
#endif
    fputs(line, stderr)
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

/// 補正候補の絞り込みに使う「ユーザーが打った通りの変換(1パス目)」の基準集合と、
/// その 1 モーラあたり最良値。
/// 絶対値だけでは「本屋(-11.5、出したい)」と「あたし(-11.1、誤検出)」を分離できないため、
/// 1パス目の最良値と比べて明確に劣る補正は出さない(正しく打てている入力では 1パス目が
/// 良い候補を出すので補正候補は自然に抑制される)。値は読みが長いほど小さくなるため
/// 必ず 1 モーラあたりに正規化する(生の値だと ん/っ 挿入で長くなる補正が一律に負ける)。
/// 予測候補(入力より長い読み)は比較対象から外す: AzooKeyKanaKanjiConverter の
/// 2026-08 世代で予測候補の value が変換候補と別スケール(-19 → -2 程度)になり、
/// 混ぜると本屋(-11.8/3)や京都(-10.8/4)が一律に落ちる(実測)。接頭辞断片(が/1 等)は
/// 変換候補と同じスケールでマージンが断片込みで校正されているため残す
/// (入力全体をカバーする候補だけにすると がっこう→顎骨 が誤検出)。
/// 予測候補しか無い場合は全体にフォールバックし、既存候補ゼロなら nil。
private func literalBaseline(
    existingCandidates: [Candidate],
    originalKeyCount: Int
) -> (candidates: [Candidate], bestPerMora: Double)? {
    let filteredCandidates = existingCandidates.filter { $0.rubyCount <= originalKeyCount }
    let baselineCandidates = filteredCandidates.isEmpty ? existingCandidates : filteredCandidates
    guard let bestPerMora = baselineCandidates
        .map({ Double($0.value) / Double(max(1, $0.rubyCount)) })
        .max()
    else {
        return nil
    }
    return (baselineCandidates, bestPerMora)
}

/// 1パス目にある、入力全体を単一語でカバーする非恒等 literal の最良値。
private func literalWholeBest(
    existingCandidates: [Candidate],
    originalKeyCount: Int
) -> (text: String, perMora: Double)? {
    existingCandidates
        .filter {
            $0.rubyCount == originalKeyCount
                && $0.data.count == 1
                && $0.text != foldedToHiragana($0.data[0].ruby)
                && $0.text != $0.data[0].ruby.toKatakana()
        }
        .map {
            ($0.text, Double($0.value) / Double(max(1, $0.rubyCount)))
        }
        .max { $0.1 < $1.1 }
}

private enum ShortTypoSelectionGate: String, Equatable {
    case solid
    case fragment
    case tooShort = "too_short"
}

private func shortTypoSelectionGate(
    literalWholeBest: (text: String, perMora: Double)?,
    originalKeyCount: Int
) -> ShortTypoSelectionGate {
    if originalKeyCount < minimumTypoInputLength {
        return .tooShort
    }
    if let literalWholeBest, literalWholeBest.perMora >= solidLiteralPerMora {
        return .solid
    }
    return .fragment
}

internal func selectTypoCandidates(
    _ typoCandidates: [TypoCandidate],
    existingCandidates: [Candidate],
    originalKeyCount: Int
) -> [TypoCandidate] {
    guard let baseline = literalBaseline(
        existingCandidates: existingCandidates,
        originalKeyCount: originalKeyCount
    ) else {
        return []
    }

    let wholeBest = originalKeyCount <= 8
        ? literalWholeBest(existingCandidates: existingCandidates, originalKeyCount: originalKeyCount)
        : nil
    let gate = originalKeyCount <= 8
        ? shortTypoSelectionGate(literalWholeBest: wholeBest, originalKeyCount: originalKeyCount)
        : .fragment
    guard gate != .tooShort else {
        return []
    }

    var seenTexts = Set(existingCandidates.map(\.text))
    var filteredCandidates: [TypoCandidate] = []
    let ranked = typoCandidates.sorted { $0.value > $1.value }
    // ベストから大きく劣る候補(誤った補正読みの強引な変換)は表示しない
    let valueCutoff = (ranked.first?.value).map { $0 - 4.0 }
    for candidate in ranked {
        if let valueCutoff, candidate.value < valueCutoff {
            break
        }
        let candidatePerMora = Double(candidate.value) / Double(max(1, candidate.correctedReading.count))
        // 確固とした単語がある場合はそれ自身からの改善を要求する。無い場合だけ、
        // 真陽性の最悪差分 -1.66 と既知ゴミ -1.95 の間に置いた従来 -1.8 を使う。
        if gate == .solid, let wholeBest {
            if candidatePerMora <= wholeBest.perMora + solidLiteralImprovement {
                continue
            }
        } else if candidatePerMora < baseline.bestPerMora + shortTypoMarginPerMora {
            continue
        }
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

private func typoSelectionDebugMessage(
    key: String,
    typoCandidates: [TypoCandidate],
    existingCandidates: [Candidate],
    originalKeyCount: Int
) -> String {
    let baseline = literalBaseline(
        existingCandidates: existingCandidates,
        originalKeyCount: originalKeyCount
    )
    let literalTop = (baseline?.candidates ?? [])
        .sorted {
            Double($0.value) / Double(max(1, $0.rubyCount))
                > Double($1.value) / Double(max(1, $1.rubyCount))
        }
        .prefix(4)
        .map { "\($0.text)/\($0.rubyCount)/\($0.value)" }
        .joined(separator: " ")
    let ranked = typoCandidates
        .sorted { $0.value > $1.value }
        .map {
            "\($0.text)/\($0.correctedReading)/\($0.value)/\($0.lastCid.map { String($0) } ?? "nil")/\($0.conjugationForm ?? "nil")"
        }
        .joined(separator: " ")
    return "[typo] key=\(key) literalBestPerMora=\(baseline.map { String($0.bestPerMora) } ?? "nil") literalTop=\(literalTop) ranked=\(ranked)"
}

private func typoSelectionGateDebugMessage(
    key: String,
    existingCandidates: [Candidate],
    originalKeyCount: Int
) -> String {
    let wholeBest = originalKeyCount <= 8
        ? literalWholeBest(existingCandidates: existingCandidates, originalKeyCount: originalKeyCount)
        : nil
    let gate = originalKeyCount <= 8
        ? shortTypoSelectionGate(literalWholeBest: wholeBest, originalKeyCount: originalKeyCount)
        : .fragment
    return "[typo] key=\(key) literalWholeBestPerMora=\(wholeBest.map { String($0.perMora) } ?? "nil") literalWholeBestText=\(wholeBest?.text ?? "nil") gate=\(gate.rawValue)"
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

    let originalKeyCount = key.count
    let hasLeftoverAlphabet = containsAlphabet(key)
    guard hasLeftoverAlphabet || originalKeyCount >= minimumTypoInputLength else {
        return []
    }
    let existingTexts = Set(existingCandidates.map(\.text))
    var typoCandidates: [TypoCandidate] = []
    let typoOptions = getTypoOptions()
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
            typoDebugLog(
                "[typo] key=\(key) reading=\(correctedReading) bar=\(improvementBar.map { String(describing: $0) } ?? "nil") top="
                    + result.mainResults.prefix(6).map { candidate in
                        let morphology = typoCandidateMorphology(data: candidate.data)
                        return "\(candidate.text)/\(candidate.rubyCount)/\(candidate.value)/"
                            + "\(morphology.map { String($0.cid) } ?? "nil")/"
                            + "\(morphology?.conjugationForm ?? "nil")/"
                            + "\(morphology?.isNonterminal == true ? "nonterminal" : "terminal")"
                    }.joined(separator: " ")
            )

            // mainResults の並びは表記バリエーション(value=-190 の素通し系)が先頭に
            // 来ることがあるため、先頭ではなく value 最大の候補を選ぶ。
            // ひらがな表記が正解の語(こんにちは 等)があるため、補正読みと同一の
            // テキストは除外しない。数字・アルファベット混入(に→2 等の過大評価)は除外
            let eligibleCandidates = result.mainResults
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
            let terminalCandidates = eligibleCandidates.filter { candidate in
                let morphology = typoCandidateMorphology(data: candidate.data)
                let isFiltered = shouldFilterNonterminalTypoCandidate(
                    data: candidate.data,
                    hasLeftoverAlphabet: hasLeftoverAlphabet
                )
                typoDebugLog(
                    "[typo] key=\(key) reading=\(correctedReading) candidate=\(candidate.text) "
                        + "value=\(candidate.value) lastCid=\(morphology.map { String($0.cid) } ?? "nil") "
                        + "form=\(morphology?.conjugationForm ?? "nil") "
                        + "decision=\(isFiltered ? "nonterminal" : "eligible")"
                )
                return !isFiltered
            }
            let best = terminalCandidates
                .max { $0.value < $1.value }
            // ひらがな素通しより漢字変換を優先する。
            // 残留系では素通しも許容しているため、そのままだと
            // 「わたしはがくせいでした」のようにひらがなのまま出てしまう
            // (実測で確認)。ただし「です」のようにひらがなが正解の場合も
            // あるので、非素通しが無いときだけ素通しを使う
            let bestConverted = terminalCandidates
                .filter {
                    $0.text != correctedReading
                }
                .max { $0.value < $1.value }
            // 漢字優先は残留系のみ。痕跡なし系では「こんにちは」のように
            // ひらがなが正解のことがあり、優先すると壊れる(実測で確認)
            let chosen = hasLeftoverAlphabet ? (bestConverted ?? best) : best
            if let best = chosen {
                let morphology = typoCandidateMorphology(data: best.data)
                typoCandidates.append(TypoCandidate(
                    text: best.text,
                    value: best.value,
                    correspondingCount: originalKeyCount,
                    correctedReading: correctedReading,
                    lastCid: morphology?.cid,
                    conjugationForm: morphology?.conjugationForm
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

    // 絞り込みの基準と閾値は literalBaseline / selectTypoCandidates を参照
    typoDebugLog(typoSelectionDebugMessage(
        key: key,
        typoCandidates: typoCandidates,
        existingCandidates: existingCandidates,
        originalKeyCount: originalKeyCount
    ))
    typoDebugLog(typoSelectionGateDebugMessage(
        key: key,
        existingCandidates: existingCandidates,
        originalKeyCount: originalKeyCount
    ))
    return selectTypoCandidates(
        typoCandidates,
        existingCandidates: existingCandidates,
        originalKeyCount: originalKeyCount
    )
}
