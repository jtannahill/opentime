import Foundation

public enum QueryFilter {

    /// Strict filter. Returns only days/slots that satisfy every populated
    /// field of `intent`. Past slots (start <= now) are always excluded.
    public static func filter(
        days: [DayAvailability],
        intent: AvailabilityIntent,
        now: Date
    ) -> [DayAvailability] {

        let cal = Calendar.current
        let dateRange = intent.requestedRange(now: now)

        var out: [DayAvailability] = []

        for day in days {
            // Date filter — skip days outside the requested range.
            if let range = dateRange {
                let startDay = cal.startOfDay(for: range.start)
                let endDay   = cal.startOfDay(for: range.end)
                let thisDay  = cal.startOfDay(for: day.date)
                if thisDay < startDay || thisDay > endDay { continue }
            }

            // Per-slot pipeline: drop past, intersect with time bounds, check duration.
            var keptSlots: [FreeSlot] = []
            for raw in day.freeSlots {
                guard let trimmed = intersect(slot: raw, intent: intent, dayStart: cal.startOfDay(for: day.date)) else { continue }
                if trimmed.end <= now { continue }
                let startOrNow = max(trimmed.start, now)
                let usable = FreeSlot(start: startOrNow, end: trimmed.end)
                if let minDur = intent.durationMin, usable.durationMin < minDur { continue }
                keptSlots.append(usable)
            }

            guard !keptSlots.isEmpty else { continue }
            out.append(DayAvailability(date: day.date, freeSlots: keptSlots, busySlots: day.busySlots))
        }

        return out
    }

    /// Intersect `slot` with the `startHour..endHour` window on the same calendar day.
    /// Returns nil if either bound makes the window empty.
    private static func intersect(slot: FreeSlot, intent: AvailabilityIntent, dayStart: Date) -> FreeSlot? {
        let cal = Calendar.current
        var lo = slot.start
        var hi = slot.end

        if let h = intent.startHour {
            guard let bound = cal.date(byAdding: .hour, value: h, to: dayStart) else { return nil }
            if bound > lo { lo = bound }
        }
        if let h = intent.endHour {
            guard let bound = cal.date(byAdding: .hour, value: h, to: dayStart) else { return nil }
            if bound < hi { hi = bound }
        }

        return lo < hi ? FreeSlot(start: lo, end: hi) : nil
    }
}
