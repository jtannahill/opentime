import AppIntents

struct OpenTimeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetAvailabilityIntent(),
            phrases: [
                "What's my availability in \(.applicationName)",
                "Check my \(.applicationName) for \(\.$timeRange)",
                "Show my free time in \(.applicationName)",
                "When am I free in \(.applicationName)",
            ],
            shortTitle: "Get Availability",
            systemImageName: "calendar.badge.clock"
        )
        AppShortcut(
            intent: ShareAvailabilityIntent(),
            phrases: [
                "Share my availability from \(.applicationName)",
                "Copy my \(.applicationName) for \(\.$timeRange)",
            ],
            shortTitle: "Share Availability",
            systemImageName: "square.and.arrow.up"
        )
    }
}
