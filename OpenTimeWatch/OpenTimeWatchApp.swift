import SwiftUI

@main
struct OpenTimeWatchApp: App {
    init() {
        WatchWorkHoursSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
