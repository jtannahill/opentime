import AppIntents
import UIKit

struct ShareAvailabilityIntent: AppIntent {
    static var title: LocalizedStringResource = "Share My Availability"
    static var description = IntentDescription("Copy your availability to the clipboard so you can paste it anywhere")

    @Parameter(title: "Time Range", default: .thisWeek)
    var timeRange: AvailabilityRange

    static var parameterSummary: some ParameterSummary {
        Summary("Share availability for \(\.$timeRange)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let helper = IntentCalendarHelper()
        guard await helper.requestAccess() else {
            return .result(dialog: "I need calendar access. Please open Open Time to grant access.")
        }

        let days = helper.loadDays(for: timeRange)
        if days.isEmpty {
            return .result(dialog: "No weekdays found for \(timeRange.label).")
        }

        let text = "Here's my availability:\n" + helper.formatDays(days)
        UIPasteboard.general.string = text
        return .result(dialog: "Copied to clipboard! Paste it wherever you'd like.\n\n\(text)")
    }
}
