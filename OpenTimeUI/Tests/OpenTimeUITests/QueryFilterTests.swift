import Testing
import Foundation
@testable import OpenTimeUI

@Suite struct QueryFilterTests {

    static let cal = Calendar.current

    static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return cal.date(from: c)!
    }

    static func day(_ y: Int, _ m: Int, _ d: Int, _ slots: [(Int, Int, Int, Int)]) -> DayAvailability {
        let date = at(y, m, d, 0)
        let free = slots.map { FreeSlot(start: at(y, m, d, $0.0, $0.1), end: at(y, m, d, $0.2, $0.3)) }
        return DayAvailability(date: date, freeSlots: free, busySlots: [])
    }

    // 9–17 free, single slot
    static func fullDay(_ y: Int, _ m: Int, _ d: Int) -> DayAvailability {
        day(y, m, d, [(9, 0, 17, 0)])
    }

    @Test("empty intent returns input unchanged")
    func emptyIntent() {
        let days = [Self.fullDay(2026, 5, 12), Self.fullDay(2026, 5, 13)]
        let result = QueryFilter.filter(days: days, intent: AvailabilityIntent(), now: Self.at(2026, 5, 11, 0))
        #expect(result.count == 2)
    }

    @Test("date range single day matches only that day")
    func dateRangeSingle() {
        let days = [Self.fullDay(2026, 5, 12), Self.fullDay(2026, 5, 13)]
        var intent = AvailabilityIntent()
        intent.startDate = "2026-05-12"
        let result = QueryFilter.filter(days: days, intent: intent, now: Self.at(2026, 5, 11, 0))
        #expect(result.count == 1)
        #expect(Self.cal.isDate(result[0].date, inSameDayAs: Self.at(2026, 5, 12, 0)))
    }

    @Test("date range multi-day is inclusive on both ends")
    func dateRangeInclusive() {
        let days = [Self.fullDay(2026, 5, 12), Self.fullDay(2026, 5, 13), Self.fullDay(2026, 5, 14), Self.fullDay(2026, 5, 15)]
        var intent = AvailabilityIntent()
        intent.startDate = "2026-05-13"
        intent.endDate   = "2026-05-14"
        let result = QueryFilter.filter(days: days, intent: intent, now: Self.at(2026, 5, 11, 0))
        #expect(result.count == 2)
    }

    @Test("days outside the date range are dropped")
    func dateRangeDropsOutside() {
        let days = [Self.fullDay(2026, 5, 12)]
        var intent = AvailabilityIntent()
        intent.startDate = "2026-05-20"
        let result = QueryFilter.filter(days: days, intent: intent, now: Self.at(2026, 5, 11, 0))
        #expect(result.isEmpty)
    }

    @Test("time bound intersects slot — slot 11:30-13:30 with bounds 12-17 yields 12:00-13:30")
    func timeBoundIntersects() {
        let d = Self.day(2026, 5, 12, [(11, 30, 13, 30)])
        var intent = AvailabilityIntent()
        intent.startHour = 12
        intent.endHour   = 17
        let result = QueryFilter.filter(days: [d], intent: intent, now: Self.at(2026, 5, 11, 0))
        #expect(result.count == 1)
        let slot = result[0].freeSlots[0]
        #expect(slot.start == Self.at(2026, 5, 12, 12, 0))
        #expect(slot.end   == Self.at(2026, 5, 12, 13, 30))
    }

    @Test("time bound with empty intersection drops the slot")
    func timeBoundEmptyIntersection() {
        let d = Self.day(2026, 5, 12, [(9, 0, 11, 0)])
        var intent = AvailabilityIntent()
        intent.startHour = 14
        intent.endHour   = 17
        let result = QueryFilter.filter(days: [d], intent: intent, now: Self.at(2026, 5, 11, 0))
        #expect(result.isEmpty)
    }

    @Test("duration filter keeps slots equal to or longer than requested")
    func durationFilter() {
        let d = Self.day(2026, 5, 12, [(9, 0, 9, 30), (10, 0, 11, 0), (12, 0, 14, 0)])
        var intent = AvailabilityIntent()
        intent.durationMin = 60
        let result = QueryFilter.filter(days: [d], intent: intent, now: Self.at(2026, 5, 11, 0))
        #expect(result.count == 1)
        #expect(result[0].freeSlots.count == 2)   // 10-11 (60min) and 12-14 (120min)
    }

    @Test("duration filter excludes the exact-equal-minus-one case")
    func durationFilterEdge() {
        let d = Self.day(2026, 5, 12, [(9, 0, 9, 59)])
        var intent = AvailabilityIntent()
        intent.durationMin = 60
        let result = QueryFilter.filter(days: [d], intent: intent, now: Self.at(2026, 5, 11, 0))
        #expect(result.isEmpty)
    }

    @Test("AND composition: date + time + duration all required")
    func andComposition() {
        let days = [
            Self.day(2026, 5, 12, [(9, 0, 17, 0)]),
            Self.day(2026, 5, 13, [(9, 0, 17, 0)]),
        ]
        var intent = AvailabilityIntent()
        intent.startDate   = "2026-05-13"
        intent.startHour   = 14
        intent.durationMin = 60
        let result = QueryFilter.filter(days: days, intent: intent, now: Self.at(2026, 5, 11, 0))
        #expect(result.count == 1)
        #expect(result[0].freeSlots[0].start == Self.at(2026, 5, 13, 14, 0))
    }

    @Test("past slots are always excluded")
    func pastSlotsExcluded() {
        let d = Self.day(2026, 5, 11, [(9, 0, 11, 0), (14, 0, 16, 0)])
        let intent = AvailabilityIntent()
        let result = QueryFilter.filter(days: [d], intent: intent, now: Self.at(2026, 5, 11, 13, 0))
        #expect(result.count == 1)
        #expect(result[0].freeSlots.count == 1)
        #expect(result[0].freeSlots[0].start == Self.at(2026, 5, 11, 14, 0))
    }

    @Test("slot straddling now is clamped to now")
    func straddlingSlotClamped() {
        let d = Self.day(2026, 5, 11, [(9, 0, 17, 0)])
        let now = Self.at(2026, 5, 11, 12, 30)
        let result = QueryFilter.filter(days: [d], intent: AvailabilityIntent(), now: now)
        #expect(result.count == 1)
        #expect(result[0].freeSlots.count == 1)
        #expect(result[0].freeSlots[0].start == now)
        #expect(result[0].freeSlots[0].end == Self.at(2026, 5, 11, 17, 0))
    }
}
