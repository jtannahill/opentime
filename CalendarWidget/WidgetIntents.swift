import AppIntents
import WidgetKit

enum WidgetRange: String, AppEnum {
    case todayTomorrow
    case thisWeek
    case nextWeek

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget Range")
    static var caseDisplayRepresentations: [WidgetRange: DisplayRepresentation] = [
        .todayTomorrow: "Today & Tomorrow",
        .thisWeek: "This Week",
        .nextWeek: "Next Week",
    ]
}

struct WidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configure Availability"
    static var description = IntentDescription("Choose which days to show")

    @Parameter(title: "Range", default: .todayTomorrow)
    var range: WidgetRange
}

struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Availability"
    static var description = IntentDescription("Refresh the availability widget")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
