import Testing
import Foundation
@testable import OpenTimeUI

@Suite struct QuerySuggestTests {

    static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        QueryFilterTests.at(y, m, d, h, min)
    }
    static func day(_ y: Int, _ m: Int, _ d: Int, _ slots: [(Int, Int, Int, Int)]) -> DayAvailability {
        QueryFilterTests.day(y, m, d, slots)
    }

    @Test("relaxes timeOfDay first — keeps date, returns earliest slot on requested day")
    func relaxesTimeFirst() {
        // Tuesday May 12 free 9–11, but the user asked for 'afternoon, 1hr'.
        let d = Self.day(2026, 5, 12, [(9, 0, 11, 0)])
        var intent = AvailabilityIntent()
        intent.startDate   = "2026-05-12"
        intent.startHour   = 14
        intent.endHour     = 17
        intent.durationMin = 60
        let s = QuerySuggest.closest(days: [d], intent: intent, now: Self.at(2026, 5, 11, 12))
        #expect(s != nil)
        #expect(s?.relaxedFields == [.timeOfDay])
        #expect(s?.slot.start == Self.at(2026, 5, 12, 9, 0))
    }

    @Test("relaxes duration when time bound is real but block is too short")
    func relaxesDuration() {
        // Tuesday afternoon free 14:00-14:30, asked for 60min afternoon.
        let d = Self.day(2026, 5, 12, [(14, 0, 14, 30)])
        var intent = AvailabilityIntent()
        intent.startDate   = "2026-05-12"
        intent.startHour   = 14
        intent.endHour     = 17
        intent.durationMin = 60
        let s = QuerySuggest.closest(days: [d], intent: intent, now: Self.at(2026, 5, 11, 12))
        #expect(s != nil)
        #expect(s?.relaxedFields == [.duration])
        #expect(s?.slot.start == Self.at(2026, 5, 12, 14, 0))
    }

    @Test("relaxes date last — searches forward, never backward")
    func relaxesDate() {
        // Tue 5/12 has no slots at all; Wed 5/13 has 14-16 afternoon.
        // Need time-relax to fail (Tue empty so duration-only also fails)
        // and duration-relax to fail (Tue empty), forcing date-relax to win.
        let days = [
            Self.day(2026, 5, 12, []),
            Self.day(2026, 5, 13, [(14, 0, 16, 0)]),
        ]
        var intent = AvailabilityIntent()
        intent.startDate   = "2026-05-12"
        intent.startHour   = 14
        intent.endHour     = 17
        intent.durationMin = 120
        let s = QuerySuggest.closest(days: days, intent: intent, now: Self.at(2026, 5, 11, 12))
        #expect(s != nil)
        #expect(s?.relaxedFields == [.date])
        #expect(s?.slot.start == Self.at(2026, 5, 13, 14, 0))
    }

    @Test("never returns a slot before the requested date")
    func neverBeforeDate() {
        // Mon May 11 has 14:00-16:00 free. User asks for Tuesday 5/12 afternoon 60min.
        // Mon would satisfy time+duration but is BEFORE the requested date — must be skipped.
        let days = [
            Self.day(2026, 5, 11, [(14, 0, 16, 0)]),
            Self.day(2026, 5, 13, [(14, 0, 16, 0)]),
        ]
        var intent = AvailabilityIntent()
        intent.startDate   = "2026-05-12"
        intent.startHour   = 14
        intent.endHour     = 17
        intent.durationMin = 60
        let s = QuerySuggest.closest(days: days, intent: intent, now: Self.at(2026, 5, 11, 9))
        #expect(s != nil)
        #expect(s?.slot.start == Self.at(2026, 5, 13, 14, 0))
    }

    @Test("returns nil when nothing loosely fits")
    func nilWhenNothingFits() {
        let days = [Self.day(2026, 5, 12, [])]
        var intent = AvailabilityIntent()
        intent.startDate = "2026-05-12"
        let s = QuerySuggest.closest(days: days, intent: intent, now: Self.at(2026, 5, 11, 12))
        #expect(s == nil)
    }
}
