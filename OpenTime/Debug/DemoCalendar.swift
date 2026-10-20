#if DEBUG
import EventKit
import Foundation

/// -seedDemoCalendar: fills the default calendar with a believable week so
/// simulator screenshots and recordings show real gaps. Debug only; seeded
/// events carry a marker in their notes and are replaced on every seeded
/// launch, so the week always starts today.
enum DemoCalendar {
    static var isRequested: Bool { CommandLine.arguments.contains("-seedDemoCalendar") }

    static let marker = "opentime-demo"

    static func seed(_ store: EKEventStore) {
        guard isRequested, let calendar = store.defaultCalendarForNewEvents else { return }
        // Clear the last seeded week, recognised by the marker in its notes.
        let cal0 = Calendar.current
        let from = cal0.date(byAdding: .day, value: -30, to: Date())!
        let to = cal0.date(byAdding: .day, value: 30, to: Date())!
        for old in store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
            where old.notes == marker {
            try? store.remove(old, span: .thisEvent, commit: false)
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // (day offset, start hour, start minute, minutes, title)
        let plan: [(Int, Int, Int, Int, String)] = [
            (0, 9, 0, 30, "Standup"), (0, 11, 0, 60, "Design review"), (0, 14, 30, 45, "1:1 with Priya"),
            (1, 9, 0, 30, "Standup"), (1, 10, 0, 90, "Roadmap planning"), (1, 13, 0, 60, "Lunch with Sam"),
            (1, 16, 0, 30, "Hiring sync"),
            (2, 9, 0, 30, "Standup"), (2, 12, 0, 60, "Customer call"), (2, 15, 0, 60, "Workshop"),
            (3, 9, 0, 30, "Standup"), (3, 10, 30, 30, "Dentist"), (3, 13, 30, 120, "Quarterly review"),
            (4, 9, 0, 30, "Standup"), (4, 11, 0, 45, "Interview"), (4, 15, 30, 60, "Team retro"),
            (6, 9, 0, 30, "Standup"), (6, 13, 0, 60, "Partner meeting"),
            (7, 9, 0, 30, "Standup"), (7, 10, 0, 60, "Board prep"), (7, 14, 0, 90, "Offsite planning"),
        ]
        for (day, h, m, minutes, title) in plan {
            guard let d = cal.date(byAdding: .day, value: day, to: today),
                  let start = cal.date(bySettingHour: h, minute: m, second: 0, of: d) else { continue }
            let e = EKEvent(eventStore: store)
            e.calendar = calendar
            e.title = title
            e.startDate = start
            e.endDate = start.addingTimeInterval(TimeInterval(minutes * 60))
            e.notes = marker
            try? store.save(e, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }
}
#endif
