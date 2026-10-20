import Testing
import Foundation
@testable import OpenTimeUI

@Suite struct AvailabilityIntentTests {

    /// Build a Date for a fixed (y, m, d) at local noon to dodge DST edges.
    static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    @Test("requestedRange is nil when no date fields set")
    func requestedRangeNilWithoutDate() {
        var intent = AvailabilityIntent()
        intent.durationMin = 30
        intent.startHour = 14
        #expect(intent.requestedRange(now: Self.date(2026, 5, 11)) == nil)
    }

    @Test("requestedRange spans startDate..endDate inclusive")
    func requestedRangeSpansDates() {
        var intent = AvailabilityIntent()
        intent.startDate = "2026-05-12"
        intent.endDate   = "2026-05-14"
        let r = intent.requestedRange(now: Self.date(2026, 5, 11))!
        #expect(Calendar.current.isDate(r.start, inSameDayAs: Self.date(2026, 5, 12)))
        #expect(Calendar.current.isDate(r.end,   inSameDayAs: Self.date(2026, 5, 14)))
    }

    @Test("requestedRange with only startDate produces a single-day range")
    func requestedRangeSingleDay() {
        var intent = AvailabilityIntent()
        intent.startDate = "2026-05-12"
        let r = intent.requestedRange(now: Self.date(2026, 5, 11))!
        #expect(Calendar.current.isDate(r.start, inSameDayAs: r.end))
    }

    @Test("summary renders TODAY label")
    func summaryToday() {
        var intent = AvailabilityIntent()
        intent.startDate = "2026-05-11"
        let s = intent.summary(now: Self.date(2026, 5, 11))
        #expect(s.contains("TODAY"))
    }

    @Test("summary renders TOMORROW label")
    func summaryTomorrow() {
        var intent = AvailabilityIntent()
        intent.startDate = "2026-05-12"
        let s = intent.summary(now: Self.date(2026, 5, 11))
        #expect(s.contains("TOMORROW"))
    }

    @Test("summary renders weekday for further-out dates")
    func summaryWeekday() {
        var intent = AvailabilityIntent()
        intent.startDate = "2026-05-20"   // Wednesday
        let s = intent.summary(now: Self.date(2026, 5, 11))
        #expect(s.uppercased().contains("WED"))
    }

    @Test("summary includes AFTER 2PM for startHour-only time bound")
    func summaryAfterHour() {
        var intent = AvailabilityIntent()
        intent.startHour = 14
        let s = intent.summary(now: Self.date(2026, 5, 11))
        #expect(s.contains("AFTER 2PM"))
    }

    @Test("summary includes BEFORE 12PM for endHour-only time bound")
    func summaryBeforeHour() {
        var intent = AvailabilityIntent()
        intent.endHour = 12
        let s = intent.summary(now: Self.date(2026, 5, 11))
        #expect(s.contains("BEFORE 12PM"))
    }

    @Test("summary omits time-bound segment when endHour is 24 (end of day)")
    func summaryOmitsEndOfDay() {
        var intent = AvailabilityIntent()
        intent.endHour = 24
        let s = intent.summary(now: Self.date(2026, 5, 11))
        #expect(!s.contains("BEFORE"))
        #expect(!s.contains("12AM"))
    }

    @Test("summary includes duration in MIN")
    func summaryDuration() {
        var intent = AvailabilityIntent()
        intent.durationMin = 60
        let s = intent.summary(now: Self.date(2026, 5, 11))
        #expect(s.contains("60 MIN"))
    }

    @Test("summary includes purposeHint when present")
    func summaryPurpose() {
        var intent = AvailabilityIntent()
        intent.durationMin = 30
        intent.purposeHint = "coffee"
        let s = intent.summary(now: Self.date(2026, 5, 11))
        #expect(s.uppercased().contains("COFFEE"))
    }
}
