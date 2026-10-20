import Foundation

/// Deterministic corrections applied to the on-device model's parse.
///
/// The ~3B Foundation model is good at understanding language but unreliable
/// at calendar arithmetic and field discipline: it resolves weekday names to
/// wrong absolute dates, drops them entirely, invents hour bounds, and echoes
/// the query into `purposeHint`. Date math and canonical day-part windows are
/// therefore recomputed here from the raw query text; the model's value is
/// only kept where the text can't decide.
public extension AvailabilityIntent {

    func normalized(query: String, now: Date) -> AvailabilityIntent {
        var out = self
        let text = " " + query.lowercased() + " "
        let cal = Calendar.current

        // MARK: Date corrections: the query text is the source of truth.

        if let target = Self.explicitDay(in: text, now: now, calendar: cal) {
            let fmt = Self.isoDay
            let expected = fmt.string(from: target)
            let modelDay = startDate.flatMap(Self.parse(date:))
            let modelMatches = modelDay.map { cal.isDate($0, inSameDayAs: target) } ?? false
            if !modelMatches {
                out.startDate = expected
                out.endDate = expected
            }
        }

        // MARK: Day-part hour clamping: only when no explicit clock time given.

        if !text.contains(where: \.isNumber) {
            for (word, window) in Self.dayParts where Self.containsWord(word, in: text) {
                out.startHour = window.lowerBound
                out.endHour = window.upperBound
                break
            }
        }

        // MARK: Field hygiene.

        if let d = out.durationMin, d <= 0 {
            out.durationMin = nil
        }
        if let hint = out.purposeHint,
           hint.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
               == query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            out.purposeHint = nil
        }

        return out
    }

    // MARK: - Internals (visible for testing)

    /// The single day the query names outright, or nil when the text doesn't
    /// pin one down (no day words, several weekdays, plural forms).
    private static func explicitDay(in text: String, now: Date, calendar cal: Calendar) -> Date? {
        if containsWord("today", in: text) { return now }
        if containsWord("tomorrow", in: text) {
            return cal.date(byAdding: .day, value: 1, to: now)
        }

        let named = weekdays.filter { containsWord($0.name, in: text) || containsWord($0.abbrev, in: text) }
        guard named.count == 1, let day = named.first else { return nil }

        let todayIndex = cal.component(.weekday, from: now)
        var offset = (day.index - todayIndex + 7) % 7
        // "next friday" said on a Friday means a week out; bare "friday" means today.
        if offset == 0 && (containsWord("next \(day.name)", in: text) || containsWord("next \(day.abbrev)", in: text)) {
            offset = 7
        }
        return cal.date(byAdding: .day, value: offset, to: now)
    }

    /// Word-boundary containment: `word` must not be embedded in a longer
    /// letter run, so "fri" matches "on fri?" but not "friday"/"fridays".
    private static func containsWord(_ word: String, in text: String) -> Bool {
        var search = text.startIndex
        while let r = text.range(of: word, range: search..<text.endIndex) {
            let beforeOK = r.lowerBound == text.startIndex || !text[text.index(before: r.lowerBound)].isLetter
            let afterOK = r.upperBound == text.endIndex || !text[r.upperBound].isLetter
            if beforeOK && afterOK { return true }
            search = text.index(after: r.lowerBound)
        }
        return false
    }

    /// Gregorian weekday indices as used by `Calendar.component(.weekday,_:)` (1 = Sunday).
    private static let weekdays: [(name: String, abbrev: String, index: Int)] = [
        ("sunday", "sun", 1), ("monday", "mon", 2), ("tuesday", "tue", 3),
        ("wednesday", "wed", 4), ("thursday", "thu", 5), ("friday", "fri", 6),
        ("saturday", "sat", 7),
    ]

    /// Canonical windows, matching the parser instructions.
    private static let dayParts: [(String, ClosedRange<Int>)] = [
        ("morning", 8...12), ("afternoon", 12...17), ("evening", 17...22),
    ]

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()
}
