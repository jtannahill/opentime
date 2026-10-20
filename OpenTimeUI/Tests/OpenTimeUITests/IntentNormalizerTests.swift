import XCTest
@testable import OpenTimeUI

/// Deterministic corrections applied on top of the on-device model output.
/// Anchor date for all tests: Wednesday 2026-07-22.
final class IntentNormalizerTests: XCTestCase {

    private var now: Date {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 22; comps.hour = 16
        return Calendar.current.date(from: comps)!
    }

    private func intent(
        startDate: String? = nil,
        endDate: String? = nil,
        startHour: Int? = nil,
        endHour: Int? = nil,
        durationMin: Int? = nil,
        purposeHint: String? = nil
    ) -> AvailabilityIntent {
        var i = AvailabilityIntent()
        i.startDate = startDate
        i.endDate = endDate
        i.startHour = startHour
        i.endHour = endHour
        i.durationMin = durationMin
        i.purposeHint = purposeHint
        return i
    }

    // MARK: - Weekday resolution (the "any hour friday afternoon" bug)

    func testNamedWeekdayFillsMissingDate() {
        let raw = intent(startHour: 14, endHour: 23, durationMin: 0,
                         purposeHint: "any hour friday afternoon")
        let out = raw.normalized(query: "any hour friday afternoon", now: now)
        XCTAssertEqual(out.startDate, "2026-07-24")
        XCTAssertEqual(out.endDate, "2026-07-24")
    }

    func testNamedWeekdayCorrectsWrongDate() {
        // "next tuesday" resolved by the model to Friday Jul 24; must snap to Tue Jul 28.
        let raw = intent(startDate: "2026-07-24", endDate: "2026-07-24", startHour: 14)
        let out = raw.normalized(query: "next tuesday after 2pm", now: now)
        XCTAssertEqual(out.startDate, "2026-07-28")
        XCTAssertEqual(out.endDate, "2026-07-28")
    }

    func testCorrectWeekdayDateUntouched() {
        let raw = intent(startDate: "2026-07-24", endDate: "2026-07-24")
        let out = raw.normalized(query: "friday", now: now)
        XCTAssertEqual(out.startDate, "2026-07-24")
        XCTAssertEqual(out.endDate, "2026-07-24")
    }

    func testWeekdayAbbreviationResolves() {
        let raw = intent()
        let out = raw.normalized(query: "free on fri?", now: now)
        XCTAssertEqual(out.startDate, "2026-07-24")
    }

    func testSameDayWeekdayMeansToday() {
        // Query says "wednesday" and today IS Wednesday.
        let raw = intent()
        let out = raw.normalized(query: "wednesday evening", now: now)
        XCTAssertEqual(out.startDate, "2026-07-22")
    }

    func testNextPrefixOnTodayWeekdayMeansNextWeek() {
        let raw = intent()
        let out = raw.normalized(query: "next wednesday", now: now)
        XCTAssertEqual(out.startDate, "2026-07-29")
    }

    func testTwoWeekdaysNamedLeavesDatesAlone() {
        let raw = intent(startDate: "2026-07-25", endDate: "2026-07-26")
        let out = raw.normalized(query: "saturday or sunday", now: now)
        XCTAssertEqual(out.startDate, "2026-07-25")
        XCTAssertEqual(out.endDate, "2026-07-26")
    }

    func testPluralWeekdayLeavesDatesAlone() {
        let raw = intent(startDate: "2026-07-24", endDate: "2026-07-31")
        let out = raw.normalized(query: "fridays this month", now: now)
        XCTAssertEqual(out.startDate, "2026-07-24")
        XCTAssertEqual(out.endDate, "2026-07-31")
    }

    // MARK: - Today / tomorrow verification

    func testTomorrowCorrected() {
        let raw = intent(startDate: "2026-07-24")
        let out = raw.normalized(query: "tomorrow morning", now: now)
        XCTAssertEqual(out.startDate, "2026-07-23")
        XCTAssertEqual(out.endDate, "2026-07-23")
    }

    func testTodayFilledWhenMissing() {
        let raw = intent()
        let out = raw.normalized(query: "today after 5", now: now)
        XCTAssertEqual(out.startDate, "2026-07-22")
    }

    // MARK: - Day-part hour clamping

    func testAfternoonClampsHallucinatedHours() {
        // Model said 14–23 for "afternoon"; canonical window is 12–17.
        let raw = intent(startHour: 14, endHour: 23)
        let out = raw.normalized(query: "any hour friday afternoon", now: now)
        XCTAssertEqual(out.startHour, 12)
        XCTAssertEqual(out.endHour, 17)
    }

    func testDayPartWithExplicitTimeLeavesHoursAlone() {
        // Digits present -> the user gave explicit times; don't clamp.
        let raw = intent(startHour: 15, endHour: 17)
        let out = raw.normalized(query: "friday afternoon after 3pm", now: now)
        XCTAssertEqual(out.startHour, 15)
        XCTAssertEqual(out.endHour, 17)
    }

    func testNoDayPartLeavesHoursAlone() {
        let raw = intent(startHour: 14, endHour: 22)
        let out = raw.normalized(query: "next tuesday after 2pm", now: now)
        XCTAssertEqual(out.startHour, 14)
        XCTAssertEqual(out.endHour, 22)
    }

    // MARK: - Field hygiene

    func testZeroDurationDropped() {
        let raw = intent(durationMin: 0)
        let out = raw.normalized(query: "any hour friday afternoon", now: now)
        XCTAssertNil(out.durationMin)
    }

    func testRealDurationKept() {
        let raw = intent(durationMin: 30)
        let out = raw.normalized(query: "30 min friday", now: now)
        XCTAssertEqual(out.durationMin, 30)
    }

    func testEchoedPurposeHintDropped() {
        let raw = intent(purposeHint: "Any hour Friday afternoon")
        let out = raw.normalized(query: "any hour friday afternoon", now: now)
        XCTAssertNil(out.purposeHint)
    }

    func testRealPurposeHintKept() {
        let raw = intent(purposeHint: "coffee")
        let out = raw.normalized(query: "coffee friday afternoon", now: now)
        XCTAssertEqual(out.purposeHint, "coffee")
    }

    // MARK: - No-op safety

    func testQueryWithoutDateWordsIsUntouched() {
        let raw = intent(startDate: "2026-08-01", endDate: "2026-08-02",
                         startHour: 9, endHour: 12, durationMin: 60, purposeHint: "call")
        let out = raw.normalized(query: "an hour for a call early in august", now: now)
        XCTAssertEqual(out.startDate, "2026-08-01")
        XCTAssertEqual(out.endDate, "2026-08-02")
        XCTAssertEqual(out.startHour, 9)
        XCTAssertEqual(out.endHour, 12)
        XCTAssertEqual(out.durationMin, 60)
        XCTAssertEqual(out.purposeHint, "call")
    }
}
