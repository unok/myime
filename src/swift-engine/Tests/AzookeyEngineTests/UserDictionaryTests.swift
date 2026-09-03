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

    func testMissingPosDefaultsToNoun() throws {
        let json = #"[{"reading":"ほん","word":"本"}]"#
        let entries = try decodeDynamicUserDictionary(json)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].word, "本")
        XCTAssertEqual(entries[0].lcid, CIDData.一般名詞.cid)
        XCTAssertEqual(entries[0].mid, MIDData.一般.mid)
    }

    func testMissingReadingDropsOnlyInvalidEntry() throws {
        let json = #"[{"word":"欠落","pos":"noun"},{"reading":"せいじょう","word":"正常","pos":"noun"}]"#
        let entries = try decodeDynamicUserDictionary(json)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].ruby, "セイジョウ")
        XCTAssertEqual(entries[0].word, "正常")
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

    func testMapsIPADICFeaturesToCidsAndFallsBackForUnknownFeature() throws {
        let cases = [
            ("名詞,一般,*,*,*,*", 1285),
            ("名詞,固有名詞,人名,姓,*,*", 1290),
            ("名詞,数,*,*,*,*", 1295),
            ("動詞,自立,*,*,五段・ワ行促音便,連用形", 832),
            ("形容詞,自立,*,*,形容詞・アウオ段,基本形", 19),
            ("助詞,終助詞,*,*,*,*", 279),
            ("未知品詞,未知分類,*,*,*,*", 1285),
        ]

        for (pos, expectedCid) in cases {
            let json = """
                [{"reading":"てすと","word":"試験語","pos":"\(pos)"}]
                """
            let entries = try decodeDynamicUserDictionary(json)
            XCTAssertEqual(entries[0].lcid, expectedCid, "pos: \(pos)")
            XCTAssertEqual(entries[0].rcid, expectedCid, "pos: \(pos)")
        }
    }

    func testAlphabetSymbolFeatureUsesEnglishWordMid() throws {
        let json = #"[{"reading":"えーびーしー","word":"ABC","pos":"記号,アルファベット,*,*,*,*"}]"#
        let entries = try decodeDynamicUserDictionary(json)

        XCTAssertEqual(entries[0].mid, MIDData.英単語.mid)
    }

    func testLegacyFamilyNameCategoryRemainsCompatible() throws {
        let json = #"[{"reading":"うの","word":"宇野","pos":"family_name"}]"#
        let entries = try decodeDynamicUserDictionary(json)

        XCTAssertEqual(entries[0].lcid, 1290)
        XCTAssertEqual(entries[0].rcid, 1290)
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
