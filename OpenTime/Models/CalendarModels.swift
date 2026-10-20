import Foundation
import OpenTimeUI

// Type-alias so the rest of the app can keep saying `BusySlot`.
typealias BusySlot = BusySlotInfo

struct CalEvent: Identifiable {
    let id = UUID()
    let calendar: String
    let calendarColor: String?
    let summary: String
    let start: Date
    let end: Date
    let allDay: Bool
}

enum DisplaySlot: Identifiable {
    case free(FreeSlot)
    case busy(BusySlot)

    var id: UUID {
        switch self {
        case .free(let s): return s.id
        case .busy(let s): return s.id
        }
    }

    var startTime: Date {
        switch self {
        case .free(let s): return s.start
        case .busy(let s): return s.start
        }
    }
}
