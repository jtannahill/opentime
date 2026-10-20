import Foundation
#if canImport(FoundationModels) && os(iOS)
import FoundationModels
#endif

public enum QueryParser {

    /// Returns true when the on-device language model is currently available.
    /// Note: this collapses transient states (e.g., `.notAvailable(.modelNotReady)`
    /// while the model is still downloading) into `false`. Callers that hide UI
    /// based on this value should re-check after a delay or on app foreground
    /// rather than treat a single `false` as permanent.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels) && os(iOS)
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default: return false
        }
        #else
        return false
        #endif
    }

    /// Parses a free-form query into a structured `AvailabilityIntent`.
    /// `now` is injected into the model instructions so relative phrases
    /// like "next Tuesday" resolve consistently.
    public static func parse(_ text: String, now: Date) async throws -> AvailabilityIntent {
        #if canImport(FoundationModels) && os(iOS)
        let session = LanguageModelSession(instructions: instructions(now: now))
        let response = try await session.respond(to: text, generating: AvailabilityIntent.self)
        return response.content.normalized(query: text, now: now)
        #else
        return AvailabilityIntent().normalized(query: text, now: now)
        #endif
    }

    /// Visible for inspection.
    static func instructions(now: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let today = f.string(from: now)

        let weekdayFmt = DateFormatter()
        weekdayFmt.dateFormat = "EEEE"
        weekdayFmt.locale = Locale(identifier: "en_US_POSIX")
        let weekday = weekdayFmt.string(from: now)

        return """
        You parse a user's free-form question about their calendar availability \
        into a structured intent. Today is \(today) (\(weekday)).

        Rules:
        - startDate / endDate: absolute YYYY-MM-DD dates. Resolve "today", "tomorrow", \
        "next Tuesday", "this weekend", "end of next month", etc. against today's date. \
        Ambiguous weekdays mean the NEXT future occurrence. Single-day queries set both fields equal.
        - "This week" = Monday through the coming Sunday.
        - "Next week" = Monday through Sunday of the following week.
        - "Weekend" = Saturday–Sunday.
        - startHour / endHour: 24-hour integers. "Morning" = 8–12, "afternoon" = 12–17, \
        "evening" = 17–22. "After 2pm" -> startHour 14. "Before noon" -> endHour 12.
        - durationMin: minutes the user wants free. "An hour" = 60. "Quick 15" = 15. \
        Nil if no duration was stated — never 0.
        - Leave startHour nil unless the user gave a start bound, and endHour nil \
        unless the user gave an end bound. Do not invent bounds.
        - purposeHint: short label like "coffee" or "call with Anna" if the user gave one. \
        Display only — don't infer it from a duration alone, and never copy the whole query into it.
        - If the user said no date at all, leave startDate and endDate nil.
        - Respond with the structured intent only.
        """
    }
}
