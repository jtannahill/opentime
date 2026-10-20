import WidgetKit
import SwiftUI
import OpenTimeUI

@main
struct CalendarWidgetBundle: WidgetBundle {
    init() {
        FontRegistration.registerNHG()
    }

    var body: some Widget {
        CalendarWidget()
        AvailabilityLiveActivity()
    }
}
