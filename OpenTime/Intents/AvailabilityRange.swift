import AppIntents

enum AvailabilityRange: String, AppEnum {
    case today
    case tomorrow
    case thisWeek
    case nextWeek
    case next14Days

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Time Range")

    static var caseDisplayRepresentations: [AvailabilityRange: DisplayRepresentation] = [
        .today: "Today",
        .tomorrow: "Tomorrow",
        .thisWeek: "This Week",
        .nextWeek: "Next Week",
        .next14Days: "Next 14 Days",
    ]

    var label: String {
        switch self {
        case .today: return "today"
        case .tomorrow: return "tomorrow"
        case .thisWeek: return "this week"
        case .nextWeek: return "next week"
        case .next14Days: return "the next 14 days"
        }
    }
}
