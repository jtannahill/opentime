import Foundation
import Testing
@testable import OpenTimeUI

@Test func freeIntervalsWithNoEvents() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 0))!

    let free = AvailabilityEngine.freeIntervals(
        events: [],
        on: day,
        workStartHour: 9,
        workEndHour: 17,
        calendar: cal
    )
    #expect(free.count == 1)
    #expect(cal.component(.hour, from: free[0].start) == 9)
    #expect(cal.component(.hour, from: free[0].end) == 17)
}

@Test func mergedBusyIntervalsCombineOverlap() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "America/New_York")!
    let day = cal.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 0))!
    let events = [
        TimedEvent(
            start: cal.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 10))!,
            end: cal.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 11))!
        ),
        TimedEvent(
            start: cal.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 10, minute: 30))!,
            end: cal.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 12))!
        ),
    ]

    let merged = AvailabilityEngine.mergedBusyIntervals(
        events: events,
        on: day,
        workStartHour: 9,
        workEndHour: 17,
        calendar: cal
    )
    #expect(merged.count == 1)
    #expect(cal.component(.hour, from: merged[0].start) == 10)
    #expect(cal.component(.hour, from: merged[0].end) == 12)
}

@Test func nonDefaultWindowIsHonored() {
    // Proves the engine actually uses the passed window rather than
    // silently applying its 9-17 defaults.
    let cal = Calendar.current
    let day = cal.startOfDay(for: Date())
    let free = AvailabilityEngine.freeIntervals(
        events: [],
        on: day,
        workStartHour: 7,
        workEndHour: 19,
        calendar: cal
    )
    #expect(free.count == 1)
    #expect(cal.component(.hour, from: free[0].start) == 7)
    #expect(cal.component(.hour, from: free[0].end) == 19)
}
