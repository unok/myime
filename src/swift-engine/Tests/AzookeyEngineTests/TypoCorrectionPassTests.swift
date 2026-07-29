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

    private func makeData(word: String, ruby: String, value: PValue) -> DicdataElement {
        DicdataElement(word: word, ruby: ruby, cid: 0, mid: 0, value: value)
    }
}
