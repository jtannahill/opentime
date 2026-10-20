import Combine
import EventKit
import Foundation

struct WatchFreeSlot: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    var durationMin: Int { Int(end.timeIntervalSince(start) / 60) }

    var timeRange: String {
        start.formatted(date: .omitted, time: .shortened)
            + " - "
            + end.formatted(date: .omitted, time: .shortened)
    }
}

struct WatchDayInfo: Identifiable {
    let id = UUID()
    let date: Date
    let freeSlots: [WatchFreeSlot]
    var totalFreeMin: Int { freeSlots.reduce(0) { $0 + $1.durationMin } }

    var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: date)
    }

    var freeSummary: String {
        let min = totalFreeMin
        if min == 0 { return "0m" }
        if min < 60 { return "\(min)m" }
        let h = min / 60, m = min % 60
        return m > 0 ? "\(h)h\(m)m" : "\(h)h"
    }
}

private struct WatchTimedEvent {
    let start: Date
    let end: Date
    let allDay: Bool
}

private enum WatchAvailabilityEngine {
    struct Interval {
        let start: Date
        let end: Date
    }

    static func freeIntervals(events: [WatchTimedEvent], on date: Date, workStartHour: Int, workEndHour: Int) -> [Interval] {
        let cal = Calendar.current
        let ws = cal.date(bySettingHour: workStartHour, minute: 0, second: 0, of: date)!
        let we = cal.date(bySettingHour: workEndHour, minute: 0, second: 0, of: date)!

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

        var free: [Interval] = []
        var cursor = ws
        for (bs, be) in merged {
            if cursor < bs { free.append(Interval(start: cursor, end: bs)) }
            cursor = max(cursor, be)
        }
        if cursor < we { free.append(Interval(start: cursor, end: we)) }
        return free
    }
}

@MainActor
class WatchCalendarHelper: ObservableObject {
    let store = EKEventStore()
    @Published var accessGranted = false
    @Published var days: [WatchDayInfo] = []

    private var workStart: Int { WatchWorkHours.current().start }
    private var workEnd: Int { WatchWorkHours.current().end }

    private var workHoursObserver: NSObjectProtocol?

    init() {
        workHoursObserver = NotificationCenter.default.addObserver(
            forName: WatchWorkHours.didChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.accessGranted else { return }
                self.loadWeek()
            }
        }
    }

    deinit {
        if let workHoursObserver {
            NotificationCenter.default.removeObserver(workHoursObserver)
        }
    }

    func requestAccess() async {
        do {
            accessGranted = try await store.requestFullAccessToEvents()
            if accessGranted { loadWeek() }
        } catch {
            accessGranted = false
        }
    }

    func loadWeek() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        var weekdays: [Date] = []
        var cursor = today
        while weekdays.count < 5 {
            let wd = cal.component(.weekday, from: cursor)
            if wd >= 2 && wd <= 6 { weekdays.append(cursor) }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }

        guard let first = weekdays.first, let last = weekdays.last else { return }
        let endSearch = cal.date(bySettingHour: 23, minute: 59, second: 59, of: last)!
        let predicate = store.predicateForEvents(withStart: first, end: endSearch, calendars: nil)
        let events = store.events(matching: predicate)

        days = weekdays.map { date in
            let dayEvents = events.filter {
                cal.startOfDay(for: $0.startDate) == date && !$0.isAllDay
            }
            return availability(for: date, events: dayEvents)
        }
    }

    private func availability(for date: Date, events: [EKEvent]) -> WatchDayInfo {
        let timed = events.map { WatchTimedEvent(start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay) }
        let free = WatchAvailabilityEngine.freeIntervals(
            events: timed,
            on: date,
            workStartHour: workStart,
            workEndHour: workEnd
        )
        return WatchDayInfo(
            date: date,
            freeSlots: free.map { WatchFreeSlot(start: $0.start, end: $0.end) }
        )
    }
}
