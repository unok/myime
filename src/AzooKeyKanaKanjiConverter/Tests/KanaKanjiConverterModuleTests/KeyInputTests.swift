@testable import KanaKanjiConverterModule
import XCTest

final class KeyInputTests: XCTestCase {
    func testKeySpecificRuleBeatsCharacterRule() throws {
        // {shift 0} と 0 の両方がある場合、.key の完全一致を優先
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom_key_priority.tsv")
        let lines = [
            "{shift 0}\tあ",
            "0\tい"
        ].joined(separator: "\n")
        try lines.write(to: url, atomically: true, encoding: .utf8)

        let table = InputStyleManager.shared.table(for: .custom(url))

        XCTAssertEqual(table.applied(currentText: [], added: .key(intention: "0", modifiers: [.shift])), Array("あ"))
        XCTAssertEqual(table.applied(currentText: [], added: .character("0")), Array("い"))
    }

    func testKeyRuleOnly() throws {
        // {shift 0} のみがある場合、.key は一致、.character は素通り
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom_key_only.tsv")
        try "{shift 0}\tA".write(to: url, atomically: true, encoding: .utf8)

        let table = InputStyleManager.shared.table(for: .custom(url))

        XCTAssertEqual(table.applied(currentText: [], added: .key(intention: "0", modifiers: [.shift])), Array("A"))
        XCTAssertEqual(table.applied(currentText: [], added: .character("0")), Array("0"))
    }

    func testCharacterRuleOnly() throws {
        // 0 のみがある場合、.key も .character も一致
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom_char_only.tsv")
        try "0\tZ".write(to: url, atomically: true, encoding: .utf8)

        let table = InputStyleManager.shared.table(for: .custom(url))

        XCTAssertEqual(table.applied(currentText: [], added: .key(intention: "0", modifiers: [.shift])), Array("Z"))
        XCTAssertEqual(table.applied(currentText: [], added: .character("0")), Array("Z"))
    }

    func testShiftUnderscorePriority() throws {
        // {shift _} と _ の両方がある場合の優先
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom_shift_underscore.tsv")
        let lines = [
            "{shift _}\tX",
            "_\tY"
        ].joined(separator: "\n")
        try lines.write(to: url, atomically: true, encoding: .utf8)

        let table = InputStyleManager.shared.table(for: .custom(url))

        XCTAssertEqual(table.applied(currentText: [], added: .key(intention: "_", modifiers: [.shift])), Array("X"))
        XCTAssertEqual(table.applied(currentText: [], added: .character("_")), Array("Y"))
    }

    func testAnyCharacterCapturesKeyIntention() throws {
        // {any character} は .key(intention: c) にも一致し、c を代入できる
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom_any1_with_key.tsv")
        let lines = [
            "n{any character}\tん{any character}"
        ].joined(separator: "\n")
        try lines.write(to: url, atomically: true, encoding: .utf8)

        let table = InputStyleManager.shared.table(for: .custom(url))

        XCTAssertEqual(table.applied(currentText: ["n"], added: .key(intention: "a", modifiers: [.shift])), Array("んa"))
    }

    func testKeyAtTailMatches() throws {
        // 末尾に {shift 0} がある規則
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom_tail_shift0.tsv")
        try "k{shift 0}\tか".write(to: url, atomically: true, encoding: .utf8)

        let table = InputStyleManager.shared.table(for: .custom(url))

        // buffer に 'k' があり、追加入力が .key(intention: "0", [.shift]) の場合に一致
        XCTAssertEqual(table.applied(currentText: ["k"], added: .key(intention: "0", modifiers: [.shift])), Array("か"))

        // 単なる文字 '0' では一致せず、素通り
        XCTAssertEqual(table.applied(currentText: ["k"], added: .character("0")), Array("k0"))
    }

    func testKeyAtTailPriorityOverCharacter() throws {
        // k{shift 0} と k0 の両方があり、.key を優先
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom_tail_priority.tsv")
        let lines = [
            "k{shift 0}\tか",
            "k0\tこ"
        ].joined(separator: "\n")
        try lines.write(to: url, atomically: true, encoding: .utf8)

        let table = InputStyleManager.shared.table(for: .custom(url))

        // .key は k{shift 0} に一致
        XCTAssertEqual(table.applied(currentText: ["k"], added: .key(intention: "0", modifiers: [.shift])), Array("か"))
        // 文字 '0' は k0 に一致
        XCTAssertEqual(table.applied(currentText: ["k"], added: .character("0")), Array("こ"))
    }

    func testComposingTextWithKey() throws {
        // ComposingText 上でも .key 入力が適用されること
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom_composing_key.tsv")
        let lines = [
            "{shift 0}\tが",
            "0\tお"
        ].joined(separator: "\n")
        try lines.write(to: url, atomically: true, encoding: .utf8)

        var c = ComposingText()
        // カスタムテーブルに対して .key を1要素入力
        c.insertAtCursorPosition([
            .init(piece: .key(intention: "0", modifiers: [.shift]), inputStyle: .mapped(id: .custom(url)))
        ])
        XCTAssertEqual(c.convertTarget, "が")

        // 文字としての "0" は文字変換側に一致
        c.insertAtCursorPosition("0", inputStyle: .mapped(id: .custom(url)))
        XCTAssertEqual(c.convertTarget, "がお")
    }
}
