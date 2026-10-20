import XCTest
@testable import OpenTimeUI

final class CalendarSelectionTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "calendar-selection-tests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    // MARK: - Pure filtering core

    func testNoExclusionsMeansNil() {
        XCTAssertNil(CalendarSelection.includedIDs(all: ["a", "b"], excluded: []))
    }

    func testExclusionFilters() {
        XCTAssertEqual(CalendarSelection.includedIDs(all: ["a", "b", "c"], excluded: ["b"]), ["a", "c"])
    }

    func testStaleExclusionsOnlyMeansNil() {
        // Excluded IDs that no longer exist should not force a filtered query.
        XCTAssertNil(CalendarSelection.includedIDs(all: ["a", "b"], excluded: ["gone"]))
    }

    func testAllExcludedFallsBackToNil() {
        // An empty calendar list would make every hour look free; query all instead.
        XCTAssertNil(CalendarSelection.includedIDs(all: ["a", "b"], excluded: ["a", "b"]))
    }

    // MARK: - Persistence

    func testRoundTrip() {
        CalendarSelection.setExcludedIDs(["x", "y"], defaults: defaults)
        XCTAssertEqual(CalendarSelection.excludedIDs(defaults: defaults), ["x", "y"])
    }

    func testMissingKeyReadsEmpty() {
        XCTAssertEqual(CalendarSelection.excludedIDs(defaults: defaults), [])
    }

    func testEmptySetRemovesKey() {
        CalendarSelection.setExcludedIDs(["x"], defaults: defaults)
        CalendarSelection.setExcludedIDs([], defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "excludedCalendarIDs"))
    }
}
