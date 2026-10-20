import XCTest
@testable import OpenTimeUI

final class WorkHoursTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "work-hours-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: - Pure sanitizing core

    func testValidPairPassesThrough() {
        let r = WorkHours.sanitize(start: 7, end: 19)
        XCTAssertEqual(r.start, 7)
        XCTAssertEqual(r.end, 19)
    }

    func testMissingValuesUseDefault() {
        let r = WorkHours.sanitize(start: nil, end: nil)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testPartiallyMissingUsesDefault() {
        // A half-written pair is not a window; fall back rather than guess.
        let r = WorkHours.sanitize(start: 7, end: nil)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testInvertedRangeUsesDefault() {
        let r = WorkHours.sanitize(start: 19, end: 7)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testEqualBoundsUseDefault() {
        // A zero-width window would make every day look fully busy.
        let r = WorkHours.sanitize(start: 12, end: 12)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testOutOfRangeValuesUseDefault() {
        let low = WorkHours.sanitize(start: -3, end: 17)
        XCTAssertEqual(low.start, 9)
        XCTAssertEqual(low.end, 17)

        let high = WorkHours.sanitize(start: 9, end: 24)
        XCTAssertEqual(high.start, 9)
        XCTAssertEqual(high.end, 17)
    }

    func testFullRangeBoundsAreAllowed() {
        let r = WorkHours.sanitize(start: 0, end: 23)
        XCTAssertEqual(r.start, 0)
        XCTAssertEqual(r.end, 23)
    }

    // MARK: - Persistence

    func testEmptyDefaultsReadAsDefaultWindow() {
        let r = WorkHours.current(defaults: defaults)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testRoundTrip() {
        WorkHours.set(start: 6, end: 14, defaults: defaults)
        let r = WorkHours.current(defaults: defaults)
        XCTAssertEqual(r.start, 6)
        XCTAssertEqual(r.end, 14)
    }

    func testSetRejectsInvalidPairAndStoresDefault() {
        WorkHours.set(start: 20, end: 4, defaults: defaults)
        let r = WorkHours.current(defaults: defaults)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }

    func testCorruptStoredValuesReadAsDefault() {
        defaults.set(30, forKey: "workStartHour")
        defaults.set(31, forKey: "workEndHour")
        let r = WorkHours.current(defaults: defaults)
        XCTAssertEqual(r.start, 9)
        XCTAssertEqual(r.end, 17)
    }
}
