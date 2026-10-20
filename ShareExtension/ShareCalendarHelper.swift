import Combine
import EventKit
import Foundation
import OpenTimeUI

struct ShareFreeSlot: Identifiable, Equatable {
    let id = UUID()
    let start: Date
    let end: Date
    var durationMin: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct ShareDayInfo: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let freeSlots: [ShareFreeSlot]
    var totalFreeMin: Int { freeSlots.reduce(0) { $0 + $1.durationMin } }

    var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    var freeSummary: String {
        let min = totalFreeMin
        if min == 0 { return "0m" }
        if min < 60 { return "\(min)m free" }
        let h = min / 60, m = min % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    var slotsDescription: String {
        if freeSlots.isEmpty { return "No availability" }
        return freeSlots.map {
            TimeFormat.timeRange(from: $0.start, to: $0.end)
        }.joined(separator: ", ")
    }
}

@MainActor
class ShareCalendarHelper: ObservableObject {
    let store = EKEventStore()
    @Published var accessGranted = false
    @Published var days: [ShareDayInfo] = []

    private var workStart: Int { WorkHours.current().start }
    private var workEnd: Int { WorkHours.current().end }

    func requestAccess() async {
        do {
            accessGranted = try await store.requestFullAccessToEvents()
            if accessGranted { loadThisWeek() }
        } catch {
            accessGranted = false
        }
    }

    func loadThisWeek() {
        let (mon, fri) = weekBounds(offset: 0)
        loadRange(from: mon, to: fri)
    }

    func loadNextWeek() {
        let (mon, fri) = weekBounds(offset: 1)
        loadRange(from: mon, to: fri)
    }

    func loadNext14Days() {
        let today = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 13, to: today)!
        loadRange(from: today, to: end)
    }

    func loadRange(from start: Date, to end: Date) {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        let endSearch = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endDay)!
        let predicate = store.predicateForEvents(withStart: startDay, end: endSearch, calendars: CalendarSelection.calendars(for: store))
        let events = store.events(matching: predicate)

        var results: [ShareDayInfo] = []
        var cursor = startDay
        while cursor <= endDay {
            let wd = cal.component(.weekday, from: cursor)
            if wd >= 2 && wd <= 6 {
                results.append(availability(for: cursor, events: BusyRules.blocking(events, on: cursor)))
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        days = results
    }

    private func availability(for date: Date, events timed: [TimedEvent]) -> ShareDayInfo {
        let free = BusyRules.trimPast(AvailabilityEngine.freeIntervals(
            events: timed,
            on: date,
            workStartHour: workStart,
            workEndHour: workEnd
        ), now: Date())
        return ShareDayInfo(
            date: date,
            freeSlots: free.map { ShareFreeSlot(start: $0.start, end: $0.end) }
        )
    }

    private func weekBounds(offset: Int) -> (Date, Date) {
        let cal = Calendar.current
        let today = Date()
        let wd = cal.component(.weekday, from: today)
        let toMonday = wd == 1 ? -6 : 2 - wd
        let monday = cal.date(byAdding: .day, value: toMonday + (offset * 7), to: today)!
        let friday = cal.date(byAdding: .day, value: 4, to: monday)!
        return (cal.startOfDay(for: monday), cal.startOfDay(for: friday))
    }

    func formatSelected(_ selectedIDs: Set<UUID>) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMM d"

        let selected = days.filter { selectedIDs.contains($0.id) }
        if selected.isEmpty { return "" }

        var lines = ["Here's my availability:"]
        for day in selected {
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
}
