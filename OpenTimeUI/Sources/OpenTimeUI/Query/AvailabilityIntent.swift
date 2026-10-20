import Foundation
#if canImport(FoundationModels) && os(iOS)
import FoundationModels
#endif

#if canImport(FoundationModels) && os(iOS)
@Generable
public struct AvailabilityIntent: Codable, Sendable {
    @Guide(description: "Start date (YYYY-MM-DD) of the range the user is asking about. Resolve relative phrases like 'next Tuesday' or 'end of next month' against the current date provided in instructions.")
    public var startDate: String?

    @Guide(description: "End date (YYYY-MM-DD) of the range, inclusive. Equal to startDate for a single day. Nil if no date was mentioned.")
    public var endDate: String?

    @Guide(description: "Earliest hour the slot may start (0-23). E.g., 'after 2pm' -> 14, 'morning' -> 8.")
    public var startHour: Int?

    @Guide(description: "Latest hour the slot may end (1-24). E.g., 'before noon' -> 12, 'afternoon' -> 17.")
    public var endHour: Int?

    @Guide(description: "Minimum free block length in minutes, if user mentioned a duration ('30 min', 'an hour', 'quick 15').")
    public var durationMin: Int?

    @Guide(description: "Short free-text purpose if user gave one ('coffee', 'a call with Anna'). Optional, for display only.")
    public var purposeHint: String?

    public init() {}
}
#else
public struct AvailabilityIntent: Codable, Sendable {
    public var startDate: String?
    public var endDate: String?
    public var startHour: Int?
    public var endHour: Int?
    public var durationMin: Int?
    public var purposeHint: String?
    public init() {}
}
#endif

public extension AvailabilityIntent {

    /// The concrete date span the user asked about, or nil if the
    /// query didn't mention a date at all. Single-day queries return
    /// (start, end) where both fall on the same calendar day.
    func requestedRange(now: Date) -> (start: Date, end: Date)? {
        guard let startStr = startDate, let start = Self.parse(date: startStr) else {
            return nil
        }
        let end: Date
        if let endStr = endDate, let parsed = Self.parse(date: endStr) {
            end = parsed
        } else {
            end = start
        }
        return (start, end)
    }

    /// Human-readable summary used by `QueryResultBanner`.
    /// Example: "TUE APR 21 · AFTER 2PM · 60 MIN · COFFEE".
    func summary(now: Date) -> String {
        var parts: [String] = []

        if let range = requestedRange(now: now) {
            parts.append(Self.dateLabel(start: range.start, end: range.end, now: now))
        }

        let effectiveEnd = endHour.flatMap { $0 < 24 ? $0 : nil }
        if let lo = startHour, let hi = effectiveEnd {
            parts.append("\(Self.hourLabel(lo))–\(Self.hourLabel(hi))")
        } else if let lo = startHour {
            parts.append("AFTER \(Self.hourLabel(lo))")
        } else if let hi = effectiveEnd {
            parts.append("BEFORE \(Self.hourLabel(hi))")
        }

        if let mins = durationMin {
            parts.append("\(mins) MIN")
        }

        if let purpose = purposeHint, !purpose.isEmpty {
            parts.append(purpose.uppercased())
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Internal helpers (visible for testing)

    /// YYYY-MM-DD is interpreted in the user's local time zone so that
    /// midnight aligns with `Calendar.current` for downstream day comparisons.
    private static let parseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func parse(date: String) -> Date? {
        parseFormatter.date(from: date)
    }

    static func dateLabel(start: Date, end: Date, now: Date) -> String {
        let cal = Calendar.current
        let isRange = !cal.isDate(start, inSameDayAs: end)

        if !isRange {
            if cal.isDate(start, inSameDayAs: now) { return "TODAY" }
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: now),
               cal.isDate(start, inSameDayAs: tomorrow) { return "TOMORROW" }
            return Self.shortDate(start)
        }
        return "\(Self.shortDate(start))–\(Self.shortDate(end))"
    }

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    static func shortDate(_ d: Date) -> String {
        shortFormatter.string(from: d).uppercased()
    }

    /// 14 -> "2PM", 12 -> "12PM", 0 -> "12AM", 9 -> "9AM".
    static func hourLabel(_ hour: Int) -> String {
        let h = hour % 24
        if h == 0  { return "12AM" }
        if h == 12 { return "12PM" }
        if h < 12  { return "\(h)AM" }
        return "\(h - 12)PM"
    }
}
