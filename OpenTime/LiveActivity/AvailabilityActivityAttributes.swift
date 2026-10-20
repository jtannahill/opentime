import ActivityKit
import Foundation

struct AvailabilityActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let currentStatus: String
        let statusDetail: String
        let nextSlotLabel: String
        let nextSlotTime: String
        let totalFreeMinRemaining: Int
    }

    let workdayEnd: String
}
