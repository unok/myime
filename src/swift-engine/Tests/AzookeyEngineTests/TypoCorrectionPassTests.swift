import XCTest
import KanaKanjiConverterModuleWithDefaultDictionary
@testable import azookey_engine

final class TypoCorrectionPassTests: XCTestCase {
    func testInferredTypoCorrectionRangeReturnsWorstSegmentRange() {
        let data = [
            makeData(word: "私", ruby: "わたし", value: -3),
            makeData(word: "は", ruby: "は", value: -1),
            makeData(word: "画稿", ruby: "ガコウ", value: -24),
            makeData(word: "に", ruby: "に", value: -1),
            makeData(word: "行きました", ruby: "いきました", value: -6)
        ]

        XCTAssertEqual(inferredTypoCorrectionRange(in: "わたしはがこうにいきました", data: data), 4..<7)
    }

    func testInferredTypoCorrectionRangeReturnsNilForMismatchedRubyStack() {
        let data = [
            makeData(word: "私", ruby: "わたし", value: -3),
            makeData(word: "は", ruby: "は", value: -1),
            makeData(word: "学校", ruby: "がっこう", value: -4)
        ]

        XCTAssertNil(inferredTypoCorrectionRange(in: "わたしはがこう", data: data))
    }

    func testInferredTypoCorrectionRangeReturnsNilAboveThreshold() {
        let data = [
            makeData(word: "窓", ruby: "マド", value: -7.52),
            makeData(word: "を", ruby: "ヲ", value: -1),
            makeData(word: "開けてもいいですか", ruby: "アケテモイイデスカ", value: -12)
        ]

        // -3.76/文字 は閾値 -4.0 より上なので発火しない(境界確認)
        XCTAssertNil(inferredTypoCorrectionRange(in: "まどをあけてもいいですか", data: data))
    }

    func testInferredTypoCorrectionRangeReturnsWorstSegmentAtTypoBoundary() {
        let data = [
            makeData(word: "私", ruby: "わたし", value: -3),
            makeData(word: "は", ruby: "は", value: -1),
            makeData(word: "画稿", ruby: "ガコウ", value: -14.13),
            makeData(word: "に", ruby: "に", value: -1),
            makeData(word: "行きました", ruby: "いきました", value: -6)
        ]

        XCTAssertEqual(inferredTypoCorrectionRange(in: "わたしはがこうにいきました", data: data), 4..<7)
    }

    // 未知語素通し(表記ゆれ恒等、value=-14 固定)は実変換(-44 台)より value が
    // 高いため、素の value 最大で選ぶと常に勝ってしまい位置推定が成立しない。
    // 実変換のみから選ぶことの回帰テスト
    func testBestScoredCoveringCandidateSkipsScriptVariantPassthrough() {
        let key = "わたしはがこうにいきました"
        let passthrough = makeCandidate(
            text: "ワタシハガコウニイキマシタ", value: -14.0,
            data: [makeData(word: "ワタシハガコウニイキマシタ", ruby: "ワタシハガコウニイキマシタ", value: -14.0)])
        let identity = makeCandidate(
            text: key, value: -14.5,
            data: [makeData(word: key, ruby: "ワタシハガコウニイキマシタ", value: -14.5)])
        let converted = makeCandidate(
            text: "私は画稿に行きました", value: -44.6,
            data: [
                makeData(word: "私", ruby: "ワタシ", value: -3.7),
                makeData(word: "は", ruby: "ハ", value: -1.4),
                makeData(word: "画稿", ruby: "ガコウ", value: -14.1),
                makeData(word: "に行きました", ruby: "ニイキマシタ", value: -10.5)
            ])

        let best = bestScoredCoveringCandidate(in: [passthrough, identity, converted], key: key)
        XCTAssertEqual(best?.text, "私は画稿に行きました")
    }

    func testBestScoredCoveringCandidateReturnsNilWithoutRealConversion() {
        let key = "わたしはがこうにいきました"
        let passthrough = makeCandidate(
            text: "ワタシハガコウニイキマシタ", value: -14.0,
            data: [makeData(word: "ワタシハガコウニイキマシタ", ruby: "ワタシハガコウニイキマシタ", value: -14.0)])

        XCTAssertNil(bestScoredCoveringCandidate(in: [passthrough], key: key))
    }

    func testNonterminalConjugationIsFilteredButBasicFormRemains() {
        let tsukai = makeData(word: "使い", ruby: "ツカイ", value: -3, cid: 832)
        let tsukau = makeData(word: "使う", ruby: "ツカウ", value: -3, cid: 817)

        let nonterminal = typoCandidateMorphology(data: [tsukai])
        XCTAssertEqual(nonterminal?.conjugationForm, "連用形")
        XCTAssertEqual(nonterminal?.isNonterminal, true)
        XCTAssertTrue(shouldFilterNonterminalTypoCandidate(
            data: [tsukai], hasLeftoverAlphabet: false))
        XCTAssertFalse(shouldFilterNonterminalTypoCandidate(
            data: [tsukai], hasLeftoverAlphabet: true))

        let terminal = typoCandidateMorphology(data: [tsukau])
        XCTAssertEqual(terminal?.conjugationForm, "基本形")
        XCTAssertEqual(terminal?.isNonterminal, false)
        XCTAssertFalse(shouldFilterNonterminalTypoCandidate(
            data: [tsukau], hasLeftoverAlphabet: false))
    }

    func testPhonologicalBasicFormIsTerminalButContractedConditionalIsNot() {
        let colloquialTerminal = typoCandidateMorphology(data: [
            makeData(word: "たい", ruby: "タイ", value: -3, cid: 440)
        ])
        XCTAssertEqual(colloquialTerminal?.conjugationForm, "音便基本形")
        XCTAssertEqual(colloquialTerminal?.isNonterminal, false)

        let colloquialNegativeTerminal = typoCandidateMorphology(data: [
            makeData(word: "ねえ", ruby: "ネエ", value: -3, cid: 469)
        ])
        XCTAssertEqual(colloquialNegativeTerminal?.conjugationForm, "音便基本形")
        XCTAssertEqual(colloquialNegativeTerminal?.isNonterminal, false)

        let contractedConditional = typoCandidateMorphology(data: [
            makeData(word: "たい", ruby: "タイ", value: -3, cid: 442)
        ])
        XCTAssertEqual(contractedConditional?.conjugationForm, "仮定縮約１")
        XCTAssertEqual(contractedConditional?.isNonterminal, true)
    }

    func testLiteraryTypeIsAlwaysFilteredButClassicalConjugationTypeIsNotBlanketFiltered() {
        let literaryBasic = typoCandidateMorphology(data: [
            makeData(word: "き", ruby: "キ", value: -3, cid: 516)
        ])
        XCTAssertEqual(literaryBasic?.conjugationType, "文語・キ")
        XCTAssertEqual(literaryBasic?.conjugationForm, "基本形")
        XCTAssertEqual(literaryBasic?.isNonterminal, true)

        let lowerBigramBasic = typoCandidateMorphology(data: [
            makeData(word: "つ", ruby: "ツ", value: -3, cid: 370)
        ])
        XCTAssertEqual(lowerBigramBasic?.conjugationType, "下二・タ行")
        XCTAssertEqual(lowerBigramBasic?.conjugationForm, "基本形")
        XCTAssertEqual(lowerBigramBasic?.isNonterminal, false)
    }

    func testKatakanaTranscriptionDoesNotBecomeLiteralWholeBest() {
        let selected = selectTypoCandidates(
            [makeTypoCandidate(text: "本屋", reading: "ほんや", value: -2.4)],
            existingCandidates: [
                makeCandidate(text: "ホニャ", reading: "ほにゃ", value: -2.8, composingCount: 3)
            ],
            originalKeyCount: 3
        )

        // ホニャを solid literal と誤認すると -0.8 <= -0.933... + 2.0 で落ちる。
        XCTAssertEqual(selected.map(\.text), ["本屋"])
    }

    func testSolidLiteralMinusFivePointZeroBoundary() {
        let typo = [makeTypoCandidate(text: "補正", reading: "ほせい", value: -12.9)]
        let atBoundary = selectTypoCandidates(
            typo,
            existingCandidates: [
                makeCandidate(text: "基準", reading: "きじゅ", value: -15.0, composingCount: 3)
            ],
            originalKeyCount: 3
        )
        let belowBoundary = selectTypoCandidates(
            typo,
            existingCandidates: [
                makeCandidate(text: "基準", reading: "きじゅ", value: -15.003, composingCount: 3)
            ],
            originalKeyCount: 3
        )

        // -5.0/mora は solid（+2.0 を厳密に超えず不採用）、直下は fragment。
        XCTAssertTrue(atBoundary.isEmpty)
        XCTAssertEqual(belowBoundary.map(\.text), ["補正"])
    }

    func testSelectTypoCandidatesCalibratedExamples() {
        struct TestCase {
            let name: String
            let existingCandidates: [Candidate]
            let originalKeyCount: Int
            let typoCandidates: [TypoCandidate]
            let expectedTexts: [String]
        }

        let cases = [
            TestCase(
                name: "がっこう rejects 顎骨 after excluding prediction",
                existingCandidates: [
                    makeCandidate(text: "学校", reading: "がっこう", value: -9.032, composingCount: 4),
                    makeCandidate(text: "がっ", reading: "がっ", value: -3.6375, composingCount: 2),
                    makeCandidate(text: "が", reading: "が", value: -1.791, composingCount: 1),
                    makeCandidate(text: "学校の", reading: "がっこうの", value: 3.2887, composingCount: 5)
                ],
                originalKeyCount: 4,
                typoCandidates: [makeTypoCandidate(text: "顎骨", reading: "がっこつ", value: -14.9625)],
                expectedTexts: []),
            TestCase(
                name: "ほんや retains 本屋 after excluding prediction",
                existingCandidates: [
                    makeCandidate(text: "ほにゃらら", reading: "ほにゃらら", value: -2.0994, composingCount: 5),
                    makeCandidate(text: "ホンヤ", reading: "ほんや", value: -14.0, composingCount: 3),
                    makeCandidate(text: "歩", reading: "ほ", value: -7.0404, composingCount: 1)
                ],
                originalKeyCount: 3,
                typoCandidates: [makeTypoCandidate(text: "本屋", reading: "ほんや", value: -11.8134)],
                expectedTexts: ["本屋"]),
            TestCase(
                name: "きょうお retains 京都 after excluding prediction",
                existingCandidates: [
                    makeCandidate(text: "今日俺", reading: "きょうおれ", value: -1.7255, composingCount: 5),
                    makeCandidate(text: "今日", reading: "きょう", value: -5.1176, composingCount: 3)
                ],
                originalKeyCount: 4,
                typoCandidates: [makeTypoCandidate(text: "京都", reading: "きょうと", value: -10.7536)],
                expectedTexts: ["京都"]),
            TestCase(
                name: "solid whole literal rejects a marginal improvement",
                existingCandidates: [
                    makeCandidate(text: "今日", reading: "きょう", value: -8.1, composingCount: 3)
                ],
                originalKeyCount: 3,
                typoCandidates: [makeTypoCandidate(text: "良う", reading: "りょう", value: -7.8)],
                expectedTexts: []),
            TestCase(
                name: "weak whole literal keeps fragment margin behavior",
                existingCandidates: [
                    makeCandidate(text: "画稿", reading: "がこう", value: -14.1, composingCount: 3),
                    makeCandidate(text: "が", reading: "が", value: -1.0, composingCount: 1)
                ],
                originalKeyCount: 3,
                typoCandidates: [makeTypoCandidate(text: "学校", reading: "がっこう", value: -9.2)],
                expectedTexts: ["学校"]),
            TestCase(
                name: "two-character non-alphabet input is too short",
                existingCandidates: [
                    makeCandidate(text: "雪", reading: "ゆき", value: -8.0, composingCount: 2)
                ],
                originalKeyCount: 2,
                typoCandidates: [makeTypoCandidate(text: "行こ", reading: "ゆこ", value: -3.0)],
                expectedTexts: []),
            TestCase(
                name: "prediction-only baseline falls back and rejects weak typo",
                existingCandidates: [
                    makeCandidate(text: "予測候補", reading: "よそく", value: -3.0, composingCount: 4),
                    makeCandidate(text: "予測語", reading: "よそくご", value: -5.0, composingCount: 5)
                ],
                originalKeyCount: 2,
                typoCandidates: [makeTypoCandidate(text: "弱い補正", reading: "よわ", value: -9.0)],
                expectedTexts: []),
            TestCase(
                name: "empty existing candidates returns empty",
                existingCandidates: [],
                originalKeyCount: 3,
                typoCandidates: [makeTypoCandidate(text: "本屋", reading: "ほんや", value: -11.8134)],
                expectedTexts: []),
            TestCase(
                name: "value cutoff removes candidates more than four below best",
                existingCandidates: [
                    makeCandidate(text: "基準", reading: "きじゅ", value: -30.0, composingCount: 3)
                ],
                originalKeyCount: 3,
                typoCandidates: [
                    makeTypoCandidate(text: "最良", reading: "さい", value: -5.0),
                    makeTypoCandidate(text: "境界", reading: "かい", value: -9.0),
                    makeTypoCandidate(text: "圏外", reading: "けん", value: -9.1)
                ],
                expectedTexts: ["最良", "境界"]),
            TestCase(
                name: "result count is capped at three",
                existingCandidates: [
                    makeCandidate(text: "基準", reading: "きじゅ", value: -30.0, composingCount: 3)
                ],
                originalKeyCount: 3,
                typoCandidates: [
                    makeTypoCandidate(text: "第一", reading: "いち", value: -1.0),
                    makeTypoCandidate(text: "第二", reading: "にい", value: -2.0),
                    makeTypoCandidate(text: "第三", reading: "さん", value: -3.0),
                    makeTypoCandidate(text: "第四", reading: "しい", value: -4.0),
                    makeTypoCandidate(text: "第五", reading: "ごお", value: -5.0)
                ],
                expectedTexts: ["第一", "第二", "第三"])
        ]

        for testCase in cases {
            let selected = selectTypoCandidates(
                testCase.typoCandidates,
                existingCandidates: testCase.existingCandidates,
                originalKeyCount: testCase.originalKeyCount
            )
            XCTAssertEqual(selected.map(\.text), testCase.expectedTexts, testCase.name)
        }
    }

    private func makeCandidate(text: String, value: PValue, data: [DicdataElement]) -> Candidate {
        Candidate(text: text, value: value, composingCount: .inputCount(data.reduce(0) { $0 + $1.ruby.count }), lastMid: 0, data: data)
    }

    private func makeCandidate(text: String, reading: String, value: PValue, composingCount: Int) -> Candidate {
        Candidate(
            text: text,
            value: value,
            composingCount: .inputCount(composingCount),
            lastMid: 0,
            data: [makeData(word: text, ruby: reading, value: value)]
        )
    }

    private func makeTypoCandidate(text: String, reading: String, value: PValue) -> TypoCandidate {
        TypoCandidate(text: text, value: value, correspondingCount: reading.count, correctedReading: reading)
    }

    private func makeData(word: String, ruby: String, value: PValue, cid: Int = 0) -> DicdataElement {
        DicdataElement(word: word, ruby: ruby, cid: cid, mid: 0, value: value)
    }
}
