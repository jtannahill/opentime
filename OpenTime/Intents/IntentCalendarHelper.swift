import EventKit
import Foundation
import OpenTimeUI

struct IntentSlot {
    let start: Date
    let end: Date
    var durationMin: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct IntentDay {
    let date: Date
    let freeSlots: [IntentSlot]
    var totalFreeMin: Int { freeSlots.reduce(0) { $0 + $1.durationMin } }
}

final class IntentCalendarHelper: Sendable {
    nonisolated let store = EKEventStore()
    nonisolated private var workStart: Int { WorkHours.current().start }
    nonisolated private var workEnd: Int { WorkHours.current().end }

    nonisolated init() {}

    nonisolated func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    nonisolated func loadDays(for range: AvailabilityRange) -> [IntentDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let (start, end): (Date, Date) = {
            switch range {
            case .today:
                return (today, today)
            case .tomorrow:
                let tmr = cal.date(byAdding: .day, value: 1, to: today)!
                return (tmr, tmr)
            case .thisWeek:
                let (mon, fri) = weekBounds(offset: 0)
                return (mon, fri)
            case .nextWeek:
                let (mon, fri) = weekBounds(offset: 1)
                return (mon, fri)
            case .next14Days:
                let end = cal.date(byAdding: .day, value: 13, to: today)!
                return (today, end)
            }
        }()

        return loadRange(from: start, to: end)
    }

    nonisolated func formatDays(_ days: [IntentDay]) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"

        var lines: [String] = []
        for day in days {
            if day.freeSlots.isEmpty {
                lines.append("\(df.string(from: day.date)): No availability")
            } else {
                let slots = day.freeSlots.map {
                    TimeFormat.timeRange(from: $0.start, to: $0.end)
                }
                lines.append("\(df.string(from: day.date)): \(slots.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    nonisolated private func loadRange(from start: Date, to end: Date) -> [IntentDay] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        let endSearch = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endDay)!
        let predicate = store.predicateForEvents(withStart: startDay, end: endSearch, calendars: CalendarSelection.calendars(for: store))
        let events = store.events(matching: predicate)

        var results: [IntentDay] = []
        var cursor = startDay
        while cursor <= endDay {
            let wd = cal.component(.weekday, from: cursor)
            if wd >= 2 && wd <= 6 {
                results.append(availability(for: cursor, events: BusyRules.blocking(events, on: cursor)))
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return results
    }

    nonisolated private func availability(for date: Date, events timed: [TimedEvent]) -> IntentDay {
        let free = BusyRules.trimPast(AvailabilityEngine.freeIntervals(
            events: timed,
            on: date,
            workStartHour: workStart,
            workEndHour: workEnd
        ), now: Date())
        return IntentDay(
            date: date,
            freeSlots: free.map { IntentSlot(start: $0.start, end: $0.end) }
        )
    }

    nonisolated private func weekBounds(offset: Int) -> (Date, Date) {
        let cal = Calendar.current
        let today = Date()
        let wd = cal.component(.weekday, from: today)
        let toMonday = wd == 1 ? -6 : 2 - wd
        let monday = cal.date(byAdding: .day, value: toMonday + (offset * 7), to: today)!
        let friday = cal.date(byAdding: .day, value: 4, to: monday)!
        return (cal.startOfDay(for: monday), cal.startOfDay(for: friday))
    }
}
