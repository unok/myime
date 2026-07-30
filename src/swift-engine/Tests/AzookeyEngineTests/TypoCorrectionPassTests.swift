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

    private func makeCandidate(text: String, value: PValue, data: [DicdataElement]) -> Candidate {
        Candidate(text: text, value: value, composingCount: .inputCount(data.reduce(0) { $0 + $1.ruby.count }), lastMid: 0, data: data)
    }

    private func makeData(word: String, ruby: String, value: PValue) -> DicdataElement {
        DicdataElement(word: word, ruby: ruby, cid: 0, mid: 0, value: value)
    }
}
