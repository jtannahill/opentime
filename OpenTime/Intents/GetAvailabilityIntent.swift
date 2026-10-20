import AppIntents

struct GetAvailabilityIntent: AppIntent {
    static var title: LocalizedStringResource = "Get My Availability"
    static var description = IntentDescription("Check your free time slots for a date range")

    @Parameter(title: "Time Range", default: .thisWeek)
    var timeRange: AvailabilityRange

    static var parameterSummary: some ParameterSummary {
        Summary("Get availability for \(\.$timeRange)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let helper = IntentCalendarHelper()
        guard await helper.requestAccess() else {
            return .result(dialog: "I need calendar access to check your availability. Please open Open Time to grant access.")
        }

        let days = helper.loadDays(for: timeRange)
        if days.isEmpty {
            return .result(dialog: "No weekdays found for \(timeRange.label).")
        }

        let text = helper.formatDays(days)
        return .result(dialog: "\(text)")
    }
}
