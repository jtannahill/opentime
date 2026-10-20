import Foundation

public enum QuerySuggest {

    public struct Suggestion: Sendable {
        public let slot: FreeSlot
        public let day: Date
        public let relaxedFields: [RelaxedField]
    }

    public enum RelaxedField: Equatable, Sendable {
        case date, timeOfDay, duration
    }

    /// Called only when `QueryFilter.filter` returns empty. Tries relaxing
    /// one constraint at a time in this priority order: timeOfDay → duration → date.
    /// Returns the earliest matching slot, or nil if nothing even loosely fits.
    /// Never returns a slot before the requested date.
    public static func closest(
        days: [DayAvailability],
        intent: AvailabilityIntent,
        now: Date
    ) -> Suggestion? {

        let requestedStart = intent.requestedRange(now: now)?.start

        // Step 1: relax timeOfDay (drop startHour/endHour).
        var s1 = intent
        s1.startHour = nil
        s1.endHour   = nil
        if let hit = earliest(days: days, intent: s1, now: now, lowerBound: requestedStart) {
            return Suggestion(slot: hit.slot, day: hit.day, relaxedFields: [.timeOfDay])
        }

        // Step 2: relax duration (keep date + time bounds).
        var s2 = intent
        s2.durationMin = nil
        if let hit = earliest(days: days, intent: s2, now: now, lowerBound: requestedStart) {
            return Suggestion(slot: hit.slot, day: hit.day, relaxedFields: [.duration])
        }

        // Step 3: relax date (keep time + duration). Search forward from
        // the requested date — never before it.
        var s3 = intent
        s3.startDate = nil
        s3.endDate   = nil
        if let hit = earliest(days: days, intent: s3, now: now, lowerBound: requestedStart) {
            return Suggestion(slot: hit.slot, day: hit.day, relaxedFields: [.date])
        }

        return nil
    }

    private struct Hit { let slot: FreeSlot; let day: Date }

    private static func earliest(
        days: [DayAvailability],
        intent: AvailabilityIntent,
        now: Date,
        lowerBound: Date?
    ) -> Hit? {
        let filtered = QueryFilter.filter(days: days, intent: intent, now: now)
        let cal = Calendar.current
        let lb = lowerBound.map { cal.startOfDay(for: $0) }

        for day in filtered.sorted(by: { $0.date < $1.date }) {
            if let lb = lb, cal.startOfDay(for: day.date) < lb { continue }
            if let slot = day.freeSlots.sorted(by: { $0.start < $1.start }).first {
                return Hit(slot: slot, day: day.date)
            }
        }
        return nil
    }
}
