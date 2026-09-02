import Foundation
import XCTest
@testable import azookey_engine

final class ZenzaiStatusTests: XCTestCase {
    func testDefaultStatusHasTypedBooleansAndOmitsOptionalReasons() throws {
        let statusPointer = try XCTUnwrap(getZenzaiStatus())
        defer { freeString(statusPointer) }

        let data = Data(String(cString: statusPointer).utf8)
        let status = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(status["enabled"] as? Bool)
        XCTAssertNotNil(status["learningActive"] as? Bool)
        XCTAssertFalse(status.keys.contains("learningDisabledReason"))
        XCTAssertFalse(status.keys.contains("initializeError"))
    }
}
