import EventKit
import Foundation

/// Which calendar events take up time, shared by every surface so the app,
/// widget, extensions and Live Activity never disagree about a day.
///
/// The safe failure for an availability app is looking busy, never falsely
/// free, so anything unclear blocks.
public enum BusyRules {

    /// The facts about an event that decide whether it takes time. Kept
    /// separate from EKEvent so the rules are testable without a store.
    public struct EventFacts: Sendable, Equatable {
        public enum Availability: Sendable, Equatable { case busy, free, tentative, unavailable, notSupported }

        public let start: Date
        public let end: Date
        public let allDay: Bool
        public let availability: Availability
        /// The current user was invited and declined.
        public let declined: Bool

        public init(start: Date, end: Date, allDay: Bool,
                    availability: Availability = .busy, declined: Bool = false) {
            self.start = start
            self.end = end
            self.allDay = allDay
            self.availability = availability
            self.declined = declined
        }
    }

    /// Declined invites and events marked Free never block. A timed event
    /// otherwise blocks. An all-day event blocks only when it says so
    /// (Busy or Out of Office): holidays and birthdays arrive as all-day
    /// Free and should not wipe out a day.
    public static func blocks(_ e: EventFacts) -> Bool {
        if e.declined || e.availability == .free { return false }
        if e.allDay { return e.availability == .busy || e.availability == .unavailable }
        return true
    }

    /// The blocking events that touch `day`, as timed spans. An event that
    /// started on an earlier day still blocks the days it runs into, and a
    /// blocking all-day event covers the whole day.
    public static func blocking(_ events: [EventFacts], on day: Date,
                                calendar: Calendar = .current) -> [TimedEvent] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events.compactMap { e in
            guard blocks(e), e.start < dayEnd, e.end > dayStart else { return nil }
            if e.allDay { return TimedEvent(start: dayStart, end: dayEnd) }
            return TimedEvent(start: max(e.start, dayStart), end: min(e.end, dayEnd))
        }
    }

    /// Today's free time starts now, rounded up to the next quarter hour;
    /// what is left of a slot shorter than `minimum` is dropped. Other days
    /// pass through untouched.
    public static func trimPast(_ free: [AvailabilityEngine.Interval], now: Date,
                                minimum: TimeInterval = 15 * 60,
                                calendar: Calendar = .current) -> [AvailabilityEngine.Interval] {
        let quarter: TimeInterval = 15 * 60
        let rounded = Date(timeIntervalSinceReferenceDate:
            (now.timeIntervalSinceReferenceDate / quarter).rounded(.up) * quarter)
        return free.compactMap { slot in
            guard slot.end > now else { return nil }
            let start = max(slot.start, rounded)
            return slot.end.timeIntervalSince(start) >= minimum
                ? AvailabilityEngine.Interval(start: start, end: slot.end) : nil
        }
    }
}

public extension BusyRules.EventFacts {
    init(_ event: EKEvent) {
        let availability: Availability = switch event.availability {
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        case .notSupported: .notSupported
        default: .busy
        }
        let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        self.init(start: event.startDate, end: event.endDate, allDay: event.isAllDay,
                  availability: availability, declined: declined)
    }
}

public extension BusyRules {
    /// Convenience for surfaces holding EKEvents.
    static func blocking(_ events: [EKEvent], on day: Date, calendar: Calendar = .current) -> [TimedEvent] {
        blocking(events.map(EventFacts.init), on: day, calendar: calendar)
    }
}
