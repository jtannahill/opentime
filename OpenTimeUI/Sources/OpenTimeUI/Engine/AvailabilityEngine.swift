import Foundation

public struct TimedEvent: Sendable {
    public let start: Date
    public let end: Date
    public let allDay: Bool

    public init(start: Date, end: Date, allDay: Bool = false) {
        self.start = start
        self.end = end
        self.allDay = allDay
    }
}

public enum AvailabilityEngine {
    public struct Interval: Sendable, Equatable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    public static func mergedBusyIntervals(
        events: [TimedEvent],
        on date: Date,
        workStartHour: Int,
        workEndHour: Int,
        calendar: Calendar = .current
    ) -> [Interval] {
        let ws = calendar.date(bySettingHour: workStartHour, minute: 0, second: 0, of: date)!
        let we = calendar.date(bySettingHour: workEndHour, minute: 0, second: 0, of: date)!

        let busy: [(Date, Date)] = events.compactMap { ev in
            guard !ev.allDay else { return nil }
            let s = max(ev.start, ws)
            let e = min(ev.end, we)
            return s < e ? (s, e) : nil
        }.sorted { $0.0 < $1.0 }

        var merged: [(Date, Date)] = []
        for (s, e) in busy {
            if let last = merged.last, s <= last.1 {
                merged[merged.count - 1] = (last.0, max(last.1, e))
            } else {
                merged.append((s, e))
            }
        }

        return merged.map { Interval(start: $0.0, end: $0.1) }
    }

    public static func freeIntervals(
        events: [TimedEvent],
        on date: Date,
        workStartHour: Int,
        workEndHour: Int,
        calendar: Calendar = .current
    ) -> [Interval] {
        let ws = calendar.date(bySettingHour: workStartHour, minute: 0, second: 0, of: date)!
        let we = calendar.date(bySettingHour: workEndHour, minute: 0, second: 0, of: date)!
        let merged = mergedBusyIntervals(
            events: events,
            on: date,
            workStartHour: workStartHour,
            workEndHour: workEndHour,
            calendar: calendar
        )

        var free: [Interval] = []
        var cursor = ws
        for interval in merged {
            if cursor < interval.start {
                free.append(Interval(start: cursor, end: interval.start))
            }
            cursor = max(cursor, interval.end)
        }
        if cursor < we {
            free.append(Interval(start: cursor, end: we))
        }
        return free
    }

    /// Monday through Sunday of the calendar week containing `date`.
    public static func currentWeekBounds(
        containing date: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today)
        let monday = calendar.date(byAdding: .day, value: weekday == 1 ? -6 : 2 - weekday, to: today)!
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
        return (monday, sunday)
    }
}
