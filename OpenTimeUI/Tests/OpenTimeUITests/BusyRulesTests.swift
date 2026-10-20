import Foundation
import Testing
@testable import OpenTimeUI

@Suite struct BusyRulesTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func declinedAndFreeEventsDoNotBlock() {
        #expect(!BusyRules.blocks(.init(start: at(20, 10), end: at(20, 11), allDay: false, declined: true)))
        #expect(!BusyRules.blocks(.init(start: at(20, 10), end: at(20, 11), allDay: false, availability: .free)))
        #expect(BusyRules.blocks(.init(start: at(20, 10), end: at(20, 11), allDay: false, availability: .tentative)))
    }

    @Test func allDayBlocksOnlyWhenMarkedBusy() {
        let holiday = BusyRules.EventFacts(start: at(20, 0), end: at(21, 0), allDay: true, availability: .free)
        let offsite = BusyRules.EventFacts(start: at(20, 0), end: at(21, 0), allDay: true, availability: .busy)
        #expect(BusyRules.blocking([holiday], on: at(20, 12), calendar: cal).isEmpty)
        let spans = BusyRules.blocking([offsite], on: at(20, 12), calendar: cal)
        #expect(spans.count == 1)
        let free = AvailabilityEngine.freeIntervals(events: spans, on: at(20, 0),
                                                    workStartHour: 9, workEndHour: 17, calendar: cal)
        #expect(free.isEmpty)
    }

    @Test func multiDayEventBlocksEveryDayItTouches() {
        // Tuesday 3pm to Thursday noon.
        let trip = BusyRules.EventFacts(start: at(20, 15), end: at(22, 12), allDay: false)
        let wednesday = BusyRules.blocking([trip], on: at(21, 9), calendar: cal)
        #expect(wednesday.count == 1)
        let wedFree = AvailabilityEngine.freeIntervals(events: wednesday, on: at(21, 0),
                                                       workStartHour: 9, workEndHour: 17, calendar: cal)
        #expect(wedFree.isEmpty)
        let thursday = BusyRules.blocking([trip], on: at(22, 9), calendar: cal)
        let thuFree = AvailabilityEngine.freeIntervals(events: thursday, on: at(22, 0),
                                                       workStartHour: 9, workEndHour: 17, calendar: cal)
        #expect(thuFree == [AvailabilityEngine.Interval(start: at(22, 12), end: at(22, 17))])
        #expect(BusyRules.blocking([trip], on: at(23, 9), calendar: cal).isEmpty)
    }

    @Test func todayStartsAtTheNextQuarterHour() {
        let free = [AvailabilityEngine.Interval(start: at(20, 9), end: at(20, 10)),
                    AvailabilityEngine.Interval(start: at(20, 13), end: at(20, 13, 20)),
                    AvailabilityEngine.Interval(start: at(20, 14), end: at(20, 17))]
        let trimmed = BusyRules.trimPast(free, now: at(20, 13, 7), calendar: cal)
        // The 9-10 slot is gone; 13:15-13:20 is too short; 14-17 is untouched.
        #expect(trimmed == [AvailabilityEngine.Interval(start: at(20, 14), end: at(20, 17))])
        let midSlot = BusyRules.trimPast([AvailabilityEngine.Interval(start: at(20, 14), end: at(20, 17))],
                                         now: at(20, 14, 52), calendar: cal)
        #expect(midSlot == [AvailabilityEngine.Interval(start: at(20, 15), end: at(20, 17))])
    }
}
