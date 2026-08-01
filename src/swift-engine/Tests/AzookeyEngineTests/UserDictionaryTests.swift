import XCTest
import KanaKanjiConverterModuleWithDefaultDictionary
@testable import azookey_engine

final class UserDictionaryTests: XCTestCase {
    func testDecodesEntriesAndMapsNamePos() throws {
        let json = #"[{"reading":"うのけ","word":"宇野家","pos":"personal_name"}]"#
        let entries = try decodeDynamicUserDictionary(json)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].ruby, "ウノケ")
        XCTAssertEqual(entries[0].word, "宇野家")
        XCTAssertEqual(entries[0].lcid, CIDData.人名一般.cid)
        XCTAssertEqual(entries[0].rcid, CIDData.人名一般.cid)
        XCTAssertEqual(entries[0].mid, MIDData.一般.mid)
        XCTAssertEqual(entries[0].value(), -5)
    }

    func testUnknownPosFallsBackToGeneralNoun() throws {
        let json = #"[{"reading":"みち","word":"未知","pos":"future_pos"}]"#
        let entries = try decodeDynamicUserDictionary(json)

        XCTAssertEqual(entries[0].lcid, CIDData.一般名詞.cid)
        XCTAssertEqual(entries[0].mid, MIDData.一般.mid)
    }

    func testMapsStandaloneWordCategoriesToIPADICCids() throws {
        let json = #"""
        [
            {"reading":"けんさく","word":"検索","pos":"sahen_noun"},
            {"reading":"かわいい","word":"可愛い","pos":"adjective"},
            {"reading":"すぐ","word":"直ぐ","pos":"adverb"},
            {"reading":"わあ","word":"わあ","pos":"interjection"}
        ]
        """#
        let entries = try decodeDynamicUserDictionary(json)

        XCTAssertEqual(entries.map { $0.lcid }, [1283, 19, 1281, 3])
    }

    func testEmptyFieldsAreDroppedAndEmptyArrayClearsDictionary() throws {
        XCTAssertTrue(try decodeDynamicUserDictionary("[]").isEmpty)
        let json = #"[{"reading":"","word":"空","pos":"noun"}]"#
        XCTAssertTrue(try decodeDynamicUserDictionary(json).isEmpty)
    }

    func testMalformedJsonIsRejected() {
        XCTAssertThrowsError(try decodeDynamicUserDictionary("not-json"))
    }
}
