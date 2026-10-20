import XCTest
@testable import OpenTimeUI

final class WorkHoursPayloadTests: XCTestCase {

    func testRoundTrip() {
        let context = WorkHoursPayload.encode(start: 7, end: 19)
        let r = WorkHoursPayload.decode(context)
        XCTAssertEqual(r.start, 7)
        XCTAssertEqual(r.end, 19)
    }

    func testEmptyContextDecodesToDefault() {
        let r = WorkHoursPayload.decode([:])
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testMalformedContextDecodesToDefault() {
        let r = WorkHoursPayload.decode(["workStartHour": "seven", "workEndHour": 19])
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testInvalidPairDecodesToDefault() {
        let r = WorkHoursPayload.decode(["workStartHour": 19, "workEndHour": 7])
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testEncodeSanitizesBeforeSending() {
        // Never put a window on the wire that the receiver would reject.
        let context = WorkHoursPayload.encode(start: 30, end: 4)
        XCTAssertEqual(context["workStartHour"] as? Int, 9)
        XCTAssertEqual(context["workEndHour"] as? Int, 17)
    }

    func testKeysMatchDefaultsKeys() {
        // The watch writes the received values straight into its own
        // UserDefaults under these names, so they must not drift.
        let context = WorkHoursPayload.encode(start: 8, end: 16)
        XCTAssertNotNil(context["workStartHour"])
        XCTAssertNotNil(context["workEndHour"])
        XCTAssertEqual(context.count, 2)
    }
}
