import XCTest
@testable import azookey_engine

final class TypoCorrectionReadingGeneratorTests: XCTestCase {
    func testRoundTripReadingsHaveNoFailures() {
        XCTAssertEqual(TypoCorrectionReadingGenerator.testRoundTripFailures().count, 0)
    }

    func testRepresentativeGeneratedCandidates() {
        let cases = [
            ("がこう", "がっこう"),
            ("こにちは", "こんにちは"),
            ("ありがつお", "ありがとう"),
            ("ほにゃ", "ほんや"),
            ("きょうお", "きょうと")
        ]

        for (input, expected) in cases {
            XCTAssertTrue(
                TypoCorrectionReadingGenerator.generateCandidates(for: input).contains(expected),
                "\(input) should include \(expected)"
            )
        }
    }

    func testMultiCharacterKanaReplacementInputsDoNotCrash() {
        XCTAssertNoThrow(TypoCorrectionReadingGenerator.generateCandidates(for: "aたし"))
        XCTAssertNoThrow(TypoCorrectionReadingGenerator.generateCandidates(for: "ｅんぴつ"))
    }

    func testLeftoverAlphabetCandidates() {
        XCTAssertTrue(
            TypoCorrectionReadingGenerator.leftoverAlphabetCandidates(for: "ありがとうございまs").contains("ありがとうございます")
        )
    }
}
