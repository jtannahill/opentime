import Combine
import EventKit
import Foundation
import OpenTimeUI

@MainActor
class CalendarManager: ObservableObject {
    let store = EKEventStore()

    @Published var accessGranted = false
    @Published var days: [DayAvailability] = []
    @Published var isLoading = false
    @Published var lastRefreshed: Date?
    @Published var includeWeekends = false

    var workStartHour: Int { WorkHours.current().start }
    var workEndHour: Int { WorkHours.current().end }

    private var lastRangeStart: Date?
    private var lastRangeEnd: Date?
    private var storeChangedObserver: NSObjectProtocol?

    init() {
        storeChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    deinit {
        if let storeChangedObserver {
            NotificationCenter.default.removeObserver(storeChangedObserver)
        }
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            accessGranted = granted
            if granted {
                #if DEBUG
                DemoCalendar.seed(store)
                #endif
                loadOpeningRange()
            }
        } catch {
            accessGranted = false
        }
    }

    /// On a weekend this week's workdays are over, so the app opens on the
    /// week ahead instead of an empty list.
    static var opensOnNextWeek: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7
    }

    /// The range the app opens on: this week, or next week at the weekend.
    func loadOpeningRange() {
        guard Self.opensOnNextWeek else { return loadThisWeek() }
        let (monday, _) = AvailabilityEngine.currentWeekBounds()
        let next = Calendar.current.date(byAdding: .day, value: 7, to: monday)!
        loadRange(from: next, to: Calendar.current.date(byAdding: .day, value: 6, to: next)!)
    }

    /// Default view: Monday–Sunday of the current calendar week.
    func loadThisWeek() {
        let (monday, sunday) = AvailabilityEngine.currentWeekBounds()
        loadRange(from: monday, to: sunday)
    }

    /// Kept for menu compatibility; loads the current calendar week.
    func loadTodayAndTomorrow() {
        loadThisWeek()
    }

    func loadRange(from startDate: Date, to endDate: Date) {
        isLoading = true
        lastRangeStart = startDate
        lastRangeEnd = endDate
        days = availabilityForRange(from: startDate, to: endDate)
        lastRefreshed = Date()
        isLoading = false
    }

    /// Re-run the most recent loadRange call. Used by pull-to-refresh.
    func refresh() {
        guard accessGranted else { return }
        if let s = lastRangeStart, let e = lastRangeEnd {
            loadRange(from: s, to: e)
        } else {
            loadThisWeek()
        }
    }

    var loadedRangeEnd: Date? { lastRangeEnd }

    func extendRange(to target: Date) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = lastRangeStart ?? today
        let currentEnd = lastRangeEnd ?? today

        if cal.startOfDay(for: target) <= cal.startOfDay(for: currentEnd) { return }

        loadRange(from: start, to: target)
    }

    // MARK: - Core Logic

    private func fetchEvents(from startDate: Date, to endDate: Date) -> [EKEvent] {
        let cal = Calendar.current
        let end = cal.date(bySettingHour: 23, minute: 59, second: 59, of: endDate)!
        let predicate = store.predicateForEvents(withStart: startDate, end: end, calendars: CalendarSelection.calendars(for: store))
        return store.events(matching: predicate)
    }

    private func displayEvents(_ events: [EKEvent]) -> [CalEvent] {
        events.map { ev in
            CalEvent(
                calendar: ev.calendar.title,
                calendarColor: nil,
                summary: ev.title ?? "(No title)",
                start: ev.startDate,
                end: ev.endDate,
                allDay: ev.isAllDay
            )
        }
    }

    private func computeAvailability(events: [EKEvent], date: Date) -> DayAvailability {
        let free = BusyRules.trimPast(AvailabilityEngine.freeIntervals(
            events: BusyRules.blocking(events, on: date),
            on: date,
            workStartHour: workStartHour,
            workEndHour: workEndHour
        ), now: Date())
        let busyDisplay = displayEvents(events.filter { BusyRules.blocks(.init($0)) })
            .filter { !$0.allDay }
            .map { BusySlot(start: $0.start, end: $0.end, summary: $0.summary, calendar: $0.calendar) }
            .sorted { $0.start < $1.start }

        return DayAvailability(
            date: date,
            freeSlots: free.map { FreeSlot(start: $0.start, end: $0.end) },
            busySlots: busyDisplay
        )
    }

    private func availabilityForRange(from start: Date, to end: Date) -> [DayAvailability] {
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        let events = fetchEvents(from: startDay, to: endDay)

        var results: [DayAvailability] = []
        var current = startDay
        while current <= endDay {
            // Every event that touches the day, including ones that began earlier.
            let next = cal.date(byAdding: .day, value: 1, to: current)!
            let dayEvents = events.filter { $0.startDate < next && $0.endDate > current }
            results.append(computeAvailability(events: dayEvents, date: current))
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return results
    }

    // MARK: - Text Export

    private static let exportTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static let exportDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    /// Saves a confirmed meeting to the default calendar without a sheet,
    /// using the full access the app already has. False if it could not be
    /// saved, so the caller can fall back to the new-event sheet.
    func saveMeeting(title: String, start: Date, end: Date) -> Bool {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = store.defaultCalendarForNewEvents else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent, commit: true)
            refresh()
            return true
        } catch {
            return false
        }
    }

    func availabilityText(for days: [DayAvailability]) -> String {
        var lines = ["Here's my availability:"]
        for day in days {
            let slots = day.freeSlots.map {
                TimeFormat.timeRange(from: $0.start, to: $0.end)
            }
            let slotsText = slots.isEmpty ? "No availability" : slots.joined(separator: ", ")
            lines.append("\(Self.exportDayFmt.string(from: day.date)): \(slotsText)")
        }
        return lines.joined(separator: "\n")
    }
}
