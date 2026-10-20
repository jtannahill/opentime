import WidgetKit
import SwiftUI
import EventKit
import AppIntents
import OpenTimeUI

// MARK: - Widget data model

struct WidgetSlot {
    let start: Date
    let end: Date
    var durationMin: Int { Int(end.timeIntervalSince(start) / 60) }
}

struct WidgetDay {
    let label: String
    let date: Date
    let freeSlots: [WidgetSlot]
    var totalFreeMin: Int { freeSlots.reduce(0) { $0 + $1.durationMin } }
}

private func calendarAccessGranted() -> Bool {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .fullAccess, .authorized:
        return true
    default:
        return false
    }
}

func fetchWidgetAvailability(range: WidgetRange = .todayTomorrow) -> (days: [WidgetDay], needsCalendarAccess: Bool) {
    guard calendarAccessGranted() else {
        return ([], true)
    }

    let store = EKEventStore()
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())

    let dates: [(String, Date)]

    switch range {
    case .todayTomorrow:
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        dates = [("Today", today), ("Tomorrow", tomorrow)]
    case .thisWeek:
        let wd = cal.component(.weekday, from: today)
        let toMonday = wd == 1 ? -6 : 2 - wd
        let monday = cal.date(byAdding: .day, value: toMonday, to: today)!
        dates = (0..<5).map { offset in
            let d = cal.date(byAdding: .day, value: offset, to: monday)!
            return (widgetDayLabel(d, today: today), d)
        }
    case .nextWeek:
        let wd = cal.component(.weekday, from: today)
        let toMonday = wd == 1 ? 1 : 9 - wd
        let monday = cal.date(byAdding: .day, value: toMonday, to: today)!
        dates = (0..<5).map { offset in
            let d = cal.date(byAdding: .day, value: offset, to: monday)!
            return (widgetDayLabel(d, today: today), d)
        }
    }

    let hours = WorkHours.current()
    let days = dates.map { label, date in
        let dayEnd = cal.date(bySettingHour: 23, minute: 59, second: 59, of: date)!
        let predicate = store.predicateForEvents(withStart: date, end: dayEnd, calendars: CalendarSelection.calendars(for: store))
        let events = BusyRules.blocking(store.events(matching: predicate), on: date)
        let free = BusyRules.trimPast(AvailabilityEngine.freeIntervals(
            events: events,
            on: date,
            workStartHour: hours.start,
            workEndHour: hours.end
        ), now: Date())
        return WidgetDay(
            label: label,
            date: date,
            freeSlots: free.map { WidgetSlot(start: $0.start, end: $0.end) }
        )
    }
    return (days, false)
}

private func widgetDayLabel(_ date: Date, today: Date) -> String {
    let cal = Calendar.current
    if cal.isDate(date, inSameDayAs: today) { return "Today" }
    if cal.isDate(date, inSameDayAs: cal.date(byAdding: .day, value: 1, to: today)!) { return "Tomorrow" }
    let f = DateFormatter(); f.dateFormat = "EEE"
    return f.string(from: date)
}

// MARK: - Timeline

struct AvailabilityEntry: TimelineEntry {
    let date: Date
    let days: [WidgetDay]
    let needsCalendarAccess: Bool
}

struct AvailabilityProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AvailabilityEntry {
        AvailabilityEntry(date: Date(), days: [
            WidgetDay(label: "Today", date: Date(), freeSlots: [
                WidgetSlot(start: Date(), end: Date().addingTimeInterval(3600))
            ]),
            WidgetDay(label: "Tomorrow", date: Date().addingTimeInterval(86400), freeSlots: [
                WidgetSlot(start: Date(), end: Date().addingTimeInterval(7200))
            ]),
        ], needsCalendarAccess: false)
    }

    func snapshot(for configuration: WidgetConfigIntent, in context: Context) async -> AvailabilityEntry {
        let result = fetchWidgetAvailability(range: configuration.range)
        return AvailabilityEntry(date: Date(), days: result.days, needsCalendarAccess: result.needsCalendarAccess)
    }

    func timeline(for configuration: WidgetConfigIntent, in context: Context) async -> Timeline<AvailabilityEntry> {
        let result = fetchWidgetAvailability(range: configuration.range)
        let entry = AvailabilityEntry(date: Date(), days: result.days, needsCalendarAccess: result.needsCalendarAccess)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - Formatters

private enum WidgetFmt {
    static let dateMeta: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f
    }()

    static func chipTime(_ date: Date) -> String {
        TimeFormat.time(date)
    }

    static func duration(_ min: Int) -> String {
        if min < 60 { return "\(min)m" }
        let h = min / 60, m = min % 60
        return m > 0 ? "\(h)h\(m)m" : "\(h)h"
    }
}

private func subdivide(_ slot: WidgetSlot, durationMin: Int = 30) -> [Date] {
    var starts: [Date] = []
    var cursor = slot.start
    let durSec = TimeInterval(durationMin * 60)
    while cursor.addingTimeInterval(durSec) <= slot.end {
        starts.append(cursor)
        cursor = cursor.addingTimeInterval(durSec)
    }
    return starts
}

private func deepLink(for start: Date, durationMin: Int = 30) -> URL {
    let end = start.addingTimeInterval(TimeInterval(durationMin * 60))
    var c = URLComponents()
    c.scheme = "opentime"
    c.host = "slot"
    c.queryItems = [
        URLQueryItem(name: "start", value: String(Int(start.timeIntervalSince1970))),
        URLQueryItem(name: "end",   value: String(Int(end.timeIntervalSince1970)))
    ]
    return c.url!
}

// MARK: - Widget views (MT aesthetic)

private struct WidgetHeader: View {
    let title: String
    let meta: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline) {
                Text(title.uppercased())
                    .font(Theme.Font.display(size: 11, weight: .bold))
                    .kerning(1.8)
                    .foregroundStyle(Theme.fg)
                Spacer()
                Text(meta.uppercased())
                    .font(Theme.Font.display(size: 8, weight: .regular))
                    .kerning(2.0)
                    .foregroundStyle(Theme.muted)
            }
            Rectangle().fill(Theme.rule).frame(height: 2)
        }
    }
}

private struct WidgetDayLine: View {
    let day: WidgetDay
    let isToday: Bool
    let chipLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isToday {
                    Rectangle().fill(Theme.accent).frame(width: 2, height: 11)
                }
                Text(day.label)
                    .font(Theme.Font.display(size: 11, weight: .bold))
                    .kerning(-0.16)
                    .foregroundStyle(isToday ? Theme.accent : Theme.fg)
                Spacer()
                Text(WidgetFmt.duration(day.totalFreeMin).uppercased())
                    .font(Theme.Font.display(size: 8, weight: .regular))
                    .kerning(1.6)
                    .foregroundStyle(Theme.fg)
            }

            let chipStarts = day.freeSlots.flatMap { subdivide($0) }
            if chipStarts.isEmpty {
                Text("—")
                    .font(Theme.Font.display(size: 9, weight: .regular))
                    .foregroundStyle(Theme.dim)
            } else {
                HStack(spacing: 2) {
                    ForEach(Array(chipStarts.prefix(chipLimit).enumerated()), id: \.offset) { _, start in
                        Link(destination: deepLink(for: start)) {
                            Text(WidgetFmt.chipTime(start))
                                .font(Theme.Font.display(size: 9, weight: .medium))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .foregroundStyle(Theme.bg)
                                .background(isToday ? Theme.accent : Theme.fg)
                        }
                    }
                    if chipStarts.count > chipLimit {
                        Text("+\(chipStarts.count - chipLimit)")
                            .font(Theme.Font.display(size: 8, weight: .regular))
                            .kerning(1.4)
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
        }
    }
}

struct SmallWidgetView: View {
    let entry: AvailabilityEntry
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        if entry.needsCalendarAccess {
            WidgetAccessView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Free", meta: WidgetFmt.dateMeta.string(from: entry.date))
                ForEach(Array(entry.days.prefix(2).enumerated()), id: \.offset) { _, day in
                    WidgetDayLine(
                        day: day,
                        isToday: Calendar.current.isDate(day.date, inSameDayAs: today),
                        chipLimit: 3
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct MediumWidgetView: View {
    let entry: AvailabilityEntry
    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    var body: some View {
        if entry.needsCalendarAccess {
            WidgetAccessView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Availability", meta: WidgetFmt.dateMeta.string(from: entry.date))
                ForEach(Array(entry.days.prefix(3).enumerated()), id: \.offset) { _, day in
                    WidgetDayLine(
                        day: day,
                        isToday: Calendar.current.isDate(day.date, inSameDayAs: today),
                        chipLimit: 6
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct WidgetAccessView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CALENDAR ACCESS")
                .font(Theme.Font.display(size: 9, weight: .bold))
                .kerning(1.6)
                .foregroundStyle(Theme.muted)
            Text("Open OpenTime to grant access.")
                .font(Theme.Font.display(size: 11, weight: .regular))
                .foregroundStyle(Theme.fg)
        }
    }
}

// MARK: - Widget Definition

struct CalendarWidget: Widget {
    let kind = "CalendarWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetConfigIntent.self, provider: AvailabilityProvider()) { entry in
            WidgetContent(entry: entry)
                .containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Availability")
        .description("Editorial-style free time at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetContent: View {
    let entry: AvailabilityEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        default:
            MediumWidgetView(entry: entry)
        }
    }
}

#Preview(as: .systemSmall) {
    CalendarWidget()
} timeline: {
    AvailabilityEntry(date: .now, days: [
        WidgetDay(label: "Today", date: .now, freeSlots: [
            WidgetSlot(start: .now, end: .now.addingTimeInterval(7200)),
        ]),
        WidgetDay(label: "Tomorrow", date: .now.addingTimeInterval(86400), freeSlots: [
            WidgetSlot(start: .now, end: .now.addingTimeInterval(10800)),
        ]),
    ], needsCalendarAccess: false)
}

#Preview(as: .systemMedium) {
    CalendarWidget()
} timeline: {
    AvailabilityEntry(date: .now, days: [
        WidgetDay(label: "Today", date: .now, freeSlots: [
            WidgetSlot(start: .now, end: .now.addingTimeInterval(14400)),
        ]),
        WidgetDay(label: "Tomorrow", date: .now.addingTimeInterval(86400), freeSlots: [
            WidgetSlot(start: .now, end: .now.addingTimeInterval(10800)),
        ]),
        WidgetDay(label: "Mon", date: .now.addingTimeInterval(2 * 86400), freeSlots: [
            WidgetSlot(start: .now, end: .now.addingTimeInterval(3600 * 6)),
        ]),
    ], needsCalendarAccess: false)
}
